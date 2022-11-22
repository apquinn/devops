ScriptsDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
present=$(pwd); cd "$ScriptsDir/../.."; BaseDir=$(pwd); cd "$present"
VM_Log=$BaseDir/temp/error_log.txt
debug=false;

RemoveKnownHost() { 
	source $BaseDir/scripts/UserConfig/$VM.sh
	if [ -f ~/.ssh/known_hosts ]; then sed -i'.bk' "/^$Address_Guest/d" ~/.ssh/known_hosts; fi
}

SyncScripts() {
	MachineToSync=$1
	MachineToSyncUser=$2

	{
		ssh $MachineToSyncUser@$MachineToSync "rm -rf /ScriptFiles"; 
		scp -r $BaseDir $MachineToSyncUser@$MachineToSync:/ScriptFiles
		ssh $MachineToSyncUser@$MachineToSync "sudo chmod -R 775 /ScriptFiles;"; 
	} &> $VM_Log;
	CheckErrors

}

VMBuilder() {
	stage=$1

	if [ "$stage" == "" ]; then
		source $ScriptsDir/Build.sh
		CollectInfo

		LocalKey=$(cat ~/.ssh/id_rsa.pub)
		ssh root@$ENTERED_Address_Guest "bash /ScriptFiles/scripts/ShellScripts/VM-Mgmt.sh --$ENTERED_Guest_ShortName \"build\" \"InstallComponents\" \"$(whoami)\" \"$ENTERED_Guest_PW\" \"$LocalKey\" "
		ssh $(whoami)@$ENTERED_Address_Guest "bash /ScriptFiles/scripts/ShellScripts/VM-Mgmt.sh --$ENTERED_Guest_ShortName \"build\" \"FinalConfiguration\" \"$(whoami)\""
		bash $ScriptsDir/VM-Mgmt.sh --$ENTERED_Guest_ShortName "mount" "$ENTERED_Guest_PW"
	fi

	if [ "$stage" == "InstallComponents" ]; then
		source $ScriptsDir/Build.sh
		vm=$2
		user=$3
		password=$4
		key=$5
		source /ScriptFiles/scripts/UserConfig/$vm.sh

		InstallComponents $user $password "$key" "$vm"
	fi

	if [ "$stage" == "FinalConfiguration" ]; then
		source $ScriptsDir/Build.sh
		vm=$2
		user=$3

		FinalConfiguration $vm $user
	fi

}


function Vars_SaveVar() {
	Vars_GetPath
	if [ -f $VarFile ]; then sed -i'.bk' "/^DrewVar_$1=/d" $VarFile; fi
	echo -e "DrewVar_$1=\"$2\"" >> $VarFile
}


function Vars_GetVar() {
	Vars_GetPath
	if [ -f $VarFile ]; then source $VarFile; fi
	DrewVarX_MyVarName="DrewVar_$1"
	eval $1="${!DrewVarX_MyVarName}"
}


function Vars_GetPath() {
	VarFilename=".vm_vars.sh"
	VarFile="$ScriptsDir/$VarFilename"
}


function AddProfileDetails () {
	ToDelete=$1
	NewLine=$2
	ProfileLoc=$3
	Desc=$4
	User=$5

	if [ ! -f $ProfileLoc ]; then
	  sudo touch "$ProfileLoc";
	  sudo chown "$User" "$ProfileLoc"
	  sudo chmod 644 "$ProfileLoc"
	fi
	if [ "$ToDelete" != "" ]; then sudo sed -i'.bk' '/'"$ToDelete"'/d' "$ProfileLoc"; fi

	Run=false
	if [ "$Desc" != "" ] && ! sudo grep -q "$Desc" $ProfileLoc; 		then Run=true; fi
	if [ "$Desc" == "" ] && ! sudo grep -q "$NewLine" $ProfileLoc;	then Run=true; fi
	if [ "$Desc" == "" ] && [ "$NewLine" == "" ]; 									then Run=true; fi

	if [ $Run == true ]; then
		sudo cp $ProfileLoc $ProfileLoc.bk
		if [ "$Desc" != "" ]; then NewLine="$NewLine			$Desc"; fi

	  sudo chmod 777 $ProfileLoc
		echo "$NewLine" >> $ProfileLoc
	  sudo chmod 644 $ProfileLoc
    source $ProfileLoc;
    cd /
	fi
}

