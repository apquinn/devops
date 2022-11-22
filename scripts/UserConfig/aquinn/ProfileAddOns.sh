function ProfileAdditions()
{
	### SHELL SETTINGS
	AddProfile "" "HISTCONTROL=ignoreboth:erasedups"

	if [ "$(hostname)" == "$Address_Guest" ]; then
		AddProfile "" "alias conf='cd /usr/local/apache2/conf'"
		AddProfile "" "alias start='sudo systemctl start '"
		AddProfile "" "alias re='sudo systemctl restart '"
		AddProfile "" "alias stop='sudo systemctl stop '"
	fi

	if [ ! -d /Users ]; then
		### NAVIGATION SHORTCUTS
		AddProfile "" "alias sites='cd /htdocs/Drupal/web/sites/'"
		AddProfile "" "alias cgi='cd /htdocs/cmsphp'"

		### COMMAND SHORTCUTS
		AddProfile "" "alias drupal='/htdocs/Drupal/vendor/drupal/console/bin/drupal'"

		### VI SHORTCUTS
		AddProfile "" "alias vip='vi ~/.zprofile'"
		AddProfile "" "alias venv='vi /htdocs/Drupal/.env'"
		AddProfile "" "alias vht='sudo vi /htdocs/Drupal/web/.htaccess'"
		AddProfile "" "alias vs='vi /htdocs/Drupal/web/sites/sites.php'"
		AddProfile "" "alias vic='vi /usr/local/apache2/conf/nmu/shared_config/www.sites.conf'"
		AddProfile "" "alias src='source ~/.zprofile'"
	else
		AddProfile "" "alias src='source ~/.bash_profile'"
	fi

	### COMMAND SHORTCUTS
	AddProfile "" "alias ls='ls -l'"
}


function DrewsScreenSetup()
{
	osascript <<-EOF
		tell application "bbedit"
			activate
			set CurrentWindow to name of text window 1
		end tell

		repeat with counter from 0 to 25
			tell application "bbedit" to open "/Users/$Username/ApplicationOrg/Dividers/" & counter
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


function Add_A_Mount()
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

			if [ -f $VM_Log ]; then rm $VM_Log; fi

			{
				mount_smbfs  //$Identity@$MakeConnections_Host/$A_Mount $MakeConnections_MountPath/$A_Mount
			} &> $VM_Log;
		fi
	done
	echo;
	export IFS=""
}


function AddMounts()
{
	echo; echo "MOUNTING HOST SAMBA SHARES"
	echo "--- Mounting shares to		$BaseDir/mounts"

	if [ "$Address_Guest" != "" ]; then 
		RequestCredential $Address_Guest 
		Add_A_Mount $BaseDir/mounts/$Address_Guest $Address_Guest $Username $Linode_Mounts $ReturnVal
	fi
}






