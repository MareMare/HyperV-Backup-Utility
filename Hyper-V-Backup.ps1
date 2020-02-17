﻿<#PSScriptInfo

.VERSION 20.02.14

.GUID c7fb05cc-1e20-4277-9986-523020060668

.AUTHOR Mike Galvin Contact: mike@gal.vin / twitter.com/mikegalvin_

.COMPANYNAME Mike Galvin

.COPYRIGHT (C) Mike Galvin. All rights reserved.

.TAGS Hyper-V Virtual Machines Full Backup Export Permissions Zip History

.LICENSEURI

.PROJECTURI https://gal.vin/2017/09/18/vm-backup-for-hyper-v

.ICONURI

.EXTERNALMODULEDEPENDENCIES Windows Server 2016/Windows 2012 R2 Hyper-V PowerShell Management Modules

.REQUIREDSCRIPTS

.EXTERNALSCRIPTDEPENDENCIES Hyper-V PowerShell Management Tools

.RELEASENOTES

#>

<#
    .SYNOPSIS
    Hyper-V Backup Utility - Flexible backup of Hyper-V Virtual Machines.

    .DESCRIPTION
    This script will create a full backup of virtual machines, complete with configuration, snapshots/checkpoints, and VHD files.

    This script should be run on a Hyper-V host and the Hyper-V PowerShell management modules should be installed.

    To send a log file via e-mail using ssl and an SMTP password you must generate an encrypted password file.
    The password file is unique to both the user and machine.

    To create the password file run this command as the user and on the machine that will use the file:

    $creds = Get-Credential
    $creds.Password | ConvertFrom-SecureString | Set-Content c:\foo\ps-script-pwd.txt
    
    .PARAMETER BackupTo
    The path the Virtual Machines should be backed up to.
    A folder will be created in the specified path and each VM will have it's own folder inside.

    .PARAMETER List
    Enter the path to a txt file with a list of Hyper-V VM names to backup. If this option is not
    configured, all running VMs will be backed up.

    .PARAMETER L
    The path to output the log file to.
    The file name will be Hyper-V-Backup_YYYY-MM-dd_HH-mm-ss.log

    .PARAMETER Wd
    The path to the working directory to use for the backup before copying it to the final backup
    directory. Use a directory on local fast media to improve performance.

    .PARAMETER NoPerms
    Instructs the script to shutdown the running VM(s) to do the file-copy based backup, instead of
    using the Hyper-V export function. When multiple VMs are running, the first VM (alphabetically)
    will be shutdown, backed up, and then started, then the next and so on.

    .PARAMETER Keep
    Instructs the script to keep a specified number of days worth of backups. The script will delete
    VM backups older than the number of days specified.

    .PARAMETER Compress
    This option will create a zip file of each Hyper-V VM backup.
    Available disk space should be considered when using this option.

    .PARAMETER Sz
    This option will use 7-zip compression instead of Windows compression to create the zip file.
    7-zip should be installed in the default location (env:Programfiles) on the host in order
    to use this option. If it is not installed, the script will fallback to Windows compression.

    .PARAMETER NoBanner
    Use this option to hide the ASCII art title in the console.

    .PARAMETER Subject
    The e-mail subject, if not configured the default of "Hyper-V Backup Log" will be used.
    Encapsulate with single or double quotes.

    .PARAMETER SendTo
    The e-mail address the log should be sent to.

    .PARAMETER From
    The e-mail address the log should be sent from.

    .PARAMETER Smtp
    The DNS name or IP address of the SMTP server.

    .PARAMETER User
    The user account to connect to the SMTP server.

    .PARAMETER Pwd
    The txt file containing the encrypted password for the user account.

    .PARAMETER UseSsl
    Configures the script to connect to the SMTP server using SSL.

    .EXAMPLE
    Hyper-V-Backup.ps1 -BackupTo \\nas\vms -List C:\scripts\vms.txt -Wd E:\temp -NoPerms -Keep 30
    -Compress -Sz -L C:\scripts\logs -Subject 'Server: Hyper-V Backup' -SendTo me@contoso.com
    -From hyperv@contoso.com -Smtp smtp.outlook.com -User user -Pwd C:\foo\pwd.txt -UseSsl

    This will shutdown, one at a time, all the VMs listed in the file located in C:\scripts\vms.txt
    and back up their files to \\nas\vms, using E:\temp as a working directory. A zip file for each
    VM folder will be created, and the folder will be deleted. Any backups older than 30 days will
    also be deleted. The log file will be output to C:\scripts\logs and sent via e-mail with a
    custom subject line.