function AddProfile () {
	ToDelete=$1
	NewLine=$2
	Desc=$3
	User=$4

	if [ "$User" != "" ]; then
		ProfileLoc="/home/$User/.bash_profile";
	elif [ "$(whoami)" == "root" ]; then
		ProfileLoc="/root/.bash_profile";
	elif [ -d /Users ]; then
		ProfileLoc="/Users/$(whoami)/.zprofile";
	else
		ProfileLoc="/home/$(whoami)/.bash_profile";
	fi

	AddProfileDetails "$ToDelete" "$NewLine" "$ProfileLoc" "$Desc" "$User"
}


function ConfirmAndSetKey ()
{
	MachineToKey=$1
	MachineToKeyUser=$2
	Passed="yes" 

	Result=$(ssh -oBatchMode=yes  -l $MachineToKeyUser $MachineToKey exit 2>&1)
	echo $Result | grep "Permission denied" >> /dev/null
	if [ $? = 0 ]; then Passed="no"; fi

	echo $Result | grep "Host key verification" >> /dev/null
	if [ $? = 0 ]; then	Passed="no"; fi

	echo $Result | grep "Could not resolve hostname" >> /dev/null
	if [ $? = 0 ]; then Passed="no"; fi

	if [ "$Passed" == "no" ]; then
		if [ ! -f ~/.ssh/id_rsa.pub ]; then
			{
				ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa >> /dev/null
			} &> $VM_Log;
			CheckErrors
		fi

		echo -n "--- Ready to set key for $MachineToKeyUser on $MachineToKey (press enter to continue)"
		read junk
		echo -n "--- Adding host key 		"
		{
			ssh-copy-id $MachineToKeyUser@$MachineToKey
		} &> $VM_Log;
		CheckErrors
	fi
}


function CheckErrors ()
{
	Debug="false";
	ErrorCheck=$1

	if [ -f $VM_Log ]; then
		if [ "$Debug" == "true" ]; then 
			cat $VM_Log
		fi

		Errors=$(cat $VM_Log | egrep -i "(Error|error|command not found|failed)")

		if [ "$Errors" != "" ]; then
			Success=$(tail -1 $VM_Log | egrep -i "(complete!|You should add \"extension=imagick.so\" to php.ini)|Use it: php composer.phar")
			echo; echo;
			if [ "$Success" != "" ]; then
				echo "Looks like everything completed ok, but we did see these issues:"
			else
				echo "It looks like something failed, hopefully this will help debug:"
			fi
			echo $Errors; echo; 
		fi

		rm $VM_Log
	fi
}

function Beep ()
{
	echo -ne '\007'; echo -ne '\007'; echo -ne '\007'; echo -ne '\007'; 
	echo -ne '\007'; echo -ne '\007'; echo -ne '\007'; echo -ne '\007'; 
	exit;
}

AddMounts ()
{
	MakeConnections_MountPath=$BaseDir/mounts
	source $BaseDir/scripts/UserConfig/$VM.sh
	
	declare -a MakeConnections_Mounts=("htdocs" "homes" "http-conf" "logs")

	mkdir -p $BaseDir/mounts; chmod 777 $BaseDir/mounts

	export IFS=","
	echo "--- Mounting $Address_Guest		"

	for A_Mount in ${MakeConnections_Mounts[@]}; do
 		if [ -d /Volumes/$A_Mount ]; then umount /Volumes/$A_Mount; fi

		echo -n "    --- $A_Mount"

		if ! mount | grep "on $BaseDir/mounts/$A_Mount" > /dev/null; then
			mkdir -p $BaseDir/mounts/$A_Mount; chmod 777 $BaseDir/mounts/$A_Mount
			if [ "$Guest_PW" != "" ]; then 
				Identity="$(whoami):$Guest_PW"
			else
				Identity="$(whoami)"
			fi

			if [ -f $VM_Log ]; then sudo rm -rf $VM_Log; fi
			{
				mount_smbfs  //$Identity@$Address_Guest/$A_Mount $BaseDir/mounts/$A_Mount
			} &> $VM_Log;
		fi
		echo "    		success"
	done
	export IFS=""
}


TailIt () {
	source $BaseDir/scripts/UserConfig/$VM.sh
	ssh $(whoami)@$Address_Guest "tail -f -n 10 /usr/local/apache2/logs/error_log"	
}