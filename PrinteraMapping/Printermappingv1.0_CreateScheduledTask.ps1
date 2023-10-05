# ------------------------------------------------------------------------------------------------------------ #
# Author(s)    : Peter Klapwijk - www.inthecloud247.com			                                       		   #
# Version      : 1.0                                                                                           #
#                                                                                                              #
# Description  : Create a Scheduled task to map network printers. Task runs at user logon                      #
#                                                                                                              #
# Changes      : v1.0 - Initial version                                  		                       		   # 
#                                                                                                              #
#                                                                                                              #                     
#------------------------------------------------------------------------------------------------------------- #

# Microsoft Intune Management Extension might start a 32-bit PowerShell instance. If so, restart as 64-bit PowerShell
If ($ENV:PROCESSOR_ARCHITEW6432 -eq "AMD64") {
    Try {
        &"$ENV:WINDIR\SysNative\WindowsPowershell\v1.0\PowerShell.exe" -File $PSCOMMANDPATH
    }
    Catch {
        Throw "Failed to start $PSCOMMANDPATH"
    }
    Exit
}

#Set variables:
#Company name
$CompanyName = "Klapwijk"

#region Functions
Function CleanUpAndExit() {
    Param(
        [Parameter(Mandatory=$True)][String]$ErrorLevel
    )

    # Write results to registry for Intune Detection
    $Key = "HKEY_LOCAL_MACHINE\Software\$CompanyName\PrinterMapping\v1.0"
    $NOW = Get-Date -Format "yyyyMMdd-hhmmss"

    If ($ErrorLevel -eq "0") {
        [microsoft.win32.registry]::SetValue($Key, "Scheduled", $NOW)
    } else {
        [microsoft.win32.registry]::SetValue($Key, "Failure", $NOW)
        [microsoft.win32.registry]::SetValue($Key, "Error Code", $Errorlevel)
    }
    
    # Exit Script with the specified ErrorLevel
    Stop-Transcript | Out-Null
    EXIT $ErrorLevel
}

#endregion Functions


# ------------------------------------------------------------------------------------------------------- #
# Start Transcript
# ------------------------------------------------------------------------------------------------------- #
$Transcript = "C:\programdata\Microsoft\IntuneManagementExtension\Logs\$($(Split-Path $PSCommandPath -Leaf).ToLower().Replace(".ps1",".log"))"
Start-Transcript -Path $Transcript | Out-Null


# ------------------------------------------------------------------------------------------------------- #
# Variables
# ------------------------------------------------------------------------------------------------------- #
$TaskScriptName = "Printermappingv1.0_ScriptRunFromTaskScheduler.vbs"
$TaskScriptName2 = "Printermappingv1.0_ScriptRunFromTaskScheduler.ps1"
$TaskScriptFolder = "C:\Program Files\Common Files\$CompanyName\PrinterMapping"
$ScriptSourceDirectory = Split-Path -Parent $PSCommandPath

# ------------------------------------------------------------------------------------------------------- #
# Create local copy of the script to be run from the Task Scheduler
# ------------------------------------------------------------------------------------------------------- #
if (!(Test-Path -path $TaskScriptFolder)) {
# Target Folder does not yet exist
	Write-Host "Creating Folder '$TaskScriptFolder' ..."
	New-Item $TaskScriptFolder -Type Directory | Out-Null
}

try {
	Write-Host "Source folder to copy script from: '$ScriptSourceDirectory'"
	Copy-Item "$ScriptSourceDirectory\$TaskScriptName" -Destination "$TaskScriptFolder" -ErrorAction Stop | Out-Null
	Write-Host "Created local copy of the script '$TaskScriptName' in folder: '$TaskScriptFolder'"
} catch {
	Write-Host "ERROR creating local copy of the script '$TaskScriptName' in folder: '$TaskScriptFolder'"
	CleanUpAndExit -ErrorLevel 1
}

try {
	Write-Host "Source folder to copy script from: '$ScriptSourceDirectory'"
	Copy-Item "$ScriptSourceDirectory\$TaskScriptName2" -Destination "$TaskScriptFolder" -ErrorAction Stop | Out-Null
	Write-Host "Created local copy of the script '$TaskScriptName2' in folder: '$TaskScriptFolder'"
} catch {
	Write-Host "ERROR creating local copy of the script '$TaskScriptName2' in folder: '$TaskScriptFolder'"
	CleanUpAndExit -ErrorLevel 1
}

# ------------------------------------------------------------------------------------------------------- #
# Create Scheduled Task to run At Logon
# ------------------------------------------------------------------------------------------------------- #
# General parameters
$TaskName = "MapNetworkPrinters"
$TaskDescription = "Map network printers"
$TaskSettings = New-ScheduledTaskSettingsSet -Compatibility Win8 -MultipleInstances IgnoreNew -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -Hidden -StartWhenAvailable
# Define the triggers of the scheduled task
# Configure a trigger to run the script at logon of any user
$Trigger = New-ScheduledTaskTrigger -AtLogon
# Define the action of the Scheduled task
$TaskAction = New-ScheduledTaskAction -Execute "wscript.exe" -Argument "`"$TaskScriptFolder\$TaskScriptName`""
#Define the principal
$TaskPrincipal = New-ScheduledTaskPrincipal -GroupId "S-1-5-32-545"
# Register the Scheduled task
$ModifiedTask = Register-ScheduledTask -Action $TaskAction -Trigger $Trigger -Settings $TaskSettings -TaskPath $CompanyName -TaskName $TaskName  -Description $TaskDescription -Principal $TaskPrincipal -Force 
# Modify Task to add a delay
$ModifiedTask.Triggers[0].Delay = 'PT4M'
Set-ScheduledTask -InputObject $ModifiedTask


# ------------------------------------------------------------------------------------------------------- #
# Check End State
# ------------------------------------------------------------------------------------------------------- #
try {
    Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop | Out-Null
    write-host "SUCCESS: Task is Scheduled."
    CleanUpAndExit -ErrorLevel 0
} catch {
    write-host "ERROR: Scheduled Task could not be found."
    CleanUpAndExit -ErrorLevel 2
}