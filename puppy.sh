#!/bin/bash


function Usage() {
  echo "Usages: "
  echo "  ./puppy.sh -h"
  echo "  ./puppy.sh [mode]"
  echo "  ./puppy.sh [mode [options]]"
  echo "  ./puppy.sh [mode] [file <file.csv>]"
  echo "  ./puppy.sh [mode [options]] [global options] [file <file.csv>]"
  echo "    -a | --audit                : audit configuration"
  echo "    -b | --backup               : save your configuration in csv file"
  echo "    -H | --harden               : to harden a configuration"

}

function Save() {
  echo "$1" >> "$BACKUPFILE"
}
#
# Convertor functions
# 

function AuditBeforeReinforce() {
  case $ReturnedExit in
    0|26 )#No Error
    if [[ "$RecommendedValue" == "$ReturnedValue" ]]; then
      APPLYHARDEN=0
    else
      case $Severity in
        "Hight" )
        APPLYHARDEN=1
          ;;
        "Medium" )
        APPLYHARDEN=2
          ;;
        "Low" )
        APPLYHARDEN=3
          ;;
      esac
    fi
      ;;

    1 )#Error Exec
    APPLYHARDEN=0
      ;;

  esac
}

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

#
# Transform generic sudo option with correct option
# Example : -u <usename> -> -u steavejobs
#
function SudoUserFilter() {
  case $SudoUser in
    "username" )
      SudoUser="$(logname)"
      ;;
    *)
      SudoUser="root"
      ;;
  esac
}

function WriteToCsv () {
  case $Operator in
    "=" )
    if [[ $1 != $2 ]]; then
      ResultValue="Failed"
    else 
      ResultValue="Passed"
    fi
      ;;
    "<=" )
    if [[ $1 > $2 ]]; then
      ResultValue="Failed"
    else 
      ResultValue="Passed"
    fi
      ;;
    ">=" )
    if [[ $1 < $2 ]]; then
      ResultValue="Failed"
    else 
      ResultValue="Passed"
    fi
      ;;
    "" )
    if [[ $1 != $2 ]]; then
      ResultValue="Failed"
    else 
      ResultValue="Passed"
    fi
      ;;
  esac

  # Put data in the csv file
  echo $ID,$Category,$SubCategory,$DefaultValue,$RecommendedValue,$ReturnedValue,$ResultValue,$Level,$Severity >> hardeningpuppy_report_0.1.csv

}

################################################################################
#                                                                              #
#                                  OPTIONS                                     #
#                                                                              #
################################################################################


POSITIONAL=()
SKIP_UPDATE=false
VERBOSE=false
MODE="AUDIT"

while [[ $# -gt 0 ]]; do
  key="$1"

  case $key in
    -h|--help)
      Usage
      exit 1
      ;;
    -a|--audit)
      MODE="AUDIT"
      shift # past argument
      ;;
      ;;
    -H|--harden)
      MODE="HARDEN"
      shift # past argument
      ;;
    -b|--backup)
      MODE="BACKUP"
      shift # past argument
      ;;
    *)    # unknown option
      POSITIONAL+=("$1") # save it in an array for later
      shift # past argument
      ;;
  esac
done

## Define default CSV File configuration ##
if [[ -z $INPUT ]]; then #if INPUT is empty
  INPUT='lists/ataumo.csv'
fi

set -- "${POSITIONAL[@]}" # restore positional parameters

if [[ "$MODE" == "BACKUP" ]]; then
  #BACKUPFILE=$(date +"backup-$USER-%y%m%d-%H%M.csv")
  BACKUPFILE="backup.csv"
  # remove file if it already exit
  if [[ -f "$BACKUPFILE" ]]; then
    rm "$BACKUPFILE"
  fi

  Save "ID,Category,Name,AssessmentStatus,Method,MethodOption,GetCommand,SetCommand,User,RegistryPath,RegistryItem,DefaultValue,RecommendedValue,TypeValue,Operator,Severity,Level"
fi

################################################################################
#                                                                              #
#                                 MAIN CODE                                    #
#                                                                              #
################################################################################

# Close any open System Preferences panes, to prevent them from overriding settings we re about to change
osascript -e 'tell application "System Preferences" to quit'

# Ask for the administrator password upfront
sudo -v


## Initialize CSV file
echo 'ID,"Category","Name","Result","Recommended","TestResult","ResultValue","Severity"' > hardeningpuppy_report_0.1.csv

if [[ "$MODE" == "HARDEN" ]]; then
  read -p "Are you sure to run HARDEN mode ? [y/N] " -n 1 -r
  echo    # (optional) move to a new line
  if [[ ! $REPLY =~ ^[Yy]$ ]]
  then
      exit 1
  fi
fi

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

echo $ID,$Category,$SubCategory,,,,$ResultValue,$Level,$Severity >> hardeningpuppy_report_0.1.csv



### Global varibles
PRECEDENT_CATEGORY=''
PRECEDENT_SUBCATEGORY=''

