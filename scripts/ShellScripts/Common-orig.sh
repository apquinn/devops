
######################################################################################################
#################################### Common Configuration Info #######################################
######################################################################################################

UserCfgScriptsDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$UserCfgScriptsDir/../UserConfig/Bootstrap.sh"

if [ "$Host_Username" == "aquinn" ]; then Macs=( "# 1 - aqvm2 00:50:56:3E:B4:50"); fi

DBUserList="'BackupAccount','Drupal','WebAdmin','aquinn',,'images','www_calman', 'pma', 'ssaml_admin'"
declare -a TechTeamUsers=("aquinn")
declare -a CharlieDirsToCopy=("cmsphp" "Content" "Drupal" "Webb" "www")
#declare -a FrankDirsToCopy=("cmsphp" "Content" "Webb" "www")
declare -a FrankDirsToCopy=("cmsphp")

if [ -f /etc/centos-release ]; then 
	VM_LogDir="/NMUInstallInfo"; 
else
	cd;
	VM_LogDir="$(pwd)/NMUInstallInfo";
	if [ ! -d $VM_LogDir ]; then mkdir -p "$VM_LogDir"; chmod 777 $VM_LogDir; fi
fi
VM_Log="$VM_LogDir/VMInstall.log"

Guest_Username=$Host_Username
Guest_Password="password"
Guest_VMBaseFileName="NMUCentOS7-Base.vmwarevm"
Guest_VMWorkingFileName="NMUCentOS7-Working.vmwarevm"
Guest_VMWorkingBackup="NMUCentOS7-Backup.vmwarevm"
Guest_Mounts="$Host_Username,htdocs,http-conf"

Host_Scripts="$Host_Fusion/scripts"
Host_Temp="$Host_Scripts/ShellScripts/temp"
Host_Mounts="$Host_Fusion/mounts"
Host_VMs="$Host_Fusion/VMs"
if [ "$(hostname)" != "aqvm1" ] && [ "$(hostname)" != "aqvm2" ] && [ "$Guest_Username" == "aquinn" ]; then Host_Mount_Loc="away"; else Host_Mount_Loc="work"; fi

Charlie_Address="charlie.nmu.edu"
Charlie_User=$Host_Username
Charlie_DBUser="BackupAccount"
Charlie_DBPass="SecretBackupCode"
Charlie_Mounts="$Host_Username,htdocs,weblogs"

Franklin_Address="franklin.nmu.edu"
Franklin_User=$Host_Username
Franklin_DBUser="BackupAccount"
Franklin_DBPass="SecretBackupCode"
Franklin_Mounts="$Host_Username,htdocs,weblogs"

Charlieeup_User="eupdates"
Charlieeup_Pwd="SecretCode1a1"

Synology_User=$Host_Username
Synology_Address="umc-media.nmu.edu"
Synology_Mounts="TechTeam,Office,Media"

GenericPasswordNotEncrypted="password"

if [ "$VM" != "" ]; then source "$Host_VMs/$VM/Bootstrap-VmSpecific.sh"; fi
if [[ $UserCfgScriptsDir == "/mnt"* ]]; then source "/mnt/hgfs/GuestConfig/Bootstrap-VmSpecific.sh"; fi

NONE='\033[00m'; RED='\033[01;31m'; GREEN='\033[01;32m'; YELLOW='\033[01;33m'; PURPLE='\033[01;35m'; CYAN='\033[01;36m'; WHITE='\033[01;37m'; BOLD='\033[1m'; UNDERLINE='\033[4m'

######################################################################################################
######################################################################################################
######################################################################################################


if [ -d /mnt/hgfs ]; then
	Temp_Dir="/mnt/hgfs/scripts/ShellScripts/temp"
	if [ ! -d "$Host_Temp" ]; then sudo mkdir -p $Temp_Dir; sudo chmod -R 777 $Temp_Dir; fi
else
	Temp_Dir=$Host_Fusion/scripts/ShellScripts/temp
	if [ ! -d "$Temp_Dir" ]; then sudo mkdir -p $Temp_Dir; sudo chmod -R 777 $Temp_Dir; fi
fi

function TrimVar()
{
	Variable=$1
	TrimType=$2

	if [ "$TrimType" == "l" ] || [ "$TrimType" == "both" ]; then Variable=$(echo "${Variable}" | sed -e 's/^[ \t]*//'); fi
	if [ "$TrimType" == "r" ] || [ "$TrimType" == "both" ]; then Variable=$(echo "${Variable}" | sed -e 's/[ \t]*$//'); fi

	echo "$Variable"
}


