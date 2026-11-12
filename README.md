# Taskbar Auto-Align

Automatically centers the Windows 11 taskbar when an external monitor is connected, and moves it back to the left when the laptop's built-in screen is the only display.

Docked at a desk, a centered taskbar sits naturally in the middle of a large monitor. On the laptop alone, left-aligned icons are quicker to reach. Windows only offers one fixed setting, so this script switches it for you.

## Features

- **Works with any external monitor.** It detects how each screen is connected (HDMI, DisplayPort, USB-C, dock), not its brand or model.
- **Event-driven.** It reacts to Windows display-change events instead of constantly polling, so the CPU and battery cost is negligible.
- **Respects manual changes.** It only switches alignment when your display setup changes. If you set the alignment yourself in Settings, it stays that way until the next dock, undock or restart.
- **Invisible.** It runs at logon as a scheduled task with no console window.
- **Single instance.** A second copy exits immediately.
- **Clean uninstall.** One command removes everything.

## Requirements

- Windows 11
- Windows PowerShell 5.1 (built into Windows)
- Works on both x64 and ARM64. Tested on an ARM64 Surface with a Dell monitor over USB-C (DisplayPort).

## Installation

1. Download `TaskbarAutoAlign.ps1` and `Install.ps1` into a permanent folder, for example `C:\Tools\TaskbarAutoAlign`. The scheduled task points at this folder, so don't move the files afterwards.
2. Unblock the downloaded files:
   ```powershell
   cd C:\Tools\TaskbarAutoAlign
   Get-ChildItem *.ps1 | Unblock-File
   ```
3. Install:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\Install.ps1
   ```
   If you get an access-denied error, run the same command from an elevated (Run as administrator) PowerShell window.

The task starts immediately and then at every logon.

## Uninstallation

```powershell
powershell -ExecutionPolicy Bypass -File .\Install.ps1 -Uninstall
```

This stops and removes the scheduled task. The taskbar keeps its current alignment, and you can change it by hand in **Settings → Personalization → Taskbar → Taskbar behaviors**.

## How it works

1. **Detection.** The script reads `WmiMonitorConnectionParams` (namespace `root\wmi`), which lists every monitor, whether it is active, and how it is connected. A built-in panel reports as internal (`2147483648`) or embedded DisplayPort (`11`). Any other active connection counts as an external monitor.
2. **Trigger.** It subscribes to `Microsoft.Win32.SystemEvents.DisplaySettingsChanged`. After an event it waits 1.5 seconds for the cable or dock handshake to settle, then re-checks. A fallback re-check runs every 30 seconds in case an event is missed.
3. **Action.** When the external-monitor state changes, it sets the `TaskbarAl` value under `HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced` (`0` = left, `1` = center) and notifies the shell so the taskbar updates immediately.
4. **Startup.** `Install.ps1` registers a per-user scheduled task that runs at logon through `conhost.exe --headless`, so no window appears.

## Options

| Parameter | Default | Description |
|---|---|---|
| `-SafetyPollSeconds` | `30` | Interval for the fallback re-check |
| `-Log` | off | Writes a log to `%LOCALAPPDATA%\TaskbarAutoAlign\TaskbarAutoAlign.log` |

To enable logging, open **Task Scheduler**, find the `TaskbarAutoAlign` task, and add `-Log` at the end of the action's arguments.

## Troubleshooting

**The taskbar never changes, or stays centered when undocked.**

Check what your display driver reports:

```powershell
Get-CimInstance -Namespace root\wmi WmiMonitorConnectionParams |
    Select-Object InstanceName, Active, VideoOutputTechnology
```

Your built-in screen should show `2147483648` or `11`. If it shows another value, add that value to the `$InternalTech` list near the top of `TaskbarAutoAlign.ps1`, then sign out and back in.

**How do I check it's running only once?**

```powershell
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object CommandLine -like '*TaskbarAutoAlign*' |
    Select-Object ProcessId, CommandLine
```

This should return exactly one line.

## About execution policy

The scheduled task runs the script with `-ExecutionPolicy Bypass`. This applies only to that single process and does not change your system's execution policy. As with any script from the internet, read it before you run it. It is short, and it is commented throughout.

## License

[MIT](LICENSE) © Osvaldo de Sousa

## Author

Osvaldo de Sousa · [osousa.com](https://www.osousa.com)
