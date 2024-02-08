#!/bin/bash

# Convert numerical boolean to string boolean
function NumToStingBoolean() {
  if [[ "$1" == 1 ]]; then
    echo "true"
  else
    echo "false"
  fi
}

# Convert string boolean to numerical boolean
function StringToNumBoolean() {
  if [[ "$1" == "true" ]]; then
    echo "1"
  else
    echo "0"
  fi
}

#
# Test if type is correct
# INPUT : TYPE
#
function GoodType() {
  local TYPE=$1
  if [[ "$TYPE" =~ ^(string|data|int|float|bool|date|array|array-add|dict|dict-add)$ ]]; then
    # Good type
    return 1
  else
    # Type is not correct
    return 0
  fi
}

################################################################################
#                                                                              #
#                                  OPTIONS                                     #
#                                                                              #
################################################################################


POSITIONAL=()

## Define default CSV File configuration ##
if [[ -z $INPUT ]]; then #if INPUT is empty
  INPUT='lists/ataumo.csv'
fi
## If CSV file does not exist
if [ ! -f $INPUT ]; then
  echo "$INPUT file not found";
  exit 99;
fi

set -- "${POSITIONAL[@]}" # restore positional parameters

RES_FILE='mac_config_backup.csv'

# CSV backup file initialisation
echo $ID,$Category,$Name,$AssessmentStatus,$Method,$MethodOption,$GetCommand,$SetCommand,$User,$RegistryPath,$RegistryItem,$DefaultValue,$RecommendedValue,$TypeValue,$Operator,$Severity,$Level > $RES_FILE


################################################################################
#                                                                              #
#                                 MAIN CODE                                    #
#                                                                              #
################################################################################

# Close any open System Preferences panes, to prevent them from overriding settings we re about to change
osascript -e 'tell application "System Preferences" to quit'

# Ask for the administrator password upfront
sudo -v

#
# Verify all Apple provided software is current
#
ID='1000'