function ClearFile()
{
	if [ "$1" != "" ] && [ -s "$1" ]; then
		rm $1
	fi
}


function ErrorHandler()
{
	Msg=$1
	ErrorFile=$2
	ClearFile $3
	ClearFile $4
	ClearFile $5
	ClearFile $6

	echo -e "$Msg" >> $ErrorFile
	echo "$Msg"
	exit 928
	echo
}


function GitAction ()
{
	Path=$1
	GitAction=$2

	if [ ! -d /$Path ] || [ $(find /$Path/ -mindepth 1 -maxdepth 1 -type d | wc -l) == 0 ]; then
		mkdir -p $Path
		cd $Path; chmod 755 $Path; chown $Guest_Username $Path; 

		if [ "$Host.nmu.edu" == "$Guest_Addr" ]; then chgrp wwwmgmt $Path; fi
		eval $GitAction .
		chmod -R 644 $Path/*; chown -R $Guest_Username $Path/*; chgrp -R wwwmgmt $Path/*
	fi
}


function AddKnownHost()
{
	Path=$1
	User=$2

	if [ "$User" == "root" ]; then Path="$Path/.ssh"; else Path="$Path/$2/.ssh"; fi

	{
		if [ ! -d $Path ]; then
			mkdir -p $Path;
			chmod 700 $Path;
			chown $User $Path;
		fi

		if [ ! -f $Path/known_hosts ]; then 
			touch $Path/known_hosts;
			chmod 644 $Path/known_hosts;
			chown $User $Path/known_hosts;
		fi 

		sort $Path/known_hosts | uniq > $Path/known_hosts.uniq
		mv $Path/known_hosts.uniq $Path/known_hosts
	} &> $VM_Log;
	CheckErrors "false"
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
			CheckErrors "false"
		fi

		NiceName=$(echo "${MachineToKey/.nmu.edu/}")
		echo -n "--- Ready to set key		(press enter to continue)"
		read junk
		echo -n "--- Adding host key 		"
		{
			ssh-copy-id $MachineToKeyUser@$MachineToKey
		} &> $VM_Log;
		CheckErrors "false"
	fi
}


function AddProfileDetails ()
{
	ToDelete=$1
	NewLine=$2
	ProfileLoc=$3
	Desc=$4
	User=$5

	if [ ! -f $ProfileLoc ]; then
	  sudo touch "$ProfileLoc";
	  sudo chown "$User" "$ProfileLoc"
	  sudo chgrp "wwwmgmt" "$ProfileLoc"
	  sudo chmod 644 "$ProfileLoc"
	fi
	if [ "$ToDelete" != "" ]; then sudo sed -i'.bk' '/'"$ToDelete"'/d' "$ProfileLoc"; fi

	Run=false
	if [ "$Desc" != "" ] && ! sudo grep -q "$Desc" $ProfileLoc; then		Run=true; fi
	if [ "$Desc" == "" ] && ! sudo grep -q "$NewLine" $ProfileLoc; then	Run=true; fi
	if [ "$Desc" == "" ] && [ "$NewLine" == "" ]; then				Run=true; fi

	if [ $Run == true ]; then
		sudo cp $ProfileLoc $ProfileLoc.bk
		if [ "$Desc" != "" ]; then NewLine="$NewLine			$Desc"; fi

	  sudo chmod 777 $ProfileLoc
		echo "$NewLine" >> $ProfileLoc
	  sudo chmod 644 $ProfileLoc
    if [ "$User" == "$Guest_Username" ]; then source $ProfileLoc; fi
    cd /
	fi
}


function AddProfile ()
{
	ToDelete=$1
	NewLine=$2
	Desc=$3
	User=$4

	if [ "$User" != "" ]; then
		ProfileLoc="/home/$User/.bash_profile";
	elif [ "$(whoami)" == "root" ]; then
		ProfileLoc="/root/.bash_profile";
	elif [ -d /Users ]; then
		ProfileLoc="/Users/$(whoami)/.bash_profile";
	else
		ProfileLoc="/home/$Guest_Username/.bash_profile";
	fi

	AddProfileDetails "$ToDelete" "$NewLine" "$ProfileLoc" "$Desc" "$User"
}


function CheckErrors ()
{
	Debug="false";
	ErrorCheck=$1

	if [ -f $VM_Log ]; then
		if [ "$Debug" == "true" ]; then 
			cat $VM_Log
		fi

		if [ "$ErrorCheck" != "false" ]; then 
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
		fi
		rm $VM_Log
	fi
}


function SyncDirThread()
{
	DirName="$1"
	ServerDest="$2"
	ServerPath="$3"
	Server="$4"
	SyncArgs="$5"
	SendResults="$6"
	Result=""

	{
		ssh $Guest_Username@$Guest_Addr "sudo chmod 775 $ServerDest/$DirName; sudo chown $Guest_Username $ServerDest/$DirName; sudo chgrp wwwapache $ServerDest/$DirName;"

		MainCommand="rsync $SyncArgs -e ssh --delete --exclude-from=/mnt/hgfs/scripts/ShellScripts/rsync_excludes/"
		Result=$(ssh $Guest_Username@$Guest_Addr "$MainCommand$DirName.exclude $Server:$ServerPath $ServerDest")
		if [ "$SendResults" == "true" ] && [ "$Result" != "" ]; then 
			Result=$(echo $Result | sed 's/.*Total transferred file size: //')
			Result=$(echo $Result | sed 's/ bytes.*//')
			Result=$(echo $Result | sed -e 's/,//g')
			Result=$(perl -E "say $Result/1024")
			Result=$(echo $Result | sed 's/\..*//')
		fi
	} &> $VM_Log;
	CheckErrors "false"

	echo "$Result";
}