#>

## Set up command line switches.
[CmdletBinding()]
Param(
    [parameter(Mandatory=$True)]
    [alias("BackupTo")]
    $Backup,
    [alias("Keep")]
    $History,
    [alias("List")]
    [ValidateScript({Test-Path -Path $_ -PathType Leaf})]
    $VmList,
    [alias("Wd")]
    [ValidateScript({Test-Path $_ -PathType 'Container'})]
    $WorkDir,
    [alias("L")]
    [ValidateScript({Test-Path $_ -PathType 'Container'})]
    $LogPath,
    [alias("Subject")]
    $MailSubject,
    [alias("SendTo")]
    $MailTo,
    [alias("From")]
    $MailFrom,
    [alias("Smtp")]
    $SmtpServer,
    [alias("User")]
    $SmtpUser,
    [alias("Pwd")]
    [ValidateScript({Test-Path -Path $_ -PathType Leaf})]
    $SmtpPwd,
    [switch]$UseSsl,
    [switch]$NoPerms,
    [switch]$Compress,
    [switch]$Sz,
    [switch]$NoBanner)

If ($NoBanner -eq $False)
{
    Write-Host ""
    Write-Host -ForegroundColor Yellow -BackgroundColor Black "   _    _                    __      __  ____             _                  _    _ _   _ _ _ _           "
    Write-Host -ForegroundColor Yellow -BackgroundColor Black "  | |  | |                   \ \    / / |  _ \           | |                | |  | | | (_) (_) |          "
    Write-Host -ForegroundColor Yellow -BackgroundColor Black "  | |__| |_   _ _ __   ___ _ _\ \  / /  | |_) | __ _  ___| | ___   _ _ __   | |  | | |_ _| |_| |_ _   _   "
    Write-Host -ForegroundColor Yellow -BackgroundColor Black "  |  __  | | | | '_ \ / _ \ '__\ \/ /   |  _ < / _  |/ __| |/ / | | | '_ \  | |  | | __| | | | __| | | |  "
    Write-Host -ForegroundColor Yellow -BackgroundColor Black "  | |  | | |_| | |_) |  __/ |   \  /    | |_) | (_| | (__|   <| |_| | |_) | | |__| | |_| | | | |_| |_| |  "
    Write-Host -ForegroundColor Yellow -BackgroundColor Black "  |_|  |_|\__, | .__/ \___|_|    \/     |____/ \__,_|\___|_|\_\\__,_| .__/   \____/ \__|_|_|_|\__|\__, |  "
    Write-Host -ForegroundColor Yellow -BackgroundColor Black "           __/ | |                                                  | |                            __/ |  "
    Write-Host -ForegroundColor Yellow -BackgroundColor Black "          |___/|_|          Mike Galvin   https://gal.vin           |_|      Version 20.02.14 ♥   |___/   "
    Write-Host -ForegroundColor Yellow -BackgroundColor Black "                                                                                                          "
    Write-Host ""
}

## If logging is configured, start logging.
## If the log file already exists, clear it.
If ($LogPath)
{
    $LogFile = ("Hyper-V-Backup_{0:yyyy-MM-dd_HH-mm-ss}.log" -f (Get-Date))
    $Log = "$LogPath\$LogFile"

    $LogT = Test-Path -Path $Log

    If ($LogT)
    {
        Clear-Content -Path $Log
    }

    Add-Content -Path $Log -Encoding ASCII -Value "$(Get-Date -Format "yyyy-MM-dd HH:mm:ss") [INFO] Log started"
}