EXPECTED_OUTPUT_SOFTWARE_UPDATE="SoftwareUpdateToolFindingavailablesoftware"
COMMAND="softwareupdate -l"
ReturnedValue=$(eval "$COMMAND" 2>/dev/null) # throw away stderr
ReturnedValue=${ReturnedValue//[[:space:]]/} # we remove all white space

if [[ "$ReturnedValue" == "$EXPECTED_OUTPUT_SOFTWARE_UPDATE" ]]; then
  ResultValue="Passed"
else
  ResultValue="Failed"
fi


### Global varibles
PRECEDENT_CATEGORY=''
PRECEDENT_SUBCATEGORY=''

while read -r ID Category Name AssessmentStatus Method MethodOption GetCommand SetCommand SudoUser RegistryPath RegistryItem DefaultValue RecommendedValue TypeValue Operator Severity Level
do
	## Print first raw with categories
	if [[ $ID == "ID" ]]; then
		ActualValue="Actual"
		RecommendedValue="Recommended"
		FIRSTROW=$(printf "%6s %9s %55s %s \n" "$ID" "$Name" "$ActualValue" "$RecommendedValue")
		
	else

		if [[ "$TypeValue" == "bool" ]]; then
			RecommendedValue=$(StringToNumBoolean "$RecommendedValue")
			DefaultValue=$(StringToNumBoolean "$DefaultValue")
		fi

		#
		# Print category
		#
		if [[ "$PRECEDENT_CATEGORY" != "$Category" ]]; then
			PRECEDENT_CATEGORY=$Category
		fi

		#
		# Print subcategory
		#
		SubCategory=${Name%:*} # retain the part before the colon
		Name=${Name##*:} # retain the part after the colon
		if [[ "$PRECEDENT_SUBCATEGORY" != "$SubCategory" ]]; then
			PRECEDENT_SUBCATEGORY=$SubCategory
		fi

		###################################
		#          CASE METHODS           #
		###################################
		# 
		# Registry
		#
		if [[ "$Method" == "Registry" ]]; then

			# command
			COMMAND="defaults $MethodOption read $RegistryPath $RegistryItem"

			ReturnedValue=$(eval "$COMMAND" 2>/dev/null) # throw away stderr
			ReturnedExit=$?

			# if an error occurs, it's caused by non-existance of the couple (file,item)
			# we will not consider this as an error, but as an warning
			if [[ "$ReturnedExit" == 1 ]]; then
				ReturnedExit=26
				ReturnedValue="$DefaultValue"
			fi

		# 
		# PlistBuddy
		#
		elif [[ $Method == "PlistBuddy" ]]; then

			# command
			COMMAND="/usr/libexec/PlistBuddy $MethodOption \"Print $RegistryItem\" $RegistryPath"

			ReturnedValue=$(eval "$COMMAND" 2>/dev/null) # throw away stderr
			ReturnedExit=$?

			# if an error occurs, it's caused by non-existance of the couple (file,item)
			# we will not consider this as an error, but as an warning
			if [[ $ReturnedExit == 1 ]]; then
				ReturnedExit=26
				ReturnedValue="$DefaultValue"
			fi

		# 
		# launchctl
		#
		elif [[ "$Method" == "launchctl" ]]; then

			# command
			COMMAND="launchctl print system/$RegistryItem"

			# print command in verbose mode
			ReturnedValue=$(eval "$COMMAND" 2>/dev/null) # throw away stderr
			ReturnedExit=$?

			# if an error occurs (113 code), it's caused by non-existance of the RegistryItem in system
			# so, it's not enabled
			if [[ $ReturnedExit == 1 ]]; then
				ReturnedExit=26
				ReturnedValue="$DefaultValue"
			elif [[ $ReturnedExit == 113 ]]; then
				ReturnedExit=0
				ReturnedValue="disable"
			else
				ReturnedValue="enable"
			fi

		# 
		# csrutil (Intergrity Protection)
		#
		elif [[ $Method == "csrutil" ]]; then

			# command
			COMMAND="csrutil $GetCommand"

			# print command in verbose mode
			ReturnedValue=$(eval "$COMMAND" 2>/dev/null)
			ReturnedExit=$?

			# clean retuned value
			if [[ $ReturnedValue == "System Integrity Protection status: enabled." ]]; then
				ReturnedValue="enable"
			else
				ReturnedValue="disable"
			fi

		# 
		# spctl (Gatekeeper)
		#
		elif [[ $Method == "spctl" ]]; then

			# command
			COMMAND="spctl $GetCommand"

			# print command in verbose mode
			ReturnedValue=$(eval "$COMMAND" 2>/dev/null)
			ReturnedExit=$?

			# clean retuned value
			if [[ $ReturnedValue == "assessments enabled" ]]; then
				ReturnedValue="enable"
			else
				ReturnedValue="disable"
			fi

		# 
		# systemsetup
		#
		elif [[ $Method == "systemsetup" ]]; then

			# command
			COMMAND="sudo systemsetup $GetCommand"

			ReturnedValue=$(eval "$COMMAND" 2>/dev/null)
			ReturnedExit=$?

			# clean retuned value
			ReturnedValue="${ReturnedValue##*:}" # get content after ":"
			ReturnedValue=$(echo "$ReturnedValue" | tr '[:upper:]' '[:lower:]') # convert to lowercase
			ReturnedValue="${ReturnedValue:1}" # remove first char (space)

		# 
		# pmset
		#
		elif [[ $Method == "pmset" ]]; then

			# command
			COMMAND="pmset -g | grep $RegistryItem"

			ReturnedValue=$(eval "$COMMAND" 2>/dev/null)
			ReturnedExit=$?

			# clean returned value
			ReturnedValue="${ReturnedValue//[[:space:]]/}" # we remove all white space
			ReturnedValue="${ReturnedValue#"$RegistryItem"}" # get content after RegistryItem

		# 
		# fdesetup (FileVault)
		#
		elif [[ "$Method" == "fdesetup" ]]; then

			# command
			COMMAND="fdesetup $GetCommand"

			ReturnedValue=$(eval "$COMMAND" 2>/dev/null)
			ReturnedExit=$?

			# clean retuned value
			if [[ "$ReturnedValue" == "FileVault is Off." ]]; then
				ReturnedValue="disable"
			else
				ReturnedValue="enable"
			fi

		# 
		# nvram
		#
		elif [[ "$Method" == "nvram" ]]; then

			# command
			# we add '|| true' because grep return 1 when it does not find RegistryItem
			COMMAND="nvram -p | grep -c '$RegistryItem' || true"

			ReturnedValue=$(eval "$COMMAND" 2>/dev/null)
			ReturnedExit=$?

		# 
		# AssetCacheManagerUtil
		#
		elif [[ "$Method" == "AssetCacheManagerUtil" ]]; then

			# command
			COMMAND="sudo AssetCacheManagerUtil $GetCommand"

			ReturnedValue=$(eval "$COMMAND" 2>/dev/null)
			ReturnedExit=$?

			# when this command return 1 it's not an error, it's just beacause cache saervice is deactivated
			if [[ "$ReturnedExit" == '1' ]]; then
				ReturnedExit=0
				ReturnedValue='deactivate'
			else
				ReturnedValue='activate'
			fi
		fi
		echo $ID,$Category,$Name,$AssessmentStatus,$Method,$MethodOption,$GetCommand,$SetCommand,$User,$RegistryPath,$RegistryItem,$DefaultValue,$RecommendedValue,$TypeValue,$Operator,$Severity,$Level >> $RES_FILE
	fi
  fi
  # Out of main condition to take first line of csv file
  # reset some values
  ReturnedExit=""
  ReturnedValue=""
  ResultValue=""
done < $INPUT