function GetCurrentSize()
{
	DirName="$1"
	{
		CurrentDirSize=$(echo $(ssh $Guest_Username@$Guest_Addr "du -sk /htdocs/$DirName") | awk '{print $1;}')
	} &> $VM_Log;
	CheckErrors "false"

	echo $CurrentDirSize
}


function SyncDir()
{
	DirName=$1
	Server=$2
	ServerDest=$3
	ServerPath=$4
	ssh $Guest_Username@$Guest_Addr "sudo mkdir -p /htdocs/$DirName"

	{
		ExpectedTransferSize=$(SyncDirThread "$DirName" "$ServerDest" "$ServerPath" "$Server" "-azu --dry-run --stats" "true")
		OrigDirSize=$(GetCurrentSize "$DirName")
		SyncDirThread "$DirName" "$ServerDest" "$ServerPath" "$Server" "-avzu" "false" &
	} &> $VM_Log;
	CheckErrors "false"

	CurrentTransferSize=0; Percent=0; Counter=0; Pause=1; LoopsTillFail=30;
	while [ "$CurrentTransferSize" -lt "$ExpectedTransferSize" ] && [ $Counter -lt $LoopsTillFail ]; do
		if [ $CurrentTransferSize -gt 0 ]; then Percent=$(perl -E "say $CurrentTransferSize/$ExpectedTransferSize*100"); fi

		if [ "$DirName" == "www" ]; then printf "%s%2.2f%s\\r" "--- Syncing $DirName			" $Percent "%"; else printf "%s%2.2f%s\\r" "--- Syncing $DirName		" $Percent "%"; fi
		
		sleep $Pause

		LastSize=$CurrentTransferSize
		CurrentTransferSize=$(GetCurrentSize "$DirName")
		CurrentTransferSize=$(perl -E "say $CurrentTransferSize-$OrigDirSize")

		if [ "$LastSize" == "$CurrentTransferSize" ]; then ((Counter++)); else Counter=0; fi
	done

	Percent=100
	printf "%s%2.0f%s\\r" "--- Syncing $DirName			" $Percent "%                  "; 
	echo
}


function RestrictToGuest()
{
	if [ ! -f /etc/centos-release ]; then 
		echo "This function can only be run on the guest machine"; 
		exit 914; 
	fi
}



function SyncDBError()
{
	Temp_Error=$1
	Temp_Host_Temp=$2
	Temp_Line=$3
	Temp_File2=$6
	Temp_File3=$7
	Temp_File4=$8

	if [ $Temp_Error != "0" ] ; then
		ErrorFound="true"
		ErrorHandler "$Temp_Error :: $Temp_Line" "$Temp_Host_Temp/error.log" "$Temp_File2" "$Temp_File3" "$Temp_File4"; 
		echo; echo "An error occured: $Temp_Error :: $Temp_Line"
	fi
}



function HidenAction()
{
	printf "%s\\r" "--- Installing $2";
	{
		eval $1
	} &> $VM_Log;
	CheckErrors "false"
	echo;
}