## Function to get date in specific format.
Function Get-DateFormat
{
    Get-Date -Format "yyyy-MM-dd HH:mm:ss"
}

## Function for logging.
Function Write-Log($Type, $Event)
{
    If ($Type -eq "Info")
    {
        If ($Null -ne $LogPath)
        {
            Add-Content -Path $Log -Encoding ASCII -Value "$(Get-DateFormat) [INFO] $Event"
        }
        
        Write-Host "$(Get-DateFormat) [INFO] $Event"
    }

    If ($Type -eq "Succ")
    {
        If ($Null -ne $LogPath)
        {
            Add-Content -Path $Log -Encoding ASCII -Value "$(Get-DateFormat) [SUCCESS] $Event"
        }

        Write-Host -ForegroundColor Green "$(Get-DateFormat) [SUCCESS] $Event"
    }

    If ($Type -eq "Err")
    {
        If ($Null -ne $LogPath)
        {
            Add-Content -Path $Log -Encoding ASCII -Value "$(Get-DateFormat) [ERROR] $Event"
        }

        Write-Host -ForegroundColor Red -BackgroundColor Black "$(Get-DateFormat) [ERROR] $Event"
    }
}

## Function for the options post backup.
Function OptionsRun
{
    ## If the -keep switch AND the -compress switch are NOT configured.
    If ($Null -eq $History -And $Compress -eq $False)
    {
        ## Remove all previous backup folders, including ones from previous versions of this script.
        Get-ChildItem -Path $WorkDir -Filter "$Vm-*-*-***-*-*" -Directory | Remove-Item -Recurse -Force

        ## If a working directory is configured by the user, remove all previous backup folders, including
        ## ones from previous versions of this script.
        If ($WorkDir -ne $Backup)
        {
            Get-ChildItem -Path $Backup -Filter "$Vm-*-*-***-*-*" -Directory | Remove-Item -Recurse -Force
        }

        Write-Log -Type Info -Event "Removing previous backups of $Vm"
    }

    ## If the -keep option IS configured AND the -compress option is NOT configured.
    else {
        If ($Compress -eq $False)
        {
            ## Remove previous backup folders older than the configured number of days, including
            ## ones from previous versions of this script.
            Get-ChildItem -Path $WorkDir -Filter "$Vm-*-*-***-*-*" -Directory | Where-Object CreationTime –lt (Get-Date).AddDays(-$History) | Remove-Item -Recurse -Force

            ## If a working directory is configured by the user, remove previous backup folders
            ## older than the configured number of days remove all previous backup folders,
            ## including ones from previous versions of this script.
            If ($WorkDir -ne $Backup)
            {
                Get-ChildItem -Path $Backup -Filter "$Vm-*-*-***-*-*" -Directory | Where-Object CreationTime –lt (Get-Date).AddDays(-$History) | Remove-Item -Recurse -Force
            }

            Write-Log -Type Info -Event "Removing backup folders older than: $History days"
        }
    }

    ## Check to see if the -compress switch IS configured AND if the -keep switch is NOT configured.
    If ($Compress)
    {
        If ($Null -eq $History)
        {
            ## Remove all previous compressed backups, including ones from previous versions of this script.
            Remove-Item "$WorkDir\$Vm-*-*-***-*-*.zip" -Force

            ## If a working directory is configured by the user, remove all previous compressed backups,
            ## including ones from previous versions of this script.
            If ($WorkDir -ne $Backup)
            {
                Remove-Item "$Backup\$Vm-*-*-***-*-*.zip" -Force
            }

            Write-Log -Type Info -Event "Removing previous compressed backups"
        }

        ## If the -compress switch IS configured AND if the -keep switch IS configured.
        else {
            
            ## Remove previous compressed backups older than the configured number of days, including
            ## ones from previous versions of this script.
            Get-ChildItem -Path "$WorkDir\$Vm-*-*-***-*-*.zip" | Where-Object CreationTime –lt (Get-Date).AddDays(-$History) | Remove-Item -Force

            ## If a working directory is configured by the user, remove previous compressed backups older
            ## than the configured number of days, including ones from previous versions of this script.
            If ($WorkDir -ne $Backup)
            {
                Get-ChildItem -Path "$Backup\$Vm-*-*-***-*-*.zip" | Where-Object CreationTime –lt (Get-Date).AddDays(-$History) | Remove-Item -Force
            }

            Write-Log -Type Info -Event "Removing compressed backups older than: $History days"
        }

        ## If the -compress switch and the -Sz switch IS configured, test for 7zip being installed.
        ## If it is, compress the backup folder, if it is not use Windows compression.
        If ($Sz -eq $True)
        {
            $7zT = Test-Path "$env:programfiles\7-Zip\7z.exe"
            If ($7zT -eq $True)
            {
                Write-Log -Type Info -Event "Compressing using 7-Zip compression"
                & "$env:programfiles\7-Zip\7z.exe" -bso0 a -tzip ("$WorkDir\$Vm-{0:yyyy-MM-dd_HH-mm-ss}.zip" -f (Get-Date)) "$WorkDir\$Vm\*"
            }

            else {
                Write-Log -Type Info -Event "Compressing using Windows compression"
                Add-Type -AssemblyName "system.io.compression.filesystem"
                [io.compression.zipfile]::CreateFromDirectory("$WorkDir\$Vm", ("$WorkDir\$Vm-{0:yyyy-MM-dd_HH-mm-ss}.zip" -f (Get-Date)))
            }
        }

        ## If the -compress switch IS configured and the -Sz switch is NOT configured, compress
        ## the backup folder using Windows compression.
        else {
            Write-Log -Type Info -Event "Compressing using Windows compression"
            Add-Type -AssemblyName "system.io.compression.filesystem"
            [io.compression.zipfile]::CreateFromDirectory("$WorkDir\$Vm", ("$WorkDir\$Vm-{0:yyyy-MM-dd_HH-mm-ss}.zip" -f (Get-Date)))
        }

        ## Test if the compressed file was created.
        $VmZipT = Test-Path "$WorkDir\$Vm-*-*-***-*-*.zip"
        If ($VmZipT -eq $True)
        {
            Write-Log -Type Succ -Event "Successfully created compressed backup of $Vm in $WorkDir"
        }

        else {
            Write-Log -Type Err -Event "There was a problem creating a compressed backup of $Vm in $WorkDir"
        }
        ## End of testing for file creation.

        ## Remove the VMs export folder.
        Get-ChildItem -Path $WorkDir -Filter "$Vm" -Directory | Remove-Item -Recurse -Force

        ## If a working directory has been configured by the user, move the compressed
        ## backup to the backup location and rename to include the date.
        If ($WorkDir -ne $Backup)
        {
            Get-ChildItem -Path $WorkDir -Filter "$Vm-*-*-*-*-*.zip" | Move-Item -Destination $Backup

            ## Test if the move suceeded.
            $VmMoveT = Test-Path "$Backup\$Vm-*-*-*-*-*.zip"
            If ($VmMoveT -eq $True)
            {
                Write-Log -Type Succ -Event "Successfully moved compressed backup of $Vm to $Backup"
            }

            else {
                Write-Log -Type Err -Event "There was a problem moving compressed backup of $Vm to $Backup"
            }
            ## End of testing for move.
        }
    }

    ## If the -compress switch is NOT configured AND if the -keep switch is NOT configured, rename
    ## the export of each VM to include the date.
    else {
        Get-ChildItem -Path $WorkDir -Filter $Vm -Directory | Rename-Item -NewName ("$WorkDir\$Vm-{0:yyyy-MM-dd_HH-mm-ss}" -f (Get-Date))

        If ($WorkDir -ne $Backup)
        {
            Get-ChildItem -Path $WorkDir -Filter "$Vm-*-*-***-*-*" -Directory | Move-Item -Destination ("$Backup\$Vm-{0:yyyy-MM-dd_HH-mm-ss}" -f (Get-Date))

            ## Test if the move suceeded.
            $VmMoveT = Test-Path "$Backup\$Vm-*-*-***-*-*"
            If ($VmMoveT -eq $True)
            {
                Write-Log -Type Succ -Event "Successfully moved export of $Vm to $Backup"
            }

            else {
                Write-Log -Type Err -Event "There was a problem moving export of $Vm to $Backup"
            }

            ## End of testing.
        }
    }
}

