# Bright Spot Mask · 亮斑遮罩

A Windows utility that places two adjustable, click-through radial overlays over a selected display. It can reduce the visual distraction of a localized bright spot; it does not repair the panel or change its hardware brightness.

用于 Windows 的局部亮斑遮罩：在选定显示器上显示两层可独立调节的圆形渐变遮罩，鼠标点击可穿透。遮罩用于减轻亮斑的视觉干扰，不能修复屏幕硬件。

## Requirements / 运行环境

- Windows 10 version 2004 or later, or Windows 11.
- Windows PowerShell 5.1 (`powershell.exe`), WPF, and the Windows .NET Framework assemblies used by the scripts. The launcher uses Windows PowerShell, rather than PowerShell 7.
- Keep all app files together in a writable folder. No compiled installer is included; the C# helpers are compiled by `Add-Type` when the scripts start.

## Quick start / 开始使用

1. Open [Releases](https://github.com/cutebird00/bright-spot-mask/releases) and download `Bright-Spot-Mask-2026.10.07.zip` under **Assets**. Extract it and open the `Bright-Spot-Mask` folder; do not run from inside the ZIP. The repository source is also available via **Code → Download ZIP**, with the app in `bright-spot-mask`.
2. Double-click `start-mask.cmd`. The interface initially uses Simplified Chinese; select **English** beside the master switch if preferred. Click **Monitor / 连接显示器**, choose the display, and select **Use selected display / 绑定所选显示器**. Masks remain hidden until a display is bound.
3. Move Layer 1 over the bright spot with the arrow buttons, then adjust size, color, brightness, and transparency. Enable Layer 2 if needed.

The default Layer 1 uses a black center at 10% opacity, fading to transparent edges. Layer 2 is disabled. A position-button click moves the mask by 5 pixels; holding it accelerates movement.

中文：从 Releases 的 Assets 下载应用 ZIP，完整解压后双击 `start-mask.cmd`，点击右上角“连接显示器”绑定屏幕，再用方向按钮定位亮斑并调节参数。默认第一层为中心 10% 不透明度的黑色渐变，第二层关闭；首次绑定前不显示遮罩。

## Controls / 主要功能

| Control | Behavior |
| --- | --- |
| Master switch / 总开关 | Enables or disables both mask layers together. |
| Layer 1 / Layer 2 | Independently controls each layer's position and appearance. |
| Center / optional middle point / edge | RGB, brightness, and transparency controls for the radial gradient. |
| Diameter | 30–300 physical pixels. |
| Adapt to background / 随背景亮度 | Scales opacity using a local background brightness sample; strongest on white and zero on pure black. |
| Profiles 1 / 2 / 3 | Automatically saves three configurations; display binding and language are shared. |
| Monitor | Remembers per-display positions and hides masks when the bound display disconnects. |
| Hide to tray / 收起到托盘 | Hides the settings window; double-click the tray icon or launch again to reopen. |
| Exit / 退出 | Closes the masks; the separate connection watcher remains running. |
| Language | Simplified Chinese, Traditional Chinese, and English. |

## Automatic startup / 自动启动

**The first launch automatically creates a shortcut in your Windows Startup folder and starts a background display watcher.** After sign-in, it checks every 5 seconds and launches the masks when the bound display becomes connected, including when already connected at sign-in. The settings window stays hidden for automatic launches.

首次启动会自动创建 Windows 启动文件夹快捷方式，并运行后台显示器连接检测。登录后每 5 秒检测一次，绑定屏幕接上时自动启动遮罩。界面中目前没有自动启动开关；删除方法见下方。

Keep the app folder in place. If you move it, launch `start-mask.cmd` from the new location once to update the startup shortcut. Close an older copy and its watcher before switching to this version, because its process identifiers have changed.

The launcher and watcher use `-ExecutionPolicy Bypass` for their PowerShell processes; they do not change the machine's persistent execution-policy setting. Organization policies can still prevent execution.

## Local data / 本地数据

The app saves these files beside the scripts; they are excluded by the repository's `.gitignore`:

| File | Contents |
| --- | --- |
| `mask-settings.json` | Current configuration. |
| `mask-presets.json` | Three profiles and the active profile. |
| `mask-display-binding.json` | Selected display identity and remembered positions. |
| `mask-language.json` | Interface language. |
| `*.json.bak` / `*.json.tmp` | Backup and temporary files used during saving. |

In adaptive mode, the brightness helper samples a 32 × 32 pixel patch in memory. Its source contains no frame-saving or network-transmission code. Display identification uses Windows APIs and locally reads monitor EDID information from the registry. No personal settings are included in this distribution.

## Removal / 删除与禁用自动启动

1. Choose **Exit / 退出** in the app. In Task Manager, identify the PowerShell process whose command line contains this app folder and `watch-display.ps1`, then end that process.
2. Press **Win+R**, enter `shell:startup`, and delete **亮斑遮罩 - 显示器连接自动启动**. To disable startup without deleting the app, stop here; launching the app again will recreate the shortcut and watcher.
3. Delete the extracted app folder to remove the program and local settings.

## Troubleshooting / 常见问题

- **No mask:** bind a connected display, enable the master switch and layer, and check that transparency is below 100%. Masks hide while the bound display is absent.
- **Settings do not save:** use a writable folder and keep the scripts together. A failed save is reported in the interface.
- **Background sampling unavailable:** the app cannot use the required capture exclusion or sampling path in that session; use fixed opacity by disabling adaptive mode.
- **Lock screen or UAC prompt:** ordinary overlay windows cannot cover the Windows lock screen or UAC secure desktop.
- **Fullscreen behavior:** overlay visibility depends on the application and desktop composition; compatibility with every fullscreen mode is not established.

## Source files

| File | Role |
| --- | --- |
| `start-mask.cmd` | Hidden Windows PowerShell launcher. |
| `screen-bright-spot-mask.ps1` | WPF interface, mask layers, profiles, display binding, tray, and startup setup. |
| `watch-display.ps1` | Background display-connection watcher. |
| `screen-mask-monitor.cs` | Display enumeration, binding, and physical-pixel positioning. |
| `screen-mask-topmost.cs` | Overlay stacking helpers. |
| `screen-mask-brightness.cs` | Local background sampling and capture exclusion. |
| `screen-mask-curves.cs` | Gradient construction. |
| `mask-icon.ico` / `mask-icon.png` | App icons. |
| `USER-GUIDE.txt` | Bilingual offline user guide. |

## Validation and license

Publication edits received a static source/reference check in Linux. The Windows PowerShell/WPF app has not been run in this environment; first-run binding, startup, reconnection, and adaptive mode need verification on Windows.

No open-source license has been selected. See the repository's root README.