AddMounts ()
{
	MakeConnections_MountPath=$1
	MakeConnections_Host=$2
	MakeConnections_User=$3
	MakeConnections_Mounts=$4
	MakeConnections_PWD=$5

	mkdir -p $MakeConnections_MountPath; chmod 777 $MakeConnections_MountPath

	export IFS=","
	echo -n "--- $MakeConnections_Host		"

	Comma=""
	for A_Mount in $MakeConnections_Mounts; do
		if [ -d /Volumes/$A_Mount ]; then umount /Volumes/$A_Mount; fi

		echo -n "$Comma$A_Mount"
		Comma=", "

		if ! mount | grep "on $MakeConnections_MountPath/$A_Mount" > /dev/null; then
			mkdir -p $MakeConnections_MountPath/$A_Mount; chmod 777 $MakeConnections_MountPath/$A_Mount
			if [ "$MakeConnections_PWD" != "" ]; then 
				Identity="$MakeConnections_User:$MakeConnections_PWD"
			else
				Identity="$MakeConnections_User"
			fi

			if [ -f $VM_Log ]; then sudo rm -rf $VM_Log; fi

			{
				mount_smbfs  //$Identity@$MakeConnections_Host/$A_Mount $MakeConnections_MountPath/$A_Mount
			} &> $VM_Log;
		fi
	done
	echo;
	export IFS=""
}


function EditConfigFile()
{
	File=$1
	Var=$2
	Value=$3
	Name=$4

	if [[ $Var == "sharedFolder"* ]] && [ "$Name" != "" ]; then
		sed -i'.bk' -e 's/'$Var'//g' $File

		echo $Var'.hostPath = "'$Value'"' >> $File

		echo $Var'.present = "TRUE"' >> $File
		echo $Var'.enabled = "TRUE"' >> $File
		echo $Var'.readAccess = "TRUE"' >> $File
		echo $Var'.writeAccess = "TRUE"' >> $File
		echo $Var'.guestName = "'$Name'"' >> $File
		echo $Var'.expiration = "never"' >> $File
	elif grep -q "$Var = " "$File"; then
		sed -i'.bk' -e 's/'$Var' = ".*"/'$Var' = "'$Value'"/g' $File
	elif [ "$Value" != "--delete" ]; then
		echo "$Var = \"$Value\"" >> $File
	else
		sed -i'.bk' -e 's/'$Var' = "//g' $File
	fi

	if [ -f $File.bk ]; then rm $File.bk; fi
}


function QueryUser()
{
	Msg=$1
	Var=$2
	File=$3
	Q=$4

	echo -ne "$Msg? " 
	Response=""
	HasRun="false"
	while [ "$Response" == "" ]; do
		if [ "$Response" == "" ] && [ "$HasRun" == "true" ]; then echo -ne "$Msg (required)? "; fi
		read Response
		HasRun="true"

		if [ "$Q" == "1" ] && [ "$Response" == "" ]; then Response="1"; fi
		if [ "$Q" == "2" ] && [ "$Response" == "" ]; then Response="72"; fi
		if [ "$Q" == "3" ] && [ "$Response" == "" ]; then Response="f"; fi
	done

	if [ "$Q" == "1" ]; then
		Response=$(($Response-1))
		Selection=${Macs[$Response]}
		Addr=$(echo "$Selection" | cut -d ' ' -f 4)
		Addr=$(TrimVar $Addr)

		echo "Guest_Addr=\"$Addr.nmu.edu\"" >> $File
		Mac=$(echo "$Selection" | cut -d ' ' -f 5)
		Mac=$(TrimVar $Mac)
	elif [ "$Q" == "3" ]; then
		if [ "$Response" == "c" ]; then echo "$Var=\"charlie\"" >> $File; fi
		if [ "$Response" == "f" ]; then echo "$Var=\"franklin\"" >> $File; fi
	else
		echo "$Var=\"$Response\"" >> $File
	fi
}


function CheckIfComplete()
{
	Filename=".nmu-setup-confirmation-$1"
	Clear="$2"
	if [ "$Clear" == "true" ]; then 
		if [ -f $Filename ]; then
			if [ "$Me" != "root" ]; then sudo rm /$Filename; else rm /$Filename; fi
		fi
	else
		if [ -f /$Filename ]; then 
			echo "--- done"; 
			exit 928;
		else 
			Me=$(whoami)
			if [ "$Me" != "root" ]; then sudo touch /$Filename; else touch /$Filename; fi
		fi
	fi

}