## Save old separator
OLDIFS=$IFS
## Define new separator
IFS=','
## If CSV file does not exist
if [ ! -f $INPUT ]; then
  echo "$INPUT file not found";
  exit 99;
fi
while read -r ID Category Name AssessmentStatus Method MethodOption GetCommand SetCommand SudoUser RegistryPath RegistryItem DefaultValue RecommendedValue TypeValue Operator Severity Level
do
  ## Print first raw with categories
  if [[ $ID == "ID" ]]; then
    ActualValue="Actual"
    RecommendedValue="Recommended"
    FIRSTROW=$(printf "%6s %9s %55s %s \n" "$ID" "$Name" "$ActualValue" "$RecommendedValue")
    echo -ne "$FIRSTROW"
  ## We will not take the first row
  else

    #
    ############################################################################
    #                                  AUDIT                                   #
    ############################################################################
    #
    if [[ "$MODE" == "AUDIT" || "$MODE" == "HARDEN" || "$MODE" == "BACKUP" ]]; then
      #
      # RecommendedValue and DefaultValue boolean filter
      #
      if [[ "$TypeValue" == "bool" ]]; then
        RecommendedValue=$(StringToNumBoolean "$RecommendedValue")
        DefaultValue=$(StringToNumBoolean "$DefaultValue")
      fi

      #
      # Print category
      #
      if [[ "$PRECEDENT_CATEGORY" != "$Category" ]]; then
        echo #new line
        echo "--------------------------------------------------------------------------------"
        DateValue=$(date +"%D %X")
        echo "[*] $DateValue Starting Category $Category"
        PRECEDENT_CATEGORY=$Category
      fi

      #
      # Print subcategory
      #
      SubCategory=${Name%:*} # retain the part before the colon
      Name=${Name##*:} # retain the part after the colon
      if [[ "$PRECEDENT_SUBCATEGORY" != "$SubCategory" ]]; then
        echo "------------$SubCategory"
        PRECEDENT_SUBCATEGORY=$SubCategory
      fi

      ###################################
      #        CASE METHODS             #
      ###################################


      # STATUS/AUDIT
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
        
        WriteToCsv $RecommendedValue $ReturnedValue

      # STATUS/AUDIT
      # PlistBuddy (like Registry with more options)
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

        WriteToCsv $RecommendedValue $ReturnedValue


      # STATUS/AUDIT
      # launchctl
      # intro : Interfaces with launchd to load, unload daemons/agents and generally control launchd.
      # requirements : $RegistryItem
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

        WriteToCsv $RecommendedValue $ReturnedValue

      # STATUS/AUDIT
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

        WriteToCsv $RecommendedValue $ReturnedValue


      # STATUS/AUDIT
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

        WriteToCsv $RecommendedValue $ReturnedValue


      # STATUS/AUDIT
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
      
        WriteToCsv $RecommendedValue $ReturnedValue


      # STATUS/AUDIT
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

        WriteToCsv $RecommendedValue $ReturnedValue


      # STATUS/AUDIT
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
        
        WriteToCsv $RecommendedValue $ReturnedValue

      # STATUS/AUDIT
      # nvram
      #
      elif [[ "$Method" == "nvram" ]]; then

        # command
        # we add '|| true' because grep return 1 when it does not find RegistryItem
        COMMAND="nvram -p | grep -c '$RegistryItem' || true"

        ReturnedValue=$(eval "$COMMAND" 2>/dev/null)
        ReturnedExit=$?

        WriteToCsv $RecommendedValue $ReturnedValue

      # STATUS/AUDIT
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
        
        WriteToCsv $RecommendedValue $ReturnedValue


      fi
    fi
    
    if [[ "$MODE" == "HARDEN" ]]; then

      #
      # Get audit before hardening
      # APPLYHARDEN=0 : policy is already configured to recommended value
      # APPLYHARDEN=1 : Hight policy have to be configured
      # APPLYHARDEN=2 : Medium policy have to be configured
      # APPLYHARDEN=3 : Low policy have to be configured
      #
      APPLYHARDEN=0
      AuditBeforeReinforce "$ID" "$Name" "$ReturnedExit" "$ReturnedValue" "$RecommendedValue" "$Severity"
      # echo "$ID, APPLYHARDEN ===> $APPLYHARDEN"

      if [[ "$APPLYHARDEN" != 0 && "$AssessmentStatus" != "Manually" ]]; then

        #
        # Sudo option filter
        #
        SudoUserFilter

        #
        # Print category
        #
        if [[ "$PRECEDENT_CATEGORY" != "$Category" ]]; then
          echo #new line
          DateValue=$(date +"%D %X")
          echo "[*] $DateValue Starting Category $Category"
          PRECEDENT_CATEGORY=$Category
        fi

        ###################################
        #        CASE METHODS             #
        ###################################

        #
        # Registry
        # requirements  : $MethodOption, $RegistryPath, $RegistryItem, $TypeValue, $RecommendedValue
        # optional      : $SudoUser
        #
        if [[ "$Method" == "Registry" ]]; then

          # Type filter
          if GoodType "$TypeValue"; then
            AlertMessage "this type is not correct"
            exit 1
          fi

          # Add '' around RecommendedValue when type is string
          if [[ "$TypeValue" == 'string' ]]; then
            RecommendedValue="'$RecommendedValue'"
          fi

          # Convert numerical boolean to string boolean
          if [[ "$TypeValue" == 'bool' ]]; then
            RecommendedValue=$(NumToStingBoolean "$RecommendedValue")
          fi

          # command
          COMMAND="sudo -u $SudoUser defaults $MethodOption write $RegistryPath $RegistryItem -$TypeValue $RecommendedValue"

          # keep alert error in verbose mode
          if [[ "$VERBOSE" == true ]]; then
            ReturnedValue=$(eval "$COMMAND")
          else
            ReturnedValue=$(eval "$COMMAND" 2>/dev/null) # throw away stderr
          fi
          ReturnedExit=$?

        #
        # PlistBuddy (like Registry with more options)
        # requirements : $MethodOption, $RegistryItem, $RecommendedValue, $RegistryPath
        #
        elif [[ $Method == "PlistBuddy" ]]; then

          # command
          COMMAND="sudo /usr/libexec/PlistBuddy $MethodOption \"Set $RegistryItem $RecommendedValue\" $RegistryPath"

          # print command in verbose mode
          if [[ "$VERBOSE" == true ]]; then
            ReturnedValue=$(eval "$COMMAND")
          else
            ReturnedValue=$(eval "$COMMAND" 2>/dev/null) # throw away stderr
          fi
          ReturnedExit=$?


        #
        # launchctl
        # intro : Interfaces with launchd to load, unload daemons/agents and generally control launchd.
        # requirements : $RegistryItem
        #
        elif [[ $Method == "launchctl" ]]; then

          # command
          COMMAND="sudo launchctl $RecommendedValue system/$RegistryItem"

          # print command in verbose mode
          if [[ "$VERBOSE" == true ]]; then
            ReturnedValue=$(eval "$COMMAND")
          else
            ReturnedValue=$(eval "$COMMAND" 2>/dev/null) # throw away stderr
          fi
          ReturnedExit=$?


        #
        # csrutil (Integrity Protection)
        #
        elif [[ $Method == "csrutil" ]]; then
          # "This tool needs to be executed from Recovery OS."
          ReturnedExit=13


        #
        # spctl (Gatekeeper)
        # requirements  : $RecommendedValue
        #
        elif [[ $Method == "spctl" ]]; then

          # command
          COMMAND="sudo spctl --$RecommendedValue"

          # keep alert error in verbose mode
          if [[ "$VERBOSE" == true ]]; then
            ReturnedValue=$(eval "$COMMAND")
          else
            ReturnedValue=$(eval "$COMMAND" 2>/dev/null)
          fi
          ReturnedExit=$?


        #
        # systemsetup
        #
        elif [[ $Method == "systemsetup" ]]; then

          # command
          COMMAND="sudo systemsetup $SetCommand"

          # keep alert error in verbose mode
          if [[ "$VERBOSE" == true ]]; then
            ReturnedValue=$(eval "$COMMAND")
          else
            ReturnedValue=$(eval "$COMMAND" 2>/dev/null)
          fi
          ReturnedExit=$?


        #
        # fdesetup (FileVault)
        #
        elif [[ $Method == "fdesetup" ]]; then

          # command
          COMMAND="sudo fdesetup $RecommendedValue"

          # in HARDEN mode and with this fdesetup moethod, we have to keep stdout
          ReturnedValue=$(eval "$COMMAND")
          ReturnedExit=$?


        #
        # AssetCacheManagerUtil
        #
        elif [[ $Method == "AssetCacheManagerUtil" ]]; then

          # command
          COMMAND="sudo AssetCacheManagerUtil $RecommendedValue"

          # keep alert error in verbose mode
          if [[ "$VERBOSE" == true ]]; then
            ReturnedValue=$(eval "$COMMAND")
          else
            ReturnedValue=$(eval "$COMMAND" 2>/dev/null)
          fi
          ReturnedExit=$?


        fi

      fi
      # end of APPLYHARDEN condition
    fi

    if [[ "$MODE" == "BACKUP" ]]; then
      Save "$ID,$Category,$Name,$AssessmentStatus,$Method,$MethodOption,$GetCommand,$SetCommand,$SudoUser,$RegistryPath,$RegistryItem,$DefaultValue,$ReturnedValue,$TypeValue,$Operator,$Severity,$Level"  
    fi
  fi
  # Out of main condition to take first line of csv file
  # reset some values
  ReturnedExit=""
  ReturnedValue=""
  ResultValue=""
done < $INPUT

## Redefine separator with its precedent value
IFS=$OLDIFS
