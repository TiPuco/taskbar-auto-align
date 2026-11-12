<#
.SYNOPSIS
    Installs or removes TaskbarAutoAlign as a hidden logon task for the current user.

.EXAMPLE
    .\Install.ps1              # install and start
    .\Install.ps1 -Uninstall   # stop and remove

.NOTES
    Author:  Osvaldo de Sousa - https://www.osousa.com
    License: MIT
#>

[CmdletBinding()]
param([switch]$Uninstall)

$TaskName = 'TaskbarAutoAlign'
$User     = "$env:USERDOMAIN\$env:USERNAME"

if ($Uninstall) {
    Stop-ScheduledTask       -TaskName $TaskName -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "Removed '$TaskName'. Taskbar alignment is back under manual control."
    return
}

$Script = Join-Path $PSScriptRoot 'TaskbarAutoAlign.ps1'
if (-not (Test-Path $Script)) { throw "TaskbarAutoAlign.ps1 not found next to Install.ps1" }

# conhost --headless runs PowerShell with no window at all (no console flash at logon)
$Action    = New-ScheduledTaskAction -Execute 'conhost.exe' `
               -Argument "--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$Script`""
$Trigger   = New-ScheduledTaskTrigger -AtLogOn -User $User
$Principal = New-ScheduledTaskPrincipal -UserId $User -LogonType Interactive -RunLevel Limited
$Settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
               -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew

Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger `
    -Principal $Principal -Settings $Settings -Force | Out-Null
Start-ScheduledTask -TaskName $TaskName

Write-Host "Installed '$TaskName'. It starts at every logon and is running now."
