#!/usr/bin/env bash
#
export TERM=xterm

if [[ $1 == "--"* ]]; then 
	VM=$(echo $1 | sed -e "s/--//g"); Command=$2; Argument1=$3; Argument2=$4; Argument3=$5; Argument4=$6; Argument5=$7; Argument6=$8; 
else 
	VM=""; Command=$1; Argument1=$2; Argument2=$3; Argument3=$4; Argument4=$5; Argument5=$6; Argument6=$7;
fi

ScriptsDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$ScriptsDir/Common.sh"

Found="0"


######################################################################################################
if [ "$Command" == "" ] && [ "$VM" == "" ]; then echo "Please specify command"; exit 914; fi


if [ "$Command" == "mariadb" ]	|| [ "$Command" == "m" ] || 
   [ "$Command" == "nginx" ]	|| [ "$Command" == "n" ] || 
   [ "$Command" == "both" ]		|| [ "$Command" == "b" ]
   [ "$Command" == "fail2ban" ]	|| [ "$Command" == "smb" ] || [ "$Command" == "nmb" ]; then Found=1;
	## run sudo systemctl on guest follow by requested Argument
	## for example "vmf mariadb restart" would ssh to guest and run sudo systemctl restart mariadb
	## VM must be specified
	## Inputs: 1
	## Input 1 choices: start, restart or stop
	## Example: vmf mariadb restart; vmf h s;
	ServiceCommand
fi


if [ "$Command" == "tail" ]; then Found=1;
	## Tails error log
	## VM must be specified
	## Inputs: 1
	## Input 1: hostname. Optional. Guest by default
	## Example: vmf tail, vm tail c
	TailIt
fi


if [ "$Command" == "g" ] || [ "$Command" == "" ]; then
	if [ "$Command" == "" ] && [ "$VM" == "" ]; then echo "must provide a host when using generic vm command"; exit 914; fi
	if [ "$Command" == "" ]; then Command="g"; fi 
		## Opens a new tab, sshs to server, colors for specific server
	## Inputs: 0
	## Example: vm f
	Found=1;
	SSHHelper
fi


if [ "$Command" == "build" ]; then Found=1;
	## Builds a new vm
	## Inputs: 1
	## Input 1: Build type: basic or nmu. Default is nmu
	## Example: vm build 

	VMBuilder "$Argument1" "$VM" "$Argument2" "$Argument3" "$Argument4"
fi


## These functions are used for vm build only. Do not use them.
if [ "$Command" == "rkh" ]; then Found=1; RemoveKnownHost; fi
if [ "$Command" == "setkey" ]; then Found=1; ConfirmAndSetKey "$Argument1" "$Argument2"; fi
if [ "$Command" == "setprofile" ]; then Found=1; SetupUserWorkstationProfile; fi



## Specialty Functions. Ask Drew if interested
if [ "$Command" == "mount" ]; then Found=1;
	AddMounts "$Argument1" "$Argument2" "$Argument3" "$Argument4"
fi


if [ "$Found" == "0" ]; then echo "Command $Command not found."; fi


