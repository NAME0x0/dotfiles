# dotfiles

A tiling Windows 11 desktop: **komorebi** for window management, **YASB** for the status bar,
**Rainmeter** for desktop widgets, **Windhawk** for shell patches.

Design language is Off-White × Space Grey × NASA Orange — labels in `"QUOTATION MARKS"`, industrial
spacing, one accent colour (`#FC3D21`) carried across every surface.

> Everything here installs with one command and configures itself with a wizard.
> Jump to [Quick setup](#quick-setup).

---

## Quick setup

Open PowerShell and run:

```powershell
irm https://raw.githubusercontent.com/NAME0x0/dotfiles/main/install.ps1 | iex
```

That single command will:

1. Ask where you want the repo (default `%USERPROFILE%\dotfiles`) and clone it
2. Install every package below with `winget`
3. Deploy each config to the location its app expects, backing up anything already there
4. Import the Windhawk mod list and settings
5. Register the autostart task
6. Launch the **setup wizard**, which sizes gaps, borders, bar height, fonts and rescales the
   Rainmeter widget positions to your resolution

Prefer to read before you run? Clone first:

```powershell
git clone https://github.com/NAME0x0/dotfiles.git "$env:USERPROFILE\dotfiles"
cd "$env:USERPROFILE\dotfiles"
.\install.ps1
```

### Installer options

| Flag | Effect |
|---|---|
| `-InstallRoot <path>` | Where to keep the repo |
| `-Components komorebi,yasb,…` | Install a subset only |
| `-SkipPackages` | Deploy configs without touching winget |
| `-SkipWizard` | Do not run the wizard afterwards |
| `-NonInteractive` | Take every default, never prompt |

```powershell
# just the window manager, configs only
.\install.ps1 -Components komorebi -SkipPackages

# re-run the wizard on its own, any time
.\setup-wizard.ps1
```

Every replaced file becomes `<name>.bak-<timestamp>` next to the original. Nothing is deleted.

---

## What's installed

| Component | What it does | Project | winget id |
|---|---|---|---|
| komorebi | Tiling window manager | [LGUG2Z/komorebi](https://github.com/LGUG2Z/komorebi) · [docs](https://lgug2z.github.io/komorebi/) | `LGUG2Z.komorebi` |
| whkd | Hotkey daemon driving komorebi | [LGUG2Z/whkd](https://github.com/LGUG2Z/whkd) | `LGUG2Z.whkd` |
| YASB | Status bar | [amnweb/yasb](https://github.com/amnweb/yasb) | `AmN.yasb` |
| AutoHotkey v2 | Alt+Wheel focus scrolling, German accent holds | [autohotkey.com](https://www.autohotkey.com/) | `AutoHotkey.AutoHotkey` |
| Rainmeter | Desktop widgets | [rainmeter.net](https://www.rainmeter.net/) | `Rainmeter.Rainmeter` |
| Windhawk | Shell/taskbar patches | [windhawk.net](https://windhawk.net/) | `RamenSoftware.Windhawk` |
| Flow Launcher | Application launcher | [flowlauncher.com](https://www.flowlauncher.com/) | `Flow-Launcher.Flow-Launcher` |
| Windows Terminal | Terminal | [microsoft/terminal](https://github.com/microsoft/terminal) | `Microsoft.WindowsTerminal` |
| JetBrainsMono NF | Bar and terminal font | [nerdfonts.com](https://www.nerdfonts.com/) | `DEVCOM.JetBrainsMonoNerdFont` |

### Where each config lands

| Repo path | Installed to |
|---|---|
| `config/komorebi/komorebi.json` | `%USERPROFILE%\komorebi.json` |
| `config/whkd/whkdrc` | `%USERPROFILE%\.config\whkdrc` |
| `config/yasb/` | `%USERPROFILE%\.config\yasb\` |
| `config/autohotkey/scroll_focus.ahk` | `%USERPROFILE%\.config\komorebi\` |
| `config/autostart/` | `%USERPROFILE%\.config\autostart\` |
| `config/rainmeter/skins/` | `Documents\Rainmeter\Skins\` |
| `config/rainmeter/Rainmeter.ini` | `%APPDATA%\Rainmeter\Rainmeter.ini` |
| `config/windhawk/enabled-mods.json` | `HKLM\SOFTWARE\Windhawk\Engine\Mods\*` |
| `config/terminal/settings.json` | Windows Terminal `LocalState\` |
| `config/powershell/` | `Documents\WindowsPowerShell\` |
| `config/flowlauncher/` | `%APPDATA%\FlowLauncher\Settings\` |

---

## Keybindings

Driven by [`config/whkd/whkdrc`](config/whkd/whkdrc).

| Keys | Action |
|---|---|
| <kbd>Alt</kbd> + <kbd>H/J/K/L</kbd> | Move focus left/down/up/right |
| <kbd>Alt</kbd> + <kbd>Shift</kbd> + <kbd>H/J/K/L</kbd> | Move the focused window |
| <kbd>Alt</kbd> + <kbd>,</kbd> / <kbd>.</kbd> | Cycle focus previous/next |
| <kbd>Alt</kbd> + <kbd>+</kbd> / <kbd>-</kbd> | Resize horizontally |
| <kbd>Alt</kbd> + <kbd>Shift</kbd> + <kbd>+</kbd> / <kbd>-</kbd> | Resize vertically |
| <kbd>Alt</kbd> + <kbd>B</kbd> / <kbd>N</kbd> | Switch to bsp / scrolling layout |
| <kbd>Alt</kbd> + <kbd>Wheel</kbd> | Scroll focus across columns (AutoHotkey) |
| <kbd>Alt</kbd> + <kbd>Shift</kbd> + <kbd>Wheel</kbd> | Move window across columns |
| <kbd>Ctrl</kbd> + <kbd>Alt</kbd> + <kbd>U</kbd> | Toggle German accent holds (hold A/O/U/S) |

---

## Autostart

The stack does **not** use the Startup folder. Explorer runs Startup items serially with a ~30s
timeout each, and if it crashes partway through — which it does — everything behind the crash point
silently never launches.

Instead, a scheduled task named **Desktop WM Autostart** runs
[`start-desktop.ps1`](config/autostart/start-desktop.ps1) on two triggers:

| Trigger | Delay |
|---|---|
| At logon | 30s |
| Winlogon event 1002 (Explorer crashed and restarted) | 20s |

The script is idempotent — it starts only what is not already running, so repeated triggers cannot
produce duplicates. Measured recovery from a killed shell with everything down: **32 seconds,
unattended**.

```powershell
# what should be running
Get-Process komorebi,whkd,yasb,AutoHotkey64,Rainmeter

# autostart history
Get-Content "$env:LOCALAPPDATA\komorebi\autostart.log" -Tail 20

# force a run (safe, idempotent)
schtasks /run /tn "Desktop WM Autostart"
```

---

## Windhawk mods

Only mods that are **enabled** ship here. Settings for each are exported to
[`config/windhawk/enabled-mods.json`](config/windhawk/enabled-mods.json) and written back to the
registry by the installer.

`alt-tab-per-monitor` · `explorer-details-better-file-sizes` · `island-media-controls` ·
`lock-keys-notifier` · `slick-window-arrangement` · `taskbar-dock-animation` ·
`taskbar-show-desktop-button-aero-peek` · `taskbar-tray-system-icon-tweaks` ·
`windows-11-notification-center-styler` · `windows-11-start-menu-styler` ·
`windows-11-taskbar-styler`

Windhawk mods are not on winget. The installer writes settings for mods you have already added
through the Windhawk UI, and tells you which ones are missing. Browse them at
[windhawk.net/mods](https://windhawk.net/mods).

This step writes to `HKLM` and therefore needs an elevated shell:

```powershell
# from an admin PowerShell
.\install.ps1 -Components windhawk -SkipPackages
```

---

## Wallpaper gallery

The Rainmeter slideshow widget cycles these. Full set in **[docs/gallery.md](docs/gallery.md)**.

<p align="center">
  <img src="config/rainmeter/skins/BigSur/%40Resources/Graphics/Slideshow/Sample/Off-White_Digital_Art.jpg" width="32%" alt="Off-White digital art" />
  <img src="config/rainmeter/skins/BigSur/%40Resources/Graphics/Slideshow/Sample/Kanagawa_Great_Wave_Off.jpg" width="32%" alt="The Great Wave off Kanagawa" />
  <img src="config/rainmeter/skins/BigSur/%40Resources/Graphics/Slideshow/Sample/Starry_Night_Van_Gogh.jpg" width="32%" alt="The Starry Night" />
</p>

To point the widget at your own folder, edit `PicturesFolder` in
`Documents\Rainmeter\Skins\BigSur\Widgets\Slideshow\UserVariables.inc` and refresh the skin.

---

## Weather API keys

The weather skins need your own API key — the ones here are placeholders, deliberately.

| Skin | File (after install) | Placeholder | Get a key |
|---|---|---|---|
| Monterey | `Rainmeter\Skins\Monterey\@Resources\Variables\Weather.inc` | `YOUR_OPENWEATHERMAP_API_KEY` | [openweathermap.org/api](https://openweathermap.org/api) (free tier) |
| BigSur | `Rainmeter\Skins\BigSur\Widgets\Weather\UserVariables.inc` | `YOUR_WEATHERCOM_API_KEY` | See the skin's own docs |

Set `City`, `Latitude` and `Longitude` in the same files — they default to London. Refresh the skin
afterwards (right-click → Refresh skin).

---

## Not included

- **`notes.txt`** — the Rainmeter Notes widget reads `%USERPROFILE%\notes.txt`. The widget ships;
  its contents do not. Create your own.
- **API keys and location** — weather keys are placeholders and coordinates default to London.
- **Flow Launcher history** — `History.json` and usage records are personal, excluded.
- **Inactive Rainmeter suites** — only the suites actually enabled are here.
- **komorebi `applications.json`** — upstream data, fetched fresh by `komorebic fetch-asc`.

---

## Customising

Re-run the wizard whenever you want to change sizing:

```powershell
.\setup-wizard.ps1
```

It asks for gaps, border width, accent colour, bar height, font size and family, then rescales
Rainmeter positions from the `1920x1200` baseline to your display. It edits the deployed configs in
your profile, not the repo, so your answers survive a `git pull` + re-install.

Manual knobs:

| Want to change | Edit |
|---|---|
| Keybindings | `%USERPROFILE%\.config\whkdrc` |
| Bar widgets | `%USERPROFILE%\.config\yasb\config.yaml` |
| Bar styling | `%USERPROFILE%\.config\yasb\styles.css` (CSS variables at the top) |
| Gaps, borders, animation | `%USERPROFILE%\komorebi.json` |

After editing komorebi or whkd config:

```powershell
komorebic check                 # validate
schtasks /run /tn "Desktop WM Autostart"
```

---

## Troubleshooting

**Workspace pills missing from the bar.** komorebi is usually fine — YASB is holding a dead pipe
handle. `yasbc reload`. whkd is unrelated; it only handles hotkeys.

**Nothing started after a reboot.** Check `Get-Content "$env:LOCALAPPDATA\komorebi\autostart.log" -Tail 20`.
If it is empty, the task did not fire: `Get-ScheduledTaskInfo -TaskName "Desktop WM Autostart"`.

**komorebi will not start.** `komorebic check` validates config and reports where it is looking.
Its own log is at `%LOCALAPPDATA%\Temp\komorebi_plaintext.log.<date>` — note the timestamps are UTC.

**Hotkeys dead.** Confirm `whkd` is running and that `%USERPROFILE%\.config\whkdrc` exists — whkd
reads that path and no other.

**Windhawk mods did nothing.** Settings only apply to mods already added in the Windhawk UI, and
the shell needs restarting afterwards.

---

## Credits

Rainmeter skins and Windhawk mods are third-party work redistributed here for reproducibility.
Authors and licences are listed in **[ATTRIBUTION.md](ATTRIBUTION.md)**.

The scripts and configuration in this repo are MIT — see [LICENSE](LICENSE). That covers *my* work
only, not the bundled third-party skins or the wallpapers, which keep their own terms.