## Set a variable for computer name of the Hyper-V server.
$Vs = $Env:ComputerName

## If a VM list file is configured, get the content of the file.
## If a VM list file is not configured, just get the running VMs.
If ($VmList)
{
    $Vms = Get-Content $VmList
}

else {
    $Vms = Get-VM | Where-Object {$_.State -eq 'Running'} | Select-Object -ExpandProperty Name
}

## Check to see if there are any running VMs.
## If there are no VMs, then do nothing.
If ($Vms.count -ne 0)
{
    ## If the user has not configured the working directory, set it as the backup directory.
    If ($Null -eq $WorkDir)
    {
        $WorkDir = "$Backup"
    }

    ##
    ## Display the current config and log if configured.
    ##
    If ($LogPath)
    {
        Add-Content -Path $Log -Encoding ASCII -Value "************ Running with the following config *************`r"
    }

    Write-Host "************ Running with the following config *************"

    If ($LogPath)
    {
        Add-Content -Path $Log -Encoding ASCII -Value "This virtual host is: $Vs"
        Add-Content -Path $Log -Encoding ASCII -Value "The following VMs will be backed up:"

        ForEach ($Vm in $Vms)
        {
            Add-Content -Path $Log -Encoding ASCII -Value "    $Vm"
        }
    }

    Write-Host "This virtual host is: $Vs"
    Write-Host "The following VMs will be backed up:"

    ForEach ($Vm in $Vms)
    {
        Write-Host -ForegroundColor Cyan -Object "    $Vm"
    }

    If ($LogPath)
    {
        Add-Content -Path $Log -Encoding ASCII -Value "Backup directory is: $Backup"
        Add-Content -Path $Log -Encoding ASCII -Value "Working directory is: $WorkDir"

        If ($Null -ne $History)
        {
            Add-Content -Path $Log -Encoding ASCII -Value "Days of backups to keep: $History days"
        }

        else {
            Add-Content -Path $Log -Encoding ASCII -Value "Days of backups to keep: No Config"
        }

        If ($Null -ne $LogPath)
        {
            Add-Content -Path $Log -Encoding ASCII -Value "Logs directory: $LogPath"
        }

        else {
            Add-Content -Path $Log -Encoding ASCII -Value "Logs directory: No Config"
        }

        If ($MailTo)
        {
            Add-Content -Path $Log -Encoding ASCII -Value "E-mail address to send log to is: $MailTo`r"
        }

        else {
            Add-Content -Path $Log -Encoding ASCII -Value "E-mail address to send log to is: No Config"
        }

        If ($MailFrom)
        {
            Add-Content -Path $Log -Encoding ASCII -Value "E-mail address to send log from is: $MailFrom`r"
        }

        else {
            Add-Content -Path $Log -Encoding ASCII -Value "E-mail address to send log from is: No Config"
        }

        If ($MailSubject)
        {
            Add-Content -Path $Log -Encoding ASCII -Value "E-mail subject: $MailSubject`r"
        }

        else {
            Add-Content -Path $Log -Encoding ASCII -Value "E-mail subject: Default"
        }

        If ($SmtpServer)
        {
            Add-Content -Path $Log -Encoding ASCII -Value "SMTP server is: $SmtpServer`r"
        }

        else {
            Add-Content -Path $Log -Encoding ASCII -Value "SMTP server is: No Config"
        }

        If ($SmtpUser)
        {
            Add-Content -Path $Log -Encoding ASCII -Value "SMTP user is: $SmtpUser`r"
        }

        else {
            Add-Content -Path $Log -Encoding ASCII -Value "SMTP user is: No Config"
        }

        If ($SmtpPwd)
        {
            Add-Content -Path $Log -Encoding ASCII -Value "SMTP pwd file: $SmtpPwd`r"
        }

        else {
            Add-Content -Path $Log -Encoding ASCII -Value "SMTP pwd file: No Config"
        }

        Add-Content -Path $Log -Encoding ASCII -Value "The -NoPerms switch is: $NoPerms`r"
        Add-Content -Path $Log -Encoding ASCII -Value "The -Compress switch is: $Compress`r"
        Add-Content -Path $Log -Encoding ASCII -Value "The -Sz switch is: $Sz"
        Add-Content -Path $Log -Encoding ASCII -Value "************************************************************"
    }

    Write-Host "Backup directory is: $Backup"
    Write-Host "Working directory is: $WorkDir"
    
    If ($Null -ne $History)
    {
        Write-Host "Days of backups to keep: $History days"
    }

    else {
        Write-Host "Days of backups to keep: No Config"
    }

    If ($LogPath)
    {
        Write-Host "Logs directory: $LogPath"
    }

    else {
        Write-Host "Logs directory: No Config"
    }

    If ($MailTo)
    {
        Write-Host "E-mail address to send log to is: $MailTo"
    }

    else {
        Write-Host "E-mail address to send log to is: No Config"
    }

    If ($MailFrom)
    {
        Write-Host "E-mail address to send log from is: $MailFrom"
    }

    else {
        Write-Host "E-mail address to send log from is: No Config"
    }

    If ($MailSubject)
    {
        Write-Host "E-mail subject: $MailSubject"
    }

    else {
        Write-Host "E-mail subject: Default"
    }

    If ($SmtpServer)
    {
        Write-Host "SMTP server is: $SmtpServer"
    }

    else {
        Write-Host "SMTP server is: No Config"
    }

    If ($SmtpUser)
    {
        Write-Host "SMTP user is: $SmtpUser"
    }

    else {
        Write-Host "SMTP user is: No Config"
    }

    If ($SmtpPwd)
    {
        Write-Host "SMTP pwd file: $SmtpPwd"
    }

    else {
        Write-Host "SMTP pwd file: No Config"
    }

    Write-Host "The -NoPerms switch is: $NoPerms"
    Write-Host "The -Compress switch is: $Compress"
    Write-Host "The -Sz switch is: $Sz"
    Write-Host "************************************************************"
    Write-Host ""
    Write-Log -Type Info -Event "Process started."

    ##
    ## Display current config ends here.
    ##

    ##
    ## -NoPerms process starts here.
    ##

    ## If the -noperms switch is set, start a custom process to copy all the VM data.
    If ($NoPerms)
    {
        ForEach ($Vm in $Vms)
        {
            $VmInfo = Get-VM -name $Vm

            ## Test for the existence of a previous VM export. If it exists, delete it.
            $VmExportBackupTest = Test-Path "$WorkDir\$Vm"
            If ($VmExportBackupTest -eq $True)
            {
                Remove-Item "$WorkDir\$Vm" -Recurse -Force
            }

            ## Create directories for the VM export.
            New-Item "$WorkDir\$Vm" -ItemType Directory -Force | Out-Null
            New-Item "$WorkDir\$Vm\Virtual Machines" -ItemType Directory -Force | Out-Null
            New-Item "$WorkDir\$Vm\VHD" -ItemType Directory -Force | Out-Null
            New-Item "$WorkDir\$Vm\Snapshots" -ItemType Directory -Force | Out-Null

            ##
            ## Test for the creation of backup folders. If they created sucessfully, report it. If they didn't, also report it.
            ##

            $VmFolderTest = Test-Path "$WorkDir\$Vm\Virtual Machines"
            If ($VmFolderTest -eq $True)
            {
                Write-Log -Type Succ -Event "Successfully created backup folder $WorkDir\$Vm\Virtual Machines"
            }

            else {
                Write-Log -Type Err -Event "There was a problem creating folder $WorkDir\$Vm\Virtual Machines"
            }

            $VmVHDTest = Test-Path "$WorkDir\$Vm\VHD"
            If ($VmVHDTest -eq $True)
            {
                Write-Log -Type Succ -Event "Successfully created backup folder $WorkDir\$Vm\VHD"
            }

            else {
                Write-Log -Type Err -Event "There was a problem creating folder $WorkDir\$Vm\VHD"
            }
            
            $VmSnapTest = Test-Path "$WorkDir\$Vm\Snapshots"
            If ($VmSnapTest -eq $True)
            {
                Write-Log -Type Succ -Event "Successfully created backup folder $WorkDir\$Vm\Snapshots"
            }

            else {
                Write-Log -Type Err -Event "There was a problem creating folder $WorkDir\$Vm\Snapshots"
            }

            ##
            ## End of folder creation testing.
            ##

            Write-Log -Type Info -Event "Stopping VM: $Vm"
            Stop-VM $Vm

            ##
            ## Copy the VM config files and test for success or failure.
            ##

            Copy-Item "$($VmInfo.ConfigurationLocation)\Virtual Machines\$($VmInfo.id)" "$WorkDir\$Vm\Virtual Machines\" -Recurse -Force
            Copy-Item "$($VmInfo.ConfigurationLocation)\Virtual Machines\$($VmInfo.id).*" "$WorkDir\$Vm\Virtual Machines\" -Recurse -Force

            $VmConfigTest = Test-Path "$WorkDir\$Vm\Virtual Machines\*"
            If ($VmConfigTest -eq $True)
            {
                Write-Log -Type Succ -Event "Successfully copied $Vm configuration to $WorkDir\$Vm\Virtual Machines"
            }

            else {
                Write-Log -Type Err -Event "There was a problem copying the configuration for $Vm"
            }

            ##
            ## End of VM config files.
            ##

            ##
            ## Copy the VHDs and test for success or failure.
            ##

            Copy-Item $VmInfo.HardDrives.Path -Destination "$WorkDir\$Vm\VHD\" -Recurse -Force

            $VmVHDCopyTest = Test-Path "$WorkDir\$Vm\VHD\*"
            If ($VmVHDCopyTest -eq $True)
            {
                Write-Log -Type Succ -Event "Successfully copied $Vm VHDs to $WorkDir\$Vm\VHD"
            }

            else {
                Write-Log -Type Err -Event "There was a problem copying the VHDs for $Vm"
            }

            ##
            ## End of VHDs.
            ##

            ## Get the VM snapshots/checkpoints.
            $Snaps = Get-VMSnapshot $Vm

            ForEach ($Snap in $Snaps)
            {
                ##
                ## Copy the snapshot config files and test for success or failure.
                ##

                Copy-Item "$($VmInfo.ConfigurationLocation)\Snapshots\$($Snap.id)" "$WorkDir\$Vm\Snapshots\" -Recurse -Force
                Copy-Item "$($VmInfo.ConfigurationLocation)\Snapshots\$($Snap.id).*" "$WorkDir\$Vm\Snapshots\" -Recurse -Force

                $VmSnapCopyTest = Test-Path "$WorkDir\$Vm\Snapshots\*"
                If ($VmSnapCopyTest -eq $True)
                {
                    Write-Log -Type Succ -Event "Successfully copied checkpoint configuration for $WorkDir\$Vm\Snapshots"
                }

                else {
                    Write-Log -Type Err -Event "There was a problem copying the checkpoint configuration for $Vm"
                }

                ##
                ## End of snapshot config.
                ##

                ## Copy the snapshot root VHD.
                Copy-Item $Snap.HardDrives.Path -Destination "$WorkDir\$Vm\VHD\" -Recurse -Force
                Write-Log -Type Succ -Event "Successfully copied checkpoint VHDs for $Vm to $WorkDir\$Vm\VHD"
            }

            Start-VM $Vm
            Write-Log -Type Info -Event "Starting VM: $Vm"
            Start-Sleep -S 60
            OptionsRun
        }
    }

    ##
    ## -NoPerms process ends here.
    ##
    ##
    ##
    ## Standard export process starts here.
    ##

    ## If the -NoPerms switch is NOT set, for each VM check for the existence of a previous export.
    ## If it exists then delete it, otherwise the export will fail.
    else {
        ForEach ($Vm in $Vms)
        {
            $VmExportBackupTest = Test-Path "$WorkDir\$Vm"
            If ($VmExportBackupTest -eq $True)
            {
                Remove-Item "$WorkDir\$Vm" -Recurse -Force
            }

            If ($WorkDir -ne $Backup)
            {
                $VmExportWDT = Test-Path "$Backup\$Vm"
                If ($VmExportWDT -eq $True)
                {
                    Remove-Item "$Backup\$Vm" -Recurse -Force
                }
            }
        }

        ## Do a regular export of the VMs.
        $Vms | Export-VM -Path "$WorkDir"

        ## Test if the export suceeded.
        $VmExportTest = Test-Path "$WorkDir\*"
        If ($VmExportTest -eq $True)
        {
            Write-Log -Type Succ -Event "Successfully exported specified VMs to $WorkDir"
        }

        else {
            Write-Log -Type Err -Event "There was a problem exporting the specified VMs to $WorkDir"
        }

        ## Run the configuration options on the above backup files and folders.
        ForEach ($Vm in $Vms)
        {
            OptionsRun
        }
    }
}

