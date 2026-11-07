<img src="source/betterbird-blue.svg" alt="Betterbird icon in blue: a light blue to green bird on a dark circle" width="128">

# Betterbird Icons

[![Tests and code check](https://github.com/Kassapa-Bhikkhu/betterbird-icons/actions/workflows/tests.yml/badge.svg)](https://github.com/Kassapa-Bhikkhu/betterbird-icons/actions/workflows/tests.yml)

Change the Betterbird icon on Windows to one of the alternative designs from [Betterbird's expert tips](https://www.betterbird.eu/expert-tips/#custom-icons), or a custom `.ico`. You can also change the system tray icon and its dot colour, change the "new mail" popup, and set a start page. Betterbird updates leave your icon alone.

Works with:

- Windows 10 or 11, using the built-in Windows PowerShell (PowerShell 7 also works).
- Betterbird installed **for all users (system-wide)** with the official installer, in `C:\Program Files\Betterbird`. Changing its icon needs administrator rights; the start page doesn't, and is only ever changed with your normal rights.
- **Portable Betterbird** (the official zip), or Betterbird installed in your own folder. Nothing needs administrator rights.

The menu's **Manual instructions** show how to make every change by hand instead.

## Status

This tool is experimental as in it is free and just for myself. It has been tested along the way, by myself and with automated tests in Windows PowerShell 5.1 and PowerShell 7 and on a real Betterbird on one Windows 11 PC, and its code has been audited several times - I have included one test folder. It still needs more testing, especially on other PCs, other Windows setups and other Betterbird versions. Check Betterbird after each change, and use **Revert to Betterbird defaults** (R) if something isn't right or to revert.

## Disclaimer

I wrote this for my own Betterbird on Windows. I use it myself, and I have shared it in case it helps. It is offered as-is under the [disclaimer in CC BY-NC-SA 4.0, section 5](https://creativecommons.org/licenses/by-nc-sa/4.0/legalcode#s5).

## Quick start

1. Download this repository (**Code → Download ZIP**) and unzip it, or `git clone https://github.com/Kassapa-Bhikkhu/betterbird-icons.git`.
2. Double-click **`Set-BetterbirdIcon.cmd`** and choose from the menu:

```
  1) Change all at once (2, 3 and 5)              (asks for administrator permission)
  2) Change the standard icon (Windows app icon)  (asks for administrator permission)
  3) Change the system tray icon                  (asks for administrator permission)
  4) Change the system tray dot colour            (asks for administrator permission)
  5) Change the "new mail" popup icon             (asks for administrator permission)
  6) Show the icons for selection
  7) Show manual instructions
  8) Change the start page
  9) Show the current setup
  D) Debug issues: close Betterbird and restart Windows Explorer
  R) Revert to Betterbird defaults                (asks for administrator permission)
  S) Select a different Betterbird folder (such as a portable one)
  Q) Quit
```

What each one does:

1. **Change all at once** changes the standard icon, the system tray icon and the "new mail" popup to one set, with a single administrator prompt. Pick a set by number, or type the path to your own `.ico` file. Number 1 is the blue icon.
2. **Change the standard icon** changes the Windows app icon (window, desktop, Start menu and taskbar shortcuts) and leaves the system tray icon as it is.
3. **Change the system tray icon** changes only the new-mail icon in the system tray, or puts Betterbird's own back (`none`). You don't need to choose a standard icon first.
4. **Change the system tray dot colour** draws a dot of the colour you choose on the standard icon (or on Betterbird's own design, if you haven't changed it) and uses that as the system tray icon. You don't need to choose a standard icon first.
5. **Change the "new mail" popup icon** offers every set, plus Betterbird's own. Only blue has a ready-made popup picture; for the others the tool draws one from the set's icon.
6. **Show the icons for selection** opens a table of every set in your web browser, with the numbers the menu uses for the standard icon, the system tray icon and the popup.
7. **Show manual instructions** shows how to make every change by hand.
8. **Change the start page** sets, turns on, turns off or puts back Betterbird's start page.
9. **Show the current setup** shows the standard icon, system tray icon, popup, shortcuts and start page that are in place.
D. **Debug issues** is for troubleshooting, separate from the icon changes. It asks `Go ahead? (Y/N)`, then closes Betterbird (if it is open) and restarts Windows Explorer (`explorer.exe`; open File Explorer windows close). It doesn't start Betterbird again. It only runs with your normal rights, never as administrator.
R. **Revert to Betterbird defaults** goes back to Betterbird's own icons, popup and start page (see [Revert to Betterbird defaults](#revert-to-betterbird-defaults)).
S. **Select a different Betterbird folder** is for a portable Betterbird or one in your own folder. Give its folder (the one with `BetterbirdLauncher.exe`); if no system-wide Betterbird is found, the tool asks for the folder straight away.

For Betterbird installed for all users, only the items marked above ask for administrator permission, and only when you choose them.

Before 1 and 2, if Betterbird is open, the menu asks, before any administrator prompt:

```
  Betterbird is open. Its window, taskbar button and system tray icon keep the old picture until it restarts.
  Close Betterbird now and start it again when the change is done? (Y/N)
```

- **Y** closes Betterbird in your own window the normal way. A Betterbird minimised to the system tray may not close that way: the tool then asks `Betterbird did not close. Force it closed? Anything unsaved, such as a message being written, will be lost. (Y/N)`, and only stops it on **Y**. When the change is done, Betterbird is started again from your own window (never from the administrator window): the portable launcher if there is one, otherwise `betterbird.exe`.
- **N** carries on with 2 and tells you to restart Betterbird to see the new window, taskbar and system tray icon. 1 also changes the popup, which can't be changed while Betterbird holds `omni.ja` open, so **N** stops 1 before anything changes.
- 3 and 4 don't ask: restart Betterbird afterwards to see the new tray icon. 5 stops with a message if Betterbird is open. R asks to close Betterbird itself.
- If Betterbird isn't open, nothing is asked. Only the Betterbird you're changing counts: a portable one and an installed one are separate.

## Icon sets

| Image                                                                                     | Name         | Design                                     |
|-------------------------------------------------------------------------------------------|--------------|--------------------------------------------|
| <img width="32" height="32" src="source/betterbird-blue.svg" alt="Blue icon">             | `blue`       | light blue to green gradient on a dark circle |
| <img width="32" height="32" src="source/betterbird.svg" alt="BB original">                | `bb`         | orange/red, the standard Betterbird icon   |
| <img width="32" height="32" src="source/betterbird-green.svg" alt="Green/yellow icon">    | `bb-green`   | green/yellow gradient                      |
| <img width="32" height="32" src="source/betterbird-green2.svg" alt="Green icon">          | `green2`     | green only                                 |
| <img width="32" height="32" src="source/betterbird-uk.svg" alt="Blue/yellow icon">        | `uk`         | blue/yellow gradient (Ukrainian colours)   |
| <img width="32" height="32" src="source/betterbird-lightgrey-readme.svg" alt="Grey icon"> | `lightgrey`  | light grey for dark OS mode                |
| <img src="source/newmail-sm.ico" alt="SM new-mail icon">                                  | `newmail-sm` | SeaMonkey new-mail icon only               |

Every set has a new-mail icon: the same bird with a dot. `newmail-sm` is only a small new-mail picture, for option 3. `-NewMail none` uses Betterbird's own. Betterbird's built-in icon is the orange `bb` design. **Revert to Betterbird defaults** goes back to Betterbird's own icons (see below). To put back what you had before this tool, including any icon you had customised by hand, use `-Restore` on the command line.

## Command line

All options can be combined. Run `Get-Help .\Set-BetterbirdIcon.ps1 -Full` for details.

```powershell
.\Set-BetterbirdIcon.ps1 -List                         # show the icon sets
.\Set-BetterbirdIcon.ps1 -Icon blue                    # change the icon
.\Set-BetterbirdIcon.ps1 -Icon green2 -MailPopup green2   # all at once: icon, tray icon and popup
.\Set-BetterbirdIcon.ps1 -Icon uk -NewMail keep        # only the standard icon, the tray icon stays
.\Set-BetterbirdIcon.ps1 -NewMail green2               # only the tray icon
.\Set-BetterbirdIcon.ps1 -NewMail none                 # Betterbird's own tray icon
.\Set-BetterbirdIcon.ps1 -MailPopup uk                 # the uk bird on the large new-mail popup
.\Set-BetterbirdIcon.ps1 -MailPopup factory            # Betterbird's own popup bird
.\Set-BetterbirdIcon.ps1 -Icon C:\Icons\mine.ico       # a custom icon
.\Set-BetterbirdIcon.ps1 -Icon green2 -NewMail none    # keep Betterbird's new-mail icon
.\Set-BetterbirdIcon.ps1 -Icon blue -RestartBetterbird # close Betterbird first, start it again afterwards
.\Set-BetterbirdIcon.ps1 -Icon blue -RestartExplorer   # and restart Explorer, if a shortcut still shows the old icon
.\Set-BetterbirdIcon.ps1 -StartPage C:\Docs\manual.html
.\Set-BetterbirdIcon.ps1 -StartPage Off                # back to the previous start page
.\Set-BetterbirdIcon.ps1 -Restore                      # the icons you had before, remove everything installed
.\Set-BetterbirdIcon.ps1 -FactoryReset                 # Betterbird's own icons, popup and start page (menu R)
.\Set-BetterbirdIcon.ps1 -Status
.\Set-BetterbirdIcon.ps1 -Manual                       # how to do it all by hand
.\Set-BetterbirdIcon.ps1 -Portable D:\BetterbirdPortable -Icon blue   # a portable Betterbird
```

Add `-Portable <folder>` to any option to work on a portable Betterbird, or one in your own folder. The dot colour is changed from the menu only. `-NewMail` and `-MailPopup` also take the path to an `.ico` file.

If PowerShell refuses to run the script, use `Set-BetterbirdIcon.cmd` with the same options instead.

## What it changes

### Icons

- Puts `messengerWindow.ico` (main window) and `newmail.ico` (new-mail notification) in `C:\Program Files\Betterbird\chrome\icons\default`. Betterbird doesn't ship these two files (its own icons are built into the program), so it uses them when they're there, and **updates leave them alone**. A small `betterbird-icons.txt` beside them records the hashes so a later run can tell them from icons you put there yourself. Restore removes it.
- Points the Betterbird shortcuts (desktop, Start menu, pinned taskbar) at a copy of the same icon, named `shortcut-<letters and numbers>.ico` after its contents, in the data folder, and refreshes the Windows icon cache. The name changes whenever the picture does, because Windows keeps showing the old picture for a file name it has already seen. Older copies are deleted once every shortcut has moved to the new one. Every icon file the tool installs gets the current time as its file time, for the same reason.
- Changing only the system tray icon leaves the standard icon and the shortcuts alone; changing only the standard icon leaves the system tray icon alone.
- Keeps any icon files that were already there in `C:\ProgramData\BetterbirdIcons\backup` (a folder only administrators can change), so **Restore** puts back what you had. On a fresh install there are none, so Restore simply removes the tool's icons.
- If you change an icon file by hand after this tool has changed it, Restore leaves yours in place and keeps the older backup.
- If the tool's record of what it changed is missing, Restore uses the hashes in `betterbird-icons.txt` to find its own icons. For Betterbird installed in your own folder (not portable), which shares its data folder with any other such install, it keeps the backup instead.
- If Betterbird's folder has gone (uninstalled), Restore never deletes those backed-up icons: it leaves them in the backup folder and tells you where. If the data folder was not made by this tool, it is renamed to `BetterbirdIcons.untrusted-...` and left there. The tool will not look in the renamed folder again. Copy the icons out by hand if you still need them.
- The compose window and calendar dialog icons in the same folder are part of Betterbird and are replaced by every install; this tool doesn't change them.

### Icons still look old

- Betterbird reads its window icon, taskbar button, system tray icon and popup when it starts, so a Betterbird that is already open keeps the old ones until it restarts. That is why the menu offers to close it before a change and start it again (see above). Quitting it completely, including the tray icon, and opening it again does the same by hand.
- On the command line, `-RestartBetterbird` closes Betterbird before the change (it asks, or closes it at once with `-Force`; in a script without `-Force` it refuses) and starts it again afterwards, even if the change failed. On its own it just restarts Betterbird. Without it, the tool leaves Betterbird as it is and prints `Restart Betterbird to see the new window, taskbar and tray icon.` when it is open. `-FactoryReset` still closes Betterbird as before, and `-RestartBetterbird` starts it again afterwards.
- The desktop, Start menu and taskbar shortcuts update by themselves, because each icon change gives them a new icon file name (above): Windows keeps showing the old picture for a file name it has already seen. If one still shows the old icon, restart Explorer: **T** in the menu does that (and restarts Betterbird), or add `-RestartExplorer` on the command line. Open File Explorer windows close.
- Explorer and Betterbird are only ever restarted with your normal rights, from the normal window, never from the administrator window: one started as administrator would keep running as administrator. If you started the tool as administrator, it doesn't restart them and tells you.
- Explorer: it stops the Explorer processes of your Windows session only, waits for Windows to start Explorer again, and starts `explorer.exe` from the Windows folder if that hasn't happened after a few seconds.

### Dot colour

- **Change the system tray dot colour** (4) makes a new-mail icon from the standard icon with a coloured dot (Amber, Gold, White, Pink, Purple, Red or Grey), and puts it in place as `newmail.ico`. The picture is drawn on the standard icon this tool installed; if it didn't install one, on Betterbird's own design. You don't need to change the standard icon first. The picture is made in your temp folder and deleted once it is in place.
- Choosing an icon set again (option 1) brings back that set's own new-mail icon. Option 2 leaves the dot as it is.

### Mail popup

- The large popup for a new message uses two pictures inside `omni.ja` (`icon64.png` and `icon128.png`), not the icon files above.
- **Change the "new mail" popup icon** (5), or `-MailPopup <set>`, replaces them with the bird of any icon set. Blue has a ready-made picture (`-MailPopup yours` is another name for blue); for the other sets the tool draws the two pictures (64 and 128 pixels, transparent background) from the largest picture in the set's `messengerWindow.ico`. The first time, it keeps Betterbird's own two pictures inside `omni.ja` as well. **Betterbird's own** (`-MailPopup factory`) puts exactly those back, so it always matches your Betterbird version. Option 1 changes the popup along with the icon.
- It also leaves a small `betterbird-icons-popup.txt` inside `omni.ja`, saying which set the popup shows, so **Show the current setup** can tell you. It goes when Betterbird's own is put back.
- Betterbird must be closed completely first, including its tray icon, because it keeps `omni.ja` open while it runs. The menu offers to close it (and start it again afterwards); if you say no, the change stops before anything is touched. Open Betterbird again to see the new popup.
- A Betterbird update replaces `omni.ja` and brings the original bird back, so run it again after an update. `-Restore` does not change this popup; Revert to Betterbird defaults does.
- Windows notifications (if you turn them on in Betterbird's settings) and calendar alarms use a different picture, `icon48.png`, which this tool doesn't change.

### Start page

- Changes two settings in `prefs.js` in each profile Betterbird has used: `mailnews.start_page.url` (your page) and `mailnews.start_page.enabled`. Betterbird keeps its profiles in the same folder as Thunderbird, so the tool checks which program last used each profile, and never changes profiles Thunderbird used last or ones that were never opened.
- Just before each change, a copy of `prefs.js` is saved as `prefs.js.betterbird-icons.bak` (replacing the copy from the change before).
- **Turn it on** and **Turn it off** only show or hide that page. The address stays, so turning it on again uses the same one. **Status** says whether it's on or off.
- The start page you had before is remembered (in `betterbird-icons-startpage.txt` in the profile). It comes back from **Start page**, then **Put the previous page back**, or with `-StartPage Off`. That choice appears only after this tool has changed the start page.
- The setting isn't locked: you can still change the start page in Betterbird's own settings at any time. Running the tool again replaces what's set there. If a `user.js` in the profile sets the start page, it wins over both, and the tool tells you.
- Only ever done with your normal rights, never as administrator: profiles are your own files. Run as administrator, the tool refuses and asks you to use a normal window.
- Betterbird must be closed while this runs, because it saves its settings when it exits. The tool offers to close it, and never closes it without asking, unless you add `-Force`.
- The page is used where it is, so keep the HTML file where you chose it. **Status** warns if the file has been moved or deleted. [examples/start-page.html](examples/start-page.html) is a starting point.

### Revert to Betterbird defaults

- **Revert to Betterbird defaults** (menu R, or `-FactoryReset`) puts Betterbird back to its own pictures, whatever put the changes there:
  - removes `messengerWindow.ico` and `newmail.ico` from Betterbird's icon folder, including ones you put there yourself. A copy of any icon this tool didn't make, and of its backups, is kept in a `saved-<date>` folder in the data folder, and the tool tells you where;
  - gives every Betterbird shortcut it finds Betterbird's own icon;
  - puts Betterbird's own mail popup back;
  - puts back the start page you had before this tool changed it. A start page you set yourself stays;
  - removes this tool's backups and records.
- Betterbird must be closed; the tool offers to close it, and starts it again afterwards if you used the menu.
- To go back to the icons you had before this tool, rather than to Betterbird's own, use `-Restore` on the command line.

### Portable Betterbird, or Betterbird in your own folder

- The icons go in `core\chrome\icons\default` in the portable folder (or `chrome\icons\default` in your own install folder), and shortcuts to `BetterbirdLauncher.exe` are updated too.
- For a portable Betterbird, the backups and the tool's record are kept in a `BetterbirdIcons` folder inside the portable folder, so they travel with it. For one installed in your own folder, they're kept in `%LOCALAPPDATA%\BetterbirdIcons`. That folder is shared, so if you have more than one Betterbird installed in your own folders, only one of them can have a changed icon at a time: Restore it before changing another.
- The start page is changed in the portable profile (`profile`, or wherever the launcher has moved it). Start the portable Betterbird once first, so the profile exists.
- Nothing needs administrator rights. If you start the tool as administrator anyway, it offers to start again as a standard user (recommended) or to continue as administrator (the start page is then left alone).
- Only the Betterbird you're changing has to be closed; a separately installed Betterbird can stay open.

## Extra tools

Two Python scripts in `tools/` for making your own icons. Install what they need once:

```
pip install resvg-py pillow potracer numpy opencv-python
```

**Make an icon from an SVG:** `svg_to_ico.py` turns a square SVG into a Windows `.ico` with every size Windows uses (16 to 256 px), each rendered fresh from the SVG so small sizes stay sharp. Use the result with `-Icon`:

```
python tools/svg_to_ico.py my-logo.svg my-logo.ico
.\Set-BetterbirdIcon.ps1 -Icon my-logo.ico
```

**Redraw a logo picture as a clean SVG:** `trace_logo.py` takes a PNG of a logo built like Betterbird's (one light shape on a dark circle, each filled with a top-to-bottom colour gradient, on a transparent background) and redraws it as a vector: a true circle, smooth curves for the shape with sharp tips kept, and gradients sampled from the picture. It writes `<name>.svg` and a clean `<name>-clean.png`. This is how `source/betterbird-blue.svg` was made from a PNG with jagged, grey-fringed edges. Logos built differently (several colours, no circle) need a different approach, so check the result.

```
python tools/trace_logo.py Better-Bird-Logo-Blue.png out
python tools/svg_to_ico.py out/Better-Bird-Logo-Blue.svg my-icon.ico
```

## Development

The tests use [Pester](https://pester.dev/) and run against a fake Betterbird install, fake profiles and fake shortcuts, so they never touch your real Betterbird. The code is checked with [PSScriptAnalyzer](https://github.com/PowerShell/PSScriptAnalyzer). On every push the tests run in both Windows PowerShell 5.1 and PowerShell 7, and the code check in PowerShell 7 (see [.github/workflows/tests.yml](.github/workflows/tests.yml)).

```powershell
Install-Module Pester, PSScriptAnalyzer -Scope CurrentUser -SkipPublisherCheck
Invoke-Pester -Path tests
Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
```

The `.ico` files in `icons/` are built from the designs in `source/` with `svg_to_ico.py`; the ready-made `.ico` files from betterbird.eu are copied unchanged. The same command writes the mail-popup pictures in `icons/popup/`.

```
pip install resvg-py pillow
python tools/build-icons.py
```

## License

The icon designs in `source/` and `icons/` are © [Betterbird Project](https://www.betterbird.eu/), from the [custom icons](https://www.betterbird.eu/expert-tips/#custom-icons) section of their expert tips. The blue colouring is by Kassapa Bhikkhu. The factory mail-popup pictures are Betterbird's own logo, included so that popup can be put back. They are included here for convenience and are not covered by the license below.

The scripts and documentation are released under the **CC BY-NC-SA 4.0** license:

<a rel="license" href="https://creativecommons.org/licenses/by-nc-sa/4.0/"><img alt="Creative Commons License" style="border-width:0" src="https://i.creativecommons.org/l/by-nc-sa/4.0/88x31.png" /></a>

Using these scripts and documents as they are follows that license.

The author also allows this script to be used by anyone, including charities, study, research, non-commercial use, and commercial use. It must not be sold, redistributed for a fee, or relicensed under a paid model. It may be included, free, with this original license. No further permission is required. This licence does not cover the icon designs.