function DrewsSetup()
{
	osascript <<-EOF
		tell application "bbedit"
			activate
			set CurrentWindow to name of text window 1
		end tell

		repeat with counter from 0 to 25
			tell application "bbedit" to open "/Users/aquinn/ApplicationOrg/Dividers/" & counter
		end repeat
		tell application "System Events" to set bounds of window 1 of application "bbedit" to {50, 40, 1822, 1440}

		tell application "Finder"
			activate
			if (count windows) is 0 then 
				tell application "System Events" to keystroke "n" using command down 
			end if
			set bounds of front window to {50, 700, 2400, 1440}
		end tell

		tell application "Terminal"
			activate
			set bounds of front window to {1402, 810, 2500, 1420}
		end tell

		tell app "Google Chrome" to close (windows 1 thru -1)
		tell application "Google Chrome"
			activate

			open location "http://aqvm2.nmu.edu/webadmin"
			tell application "System Events" to keystroke "j" using {option down, command down}
			delay .25

			open location "http://aqvm2.nmu.edu"
			tell application "System Events" to keystroke "j" using {option down, command down}
			delay .25

			set bounds of front window to {1824, 24, 3700, 750}
		end tell

		tell app "FireFox" to close (windows 1 thru -1)
		tell application "FireFox"
			activate
			open location "http://aqvm2.nmu.edu/SecretSQLSpot"
			set bounds of front window to {500, 25, 2500, 800}
			tell application "System Events" to keystroke "enter" 
		end tell

		tell application "Messages"
			activate
			set bounds of front window to {4000, 850, 5120, 1440}
		end tell
	EOF
}


function SetupSymLinksAndProfile()
{
	HomeDir=$1
	User=$2

  if [ -d $HomeDir/bin ]; then rm -rf $HomeDir/bin; fi
	mkdir -p $HomeDir/bin
	chmod 777 $HomeDir/bin
	cd $HomeDir/bin

	if [ ! -f drupal ]; then ln -s /htdocs/Drupal/vendor/drupal/console/bin/drupal drupal; fi
	if [ ! -f drush ]; then ln -s /htdocs/Drupal/vendor/drush/drush/drush drush; fi
	if [ ! -f drush.php ]; then ln -s /htdocs/Drupal/vendor/drush/drush/drush.php drush.php; fi
	if [ ! -f php-parse ]; then ln -s /htdocs/Drupal/vendor/nikic/php-parser/bin/php-parse php-parse; fi
	if [ ! -f phpunit ]; then ln -s /htdocs/Drupal/vendor/phpunit/phpunit/phpunit phpunit; fi
	if [ ! -f psysh ]; then ln -s /htdocs/Drupal/vendor/psy/psysh/bin/psysh psysh; fi
	cd /
	chgrp users $HomeDir/bin
	chown $User $HomeDir/bin

	AddProfile "" "if [ -f ~/.bashrc ]; then . ~/.bashrc; fi"		"# .bashrc inslude" "$User"
	AddProfile "" "PATH=\"\$HOME/bin:\$HOME/.local/bin:\$PATH\""	"" "$User"
	AddProfile "" "PS1='\u@\h: \w\\\$ '" "# setup your default cursor" "$User"
	AddProfile "" "export PATH PS1" "" "$User"
	AddProfile "" "alias perms=\"find . -type d -exec sudo chmod 775 '{}' \;; find . -type f -exec sudo chmod 664 '{}' \;\"" "" "$User"
	AddProfile "" "" "" "$User"


}


function SetDrupalPerms()
{
	echo ""
}


function CompressBackups()
{
	DirToWorkOn=$1

	for DirName in $DirToWorkOn/* ; do
		if [[ $DirName != *".tar.gz" ]]; then
			DatePart=$(echo $DirName | cut -d'/' -f4  )
			DatePart=$(echo $DatePart | cut -d'-' -f1)-$(echo $DatePart | cut -d'-' -f2)-$(echo $DatePart | cut -d'-' -f3)
			if [ ! -d $DirToWorkOn/$DatePart ]; then mkdir $DirToWorkOn/$DatePart; chmod -R 777 $DirToWorkOn/$DatePart; fi
			mv $DirName $DirToWorkOn/$DatePart/
		fi
	done

	for DirName in $DirToWorkOn/* ; do
		if [[ $DirName != *".tar.gz" ]]; then
			{
				tar -zcvf $DirName.tar.gz $DirName
				rm -rf $DirName
			} &> $VM_Log;
		fi
	done

	rm -rf ~/.Trash/*
}



