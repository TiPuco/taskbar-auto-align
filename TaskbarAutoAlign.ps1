<#
.SYNOPSIS
    Centers the Windows 11 taskbar when an external monitor is active and
    left-aligns it when the built-in screen is the only display.

.DESCRIPTION
    Listens for Windows display-change events instead of polling. On every
    change it checks whether any active monitor is connected through an
    external output (HDMI, DisplayPort, USB-C, dock...). If so, the taskbar is
    centered; otherwise it is left-aligned.

    The alignment is only changed when the display setup changes, so a manual
    change made in Settings is respected until the next dock/undock.

.PARAMETER SafetyPollSeconds
    Fallback re-check interval in case a display event is missed. Default 30.

.PARAMETER Log
    Writes a log to %LOCALAPPDATA%\TaskbarAutoAlign\TaskbarAutoAlign.log

.NOTES
    Author:  Osvaldo de Sousa - https://www.osousa.com
    License: MIT
    Requires Windows 11 and Windows PowerShell 5.1 or PowerShell 7.
#>

[CmdletBinding()]
param(
    [int]$SafetyPollSeconds = 30,
    [switch]$Log
)

$RegPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
$LogFile = Join-Path $env:LOCALAPPDATA 'TaskbarAutoAlign\TaskbarAutoAlign.log'

# --- Single instance: exit if another copy is already running in this session
$Mutex = New-Object System.Threading.Mutex($false, 'Local\TaskbarAutoAlign')
if (-not $Mutex.WaitOne(0)) { exit }

function Write-Log {
    param([string]$Message)
    if (-not $Log) { return }
    $dir = Split-Path $LogFile
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Add-Content -Path $LogFile -Value ('{0:yyyy-MM-dd HH:mm:ss}  {1}' -f (Get-Date), $Message)
}

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class ShellNotify {
    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern IntPtr SendMessageTimeout(
        IntPtr hWnd, uint Msg, IntPtr wParam, string lParam,
        uint fuFlags, uint uTimeout, out IntPtr lpdwResult);
}
'@

# DISPLAYCONFIG_VIDEO_OUTPUT_TECHNOLOGY values that mean "built-in panel":
# INTERNAL (0x80000000), DISPLAYPORT_EMBEDDED (11), UDI_EMBEDDED (13)
$InternalTech = [uint32[]](2147483648, 11, 13)

function Test-ExternalDisplayActive {
    $monitors = Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorConnectionParams -ErrorAction SilentlyContinue
    foreach ($m in $monitors) {
        if ($m.Active -and ([uint32]$m.VideoOutputTechnology -notin $InternalTech)) {
            return $true
        }
    }
    return $false
}

function Set-TaskbarAlignment {
    param([int]$Value)   # 0 = Left, 1 = Center
    $current = (Get-ItemProperty -Path $RegPath -Name TaskbarAl -ErrorAction SilentlyContinue).TaskbarAl
    if ($current -eq $Value) { return }

    Set-ItemProperty -Path $RegPath -Name TaskbarAl -Value $Value -Type DWord -Force

    # Tell the shell the tray settings changed so it applies them immediately
    $result = [IntPtr]::Zero
    [void][ShellNotify]::SendMessageTimeout([IntPtr]0xffff, 0x001A, [IntPtr]::Zero, 'TraySettings', 2, 250, [ref]$result)
    (New-Object -ComObject Shell.Application).RefreshMenu()

    Write-Log "TaskbarAl set to $Value"
}

$script:LastState = $null

function Update-Alignment {
    $external = Test-ExternalDisplayActive
    if ($external -ne $script:LastState) {
        $script:LastState = $external
        Write-Log "External display active: $external"
        Set-TaskbarAlignment -Value $(if ($external) { 1 } else { 0 })
    }
}

# --- Subscribe to display changes (dock/undock, lid close, resolution change)
Register-ObjectEvent -InputObject ([Microsoft.Win32.SystemEvents]) `
    -EventName DisplaySettingsChanged -SourceIdentifier 'TaskbarAutoAlign.DisplayChanged' | Out-Null

Write-Log 'Started'
try { Update-Alignment } catch { Write-Log "Error: $($_.Exception.Message)" }

while ($true) {
    $evt = Wait-Event -SourceIdentifier 'TaskbarAutoAlign.DisplayChanged' -Timeout $SafetyPollSeconds
    if ($evt) {
        # Let the cable/dock handshake settle, then drop any burst of queued events
        Start-Sleep -Milliseconds 1500
        Get-Event -SourceIdentifier 'TaskbarAutoAlign.DisplayChanged' -ErrorAction SilentlyContinue | Remove-Event
    }
    try { Update-Alignment } catch { Write-Log "Error: $($_.Exception.Message)" }
}