## If there are no VMs running, then do nothing.
else {
    Write-Log -Type Info -Event "There are no VMs running to backup"
}

Write-Log -Type Info -Event "Process finished."

## If logging is configured then finish the log file.
If ($LogPath)
{
    Add-Content -Path $Log -Encoding ASCII -Value "$(Get-Date -Format "yyyy-MM-dd HH:mm:ss") [INFO] Log finished"

    ## This whole block is for e-mail, if it is configured.
    If ($SmtpServer)
    {
        ## Default e-mail subject if none is configured.
        If ($Null -eq $MailSubject)
        {
            $MailSubject = "Hyper-V Backup Utility Log"
        }

        ## Setting the contents of the log to be the e-mail body. 
        $MailBody = Get-Content -Path $Log | Out-String

        ## If an smtp password is configured, get the username and password together for authentication.
        ## If an smtp password is not provided then send the e-mail without authentication and obviously no SSL.
        If ($SmtpPwd)
        {
            $SmtpPwdEncrypt = Get-Content $SmtpPwd | ConvertTo-SecureString
            $SmtpCreds = New-Object System.Management.Automation.PSCredential -ArgumentList ($SmtpUser, $SmtpPwdEncrypt)

            ## If -ssl switch is used, send the email with SSL.
            ## If it isn't then don't use SSL, but still authenticate with the credentials.
            If ($UseSsl)
            {
                Send-MailMessage -To $MailTo -From $MailFrom -Subject $MailSubject -Body $MailBody -SmtpServer $SmtpServer -UseSsl -Credential $SmtpCreds
            }

            else {
                Send-MailMessage -To $MailTo -From $MailFrom -Subject $MailSubject -Body $MailBody -SmtpServer $SmtpServer -Credential $SmtpCreds
            }
        }

        else {
            Send-MailMessage -To $MailTo -From $MailFrom -Subject $MailSubject -Body $MailBody -SmtpServer $SmtpServer
        }
    }
}

## End