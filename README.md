<img src="source/betterbird-blue.svg" alt="Betterbird icon in blue: a light blue to green bird on a dark circle" width="128">

# Betterbird Icons

[![Tests and code check](https://github.com/Kassapa-Bhikkhu/betterbird-icons/actions/workflows/tests.yml/badge.svg)](https://github.com/Kassapa-Bhikkhu/betterbird-icons/actions/workflows/tests.yml)

Change the Betterbird icon on Windows to one of the alternative designs from [Betterbird's expert tips](https://www.betterbird.eu/expert-tips/#custom-icons), or a custom `.ico`. Optionally set a start page, swap the new-mail icon, change the dot colour, or change the mail popup. Betterbird updates leave your icon alone.

Works with:

- Windows 10 or 11, using the built-in Windows PowerShell (PowerShell 7 also works).
- Betterbird installed **for all users (system-wide)** with the official installer, in `C:\Program Files\Betterbird`. Changing its icon needs administrator rights; the start page doesn't, and is only ever changed with your normal rights.
- **Portable Betterbird** (the official zip), or Betterbird installed in your own folder. Nothing needs administrator rights.

The menu's **Manual instructions** show how to make every change by hand instead.

## Status

This tool is experimental. It has been tested along the way, with automated tests in Windows PowerShell 5.1 and PowerShell 7 and on a real Betterbird on one Windows 11 PC, and its code has been audited several times. It still needs more testing, especially on other PCs, other Windows setups and other Betterbird versions. Check Betterbird after each change, and use **Restore original icons** if something isn't right.

## Disclaimer

I wrote this for my own Betterbird on Windows. I use it myself, and I have shared it in case it helps. It is offered as-is under the [disclaimer in CC BY-NC-SA 4.0, section 5](https://creativecommons.org/licenses/by-nc-sa/4.0/legalcode#s5).

## Quick start

1. Download this repository (**Code → Download ZIP**) and unzip it, or `git clone https://github.com/Kassapa-Bhikkhu/betterbird-icons.git`.
2. Close Betterbird.
3. Double-click **`Set-BetterbirdIcon.cmd`** and choose from the menu:

```
  1) Change icon                 (asks for administrator permission)
  2) Start page
  3) Restore original icons      (asks for administrator permission)
  4) Status
  5) Manual instructions (do it by hand)
  6) Change the new-mail icon    (asks for administrator permission)
  7) See the icons
  8) Change the dot colour       (asks for administrator permission)
  9) Change the mail popup       (asks for administrator permission)
  P) Use a portable Betterbird, or one in your own folder
  Q) Quit
```

Option 1 lists the icon sets by number; you can also type a set name or the path to your own `.ico` file. Number 1 is the blue icon (the tool marks it "yours": it is my own colouring). The new-mail icon is updated with that set. Options 6 and 8 work on the icon chosen with option 1, so choose one first. Option 7 opens a table of the pictures in your web browser.

For Betterbird installed for all users, only options 1, 3, 6, 8 and 9 ask for administrator permission, and only when you choose them. For a portable Betterbird, choose **P** and give its folder (the one with `BetterbirdLauncher.exe`); if no system-wide Betterbird is found, the tool asks for the folder straight away.

Then start Betterbird again.

## Icon sets

| Image                                                              | Name         | Design                                     |
|--------------------------------------------------------------------|--------------|--------------------------------------------|
| <img src="source/betterbird-blue.svg" alt="Blue icon">             | `blue`       | light blue to green gradient on a dark circle (shown as "yours") |
| <img src="source/betterbird.svg" alt="BB original">                | `bb`         | orange/red, the standard Betterbird icon   |
| <img src="source/betterbird-green.svg" alt="Green/yellow icon">    | `bb-green`   | green/yellow gradient                      |
| <img src="source/betterbird-green2.svg" alt="Green icon">          | `green2`     | green only                 |
| <img src="source/betterbird-uk.svg" alt="Blue/yellow icon">        | `uk`         | blue/yellow gradient (Ukrainian colours)   |
| <img src="source/betterbird-lightgrey.svg" alt="Grey icon">        | `lightgrey`  | light grey for dark OS mode                |
| <img src="source/newmail-sm.ico" alt="SM new-mail icon">           | `newmail-sm` | SeaMonkey new-mail icon only               |

Every set has a new-mail icon: the same bird with a dot. `newmail-sm` is only a small new-mail picture, for option 6. `-NewMail none` uses Betterbird's own. Betterbird's built-in icon is the orange `bb` design. **Restore original icons** puts back what you had before, including any icon you had customised by hand.

## Command line

All options can be combined. Run `Get-Help .\Set-BetterbirdIcon.ps1 -Full` for details.

```powershell
.\Set-BetterbirdIcon.ps1 -List                         # show the icon sets
.\Set-BetterbirdIcon.ps1 -Icon blue                    # change the icon
.\Set-BetterbirdIcon.ps1 -MailPopup yours              # the blue bird on the large new-mail popup
.\Set-BetterbirdIcon.ps1 -MailPopup factory            # Betterbird's own popup bird
.\Set-BetterbirdIcon.ps1 -Icon C:\Icons\mine.ico       # a custom icon
.\Set-BetterbirdIcon.ps1 -Icon green2 -NewMail none    # keep Betterbird's new-mail icon
.\Set-BetterbirdIcon.ps1 -StartPage C:\Docs\manual.html
.\Set-BetterbirdIcon.ps1 -StartPage Off                # back to the previous start page
.\Set-BetterbirdIcon.ps1 -Restore                      # original icons, remove everything installed
.\Set-BetterbirdIcon.ps1 -Status
.\Set-BetterbirdIcon.ps1 -Manual                       # how to do it all by hand
.\Set-BetterbirdIcon.ps1 -Portable D:\BetterbirdPortable -Icon blue   # a portable Betterbird
```

Add `-Portable <folder>` to any option to work on a portable Betterbird, or one in your own folder. The dot colour is changed from the menu only.

If PowerShell refuses to run the script, use `Set-BetterbirdIcon.cmd` with the same options instead.

## What it changes

### Icons

- Puts `messengerWindow.ico` (main window) and `newmail.ico` (new-mail notification) in `C:\Program Files\Betterbird\chrome\icons\default`. Betterbird doesn't ship these two files (its own icons are built into the program), so it uses them when they're there, and **updates leave them alone**. A small `betterbird-icons.txt` beside them records the hashes so a later run can tell them from icons you put there yourself. Restore removes it.
- Points the Betterbird shortcuts (desktop, Start menu, pinned taskbar) at the same icon, and refreshes the Windows icon cache.
- Keeps any icon files that were already there in `C:\ProgramData\BetterbirdIcons\backup` (a folder only administrators can change), so **Restore** puts back what you had. On a fresh install there are none, so Restore simply removes the tool's icons.
- If Betterbird's folder has gone (uninstalled), or the tool's record of what it changed is missing, Restore never deletes those backed-up icons: it leaves them in the backup folder and tells you where. If the data folder was not made by this tool, it is renamed to `BetterbirdIcons.untrusted-...` and left there. The tool will not look in the renamed folder again. Copy the icons out by hand if you still need them.
- The compose window and calendar dialog icons in the same folder are part of Betterbird and are replaced by every install; this tool doesn't change them.

### Dot colour

- **Change the dot colour** makes a new-mail icon from your current icon with a coloured dot (Amber, Gold, White, Pink, Purple, Red or Grey), and puts it in place as `newmail.ico`. Choose an icon with option 1 first.
- Choosing an icon set again (option 1) brings back that set's own new-mail icon.

### Mail popup

- The large popup for a new message uses two pictures inside `omni.ja` (`icon64.png` and `icon128.png`), not the icon files above.
- **Change the mail popup**, or `-MailPopup yours`, replaces them with the light blue to green bird. **factory** (`-MailPopup factory`) puts Betterbird's own bird back.
- Betterbird must be closed completely first, including its tray icon, because it keeps `omni.ja` open while it runs; the tool says so if it isn't. Open Betterbird again to see the new popup.
- A Betterbird update replaces `omni.ja` and brings the original bird back, so run it again after an update. Restore original icons does not change this popup.

### Start page

- Changes two settings in `prefs.js` in each profile Betterbird has used: `mailnews.start_page.url` (your page) and `mailnews.start_page.enabled`. Betterbird keeps its profiles in the same folder as Thunderbird, so the tool checks which program last used each profile, and never changes profiles Thunderbird used last or ones that were never opened.
- Just before each change, a copy of `prefs.js` is saved as `prefs.js.betterbird-icons.bak` (replacing the copy from the change before).
- **Turn it on** and **Turn it off** only show or hide that page. The address stays, so turning it on again uses the same one. **Status** says whether it's on or off.
- The start page you had before is remembered (in `betterbird-icons-startpage.txt` in the profile). It comes back from **Start page**, then **Put the previous page back**, or with `-StartPage Off`. That choice appears only after this tool has changed the start page.
- The setting isn't locked: you can still change the start page in Betterbird's own settings at any time. Running the tool again replaces what's set there. If a `user.js` in the profile sets the start page, it wins over both, and the tool tells you.
- Only ever done with your normal rights, never as administrator: profiles are your own files. Run as administrator, the tool refuses and asks you to use a normal window.
- Betterbird must be closed while this runs, because it saves its settings when it exits. The tool offers to close it, and never closes it without asking, unless you add `-Force`.
- The page is used where it is, so keep the HTML file where you chose it. **Status** warns if the file has been moved or deleted. [examples/start-page.html](examples/start-page.html) is a starting point.

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
