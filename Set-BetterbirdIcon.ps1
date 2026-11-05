<#
.SYNOPSIS
    Change the Betterbird icon on Windows and set a custom start page.

.DESCRIPTION
    Puts the icon files Betterbird looks for in <install dir>\chrome\icons\default
    (messengerWindow.ico for the main window, newmail.ico for the new-mail notification),
    points the Betterbird shortcuts at the same icon, and refreshes the Windows icon cache.

    Betterbird doesn't ship these two files - its own icons are built into the program - so
    Betterbird updates leave them alone and your icon stays.

    Anything that was there before is backed up to %ProgramData%\BetterbirdIcons\backup,
    so -Restore can always put it back.

    The large new-mail popup is a different picture, stored inside the program.
    -MailPopup yours changes it. -MailPopup factory puts Betterbird's own bird back.
    Quit Betterbird and open it again to see it. A Betterbird update puts that original bird back.

    Run with no options for a simple menu. Options can be combined; they run in the order
    Restore, Icon, MailPopup, StartPage.

    Works with Betterbird installed for all users (system-wide) in Program Files, which needs
    administrator rights, and with a portable Betterbird or one installed in your own folder
    (-Portable), which doesn't. -Manual shows how to make the same changes by hand.

.PARAMETER Icon
    An icon set name (see -List) or the path to your own .ico file.

.PARAMETER NewMail
    The new-mail notification icon: a set name, the path to an .ico file, or "none" for
    Betterbird's built-in one. Defaults to the chosen set's own new-mail icon; with a set that has
    none, the new-mail icon you had before stays.

.PARAMETER MailPopup
    The picture on the large new-mail popup: "yours" or "factory".
    "factory" puts Betterbird's own bird back.

.PARAMETER StartPage
    The path to an .html file (or an http/https address) to show as Betterbird's start page,
    or "Off" to go back to the previous start page. Only profiles Betterbird has used are changed.
    This is done with your normal rights, never as administrator.

.PARAMETER Restore
    Put the original icons and shortcuts back and remove everything this script installed.
    (The start page is separate: use -StartPage Off.)

.PARAMETER Portable
    The folder of a portable Betterbird (the one holding BetterbirdLauncher.exe), or of a
    Betterbird installed in your own folder. Then nothing needs administrator rights.

.PARAMETER Manual
    Show step-by-step instructions for making all of these changes by hand.

.EXAMPLE
    .\Set-BetterbirdIcon.ps1 -MailPopup yours
.EXAMPLE
    .\Set-BetterbirdIcon.ps1 -MailPopup factory
.EXAMPLE
    .\Set-BetterbirdIcon.ps1 -Icon blue
.EXAMPLE
    .\Set-BetterbirdIcon.ps1 -Icon C:\Icons\my-logo.ico -NewMail none
.EXAMPLE
    .\Set-BetterbirdIcon.ps1 -StartPage C:\Docs\manual.html
.EXAMPLE
    .\Set-BetterbirdIcon.ps1 -Portable D:\BetterbirdPortable -Icon blue
#>
[CmdletBinding()]
param(
    [string]$Icon,
    [string]$NewMail,
    [string]$MailPopup,
    [string]$StartPage,
    [switch]$Restore,
    [string]$Portable,
    [switch]$List,
    [switch]$Status,
    [switch]$Manual,
    [switch]$Force,
    # Set when relaunching elevated, so per-user paths stay the invoking user's.
    [string]$UserAppData,
    [string]$UserDesktop,
    [string]$UserStartMenu,
    [switch]$Relaunched,
    # Internal: the elevated window writes its result here for the menu to read.
    [string]$ExitFile
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2

# Windows PowerShell started from pwsh inherits pwsh's module path and then can't load
# Get-Acl. Drop the PowerShell 7 entries.
if ($PSVersionTable.PSVersion.Major -lt 6 -and $env:PSModulePath -match '\\PowerShell\\7\\') {
    $env:PSModulePath = (@($env:PSModulePath -split ';' | Where-Object { $_ -and $_ -notmatch '\\PowerShell\\7\\' }) -join ';')
}

# From Windows rather than env vars, which the user can set.
$ProgramDataDir  = [Environment]::GetFolderPath('CommonApplicationData')
$ProgramFilesDirs = @([Environment]::GetFolderPath('ProgramFiles'), [Environment]::GetFolderPath('ProgramFilesX86')) | Where-Object { $_ }
$WindowsDir      = [Environment]::GetFolderPath('Windows')
if (-not $ProgramDataDir) { throw 'The ProgramData folder is not set on this computer.' }
$DataDir    = Join-Path $ProgramDataDir 'BetterbirdIcons'
$BackupDir  = Join-Path $DataDir 'backup'
$CurrentDir = Join-Path $DataDir 'current'
$StateFile  = Join-Path $DataDir 'state.json'
$OldTask    = 'Betterbird Icons - Reapply'   # from v1, no longer used
$IconFiles  = @('messengerWindow.ico', 'newmail.ico')
$IconStamp  = 'betterbird-icons.txt'   # next to our icons: their hashes
$StartPrefs = 'mailnews\.start_page\.(url|enabled)'
$SideFile   = 'betterbird-icons-startpage.txt'   # per profile: the previous start page
$Admins     = 'S-1-5-32-544'
$System     = 'S-1-5-18'
$NotSystemWide = 'Betterbird is not installed for all users (system-wide) in Program Files. For a portable ' +
                 'Betterbird, or one in your own folder, run this with -Portable <folder>. Run it with ' +
                 '-Manual to see how to make these changes by hand.'
# Profiles are user-writable, so never open them elevated.
$NoAdminProfiles = 'The start page is changed with your normal rights, never as administrator. Run this again ' +
                   'from a normal window (for example by double-clicking Set-BetterbirdIcon.cmd).'
$WindowsPowerShell = Join-Path $WindowsDir 'System32\WindowsPowerShell\v1.0\powershell.exe'

# 'system': Program Files install, needs admin.
# 'own':    portable or per-user install, no admin.
$Mode       = 'system'
$AppDir     = $null   # own mode: folder with betterbird.exe
$Launcher   = $null   # portable: BetterbirdLauncher.exe, which shortcuts target
$ProfileDir = $null   # portable: its profile
# Messages for the next menu screen (D done, W warning, S step), cleared once shown.
$script:Notes = @()
$script:MenuNotice = $null

if (-not $UserAppData)   { $UserAppData   = $env:APPDATA }
if (-not $UserDesktop)   { $UserDesktop   = [Environment]::GetFolderPath('Desktop') }
if (-not $UserStartMenu) { $UserStartMenu = [Environment]::GetFolderPath('StartMenu') }

$SetNotes = [ordered]@{
    'blue'       = 'light blue to green bird on a dark disc'
    'green'      = 'green bird, grey ring'
    'green2'     = 'brighter green bird, grey ring'
    'lightgrey'  = 'light grey bird, grey ring'
    'uk'         = 'blue to yellow bird, grey ring'
    'bb'         = 'orange/red - like the standard Betterbird icon'
    'bb-green'   = 'green/yellow glow'
    'newmail-sm' = 'small new-mail icon'
}

# New-mail dot colours. Amber matches green/bb-green, Red matches blue.
$DotColours = [ordered]@{
    Amber  = '#ff6000'
    Gold   = '#ffd700'
    White  = '#ffffff'
    Pink   = '#ff1493'
    Purple = '#6a1b9a'
    Red    = '#ff2100'
    Grey   = '#808080'
}

# Mail popup images. These live in omni.ja, not in the .ico files.
$PopupChoices = [ordered]@{
    'yours'   = 'light blue to green bird'
    'factory' = "Betterbird's own"
}
$PopupFiles = [ordered]@{
    'chrome/messenger/content/branding/icon64.png'  = @{ File = 'icon64.png';  Size = 64 }
    'chrome/messenger/content/branding/icon128.png' = @{ File = 'icon128.png'; Size = 128 }
}

# ---------------------------------------------------------------- helpers

function Add-Note([string]$Kind, [string]$Text, [switch]$Quiet) {
    # -Quiet: already printed by the elevated window; the menu repeats it.
    # Newlines stripped: one note per line in the result file.
    $clean = ($Text -replace '[\r\n]+', ' ').Trim()
    $script:Notes += [pscustomobject]@{ Kind = $Kind; Text = $clean; Shown = -not $Quiet }
}
function Write-Step([string]$Text) { Write-Host "  $Text"; Add-Note 'S' $Text }
function Write-Done([string]$Text) { Write-Host "  $Text" -ForegroundColor Green; Add-Note 'D' $Text }
function Write-Warn([string]$Text) { Write-Host "  $Text" -ForegroundColor Yellow; Add-Note 'W' $Text }

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-PathUnder([string]$Path, [string]$Root) {
    [bool]$Root -and $Path.StartsWith($Root.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)
}

function Test-ReparsePoint([string]$Path) {
    # Symlinks and junctions only; OneDrive placeholders are reparse points too.
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $item = Get-Item -LiteralPath $Path -Force
    [bool]($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -and $item.LinkType -in 'SymbolicLink', 'Junction'
}

function Test-SystemWideInstall([string]$Dir) {
    # Program Files is admin-only.
    @($ProgramFilesDirs | Where-Object { Test-PathUnder $Dir $_ }).Count -gt 0
}

function Get-InstallDir {
    if ($Mode -eq 'own') { return $AppDir }
    # HKLM App Paths or the default folder. Not HKCU: any user process can write it.
    $dirs = @()
    $key = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\betterbird.exe'
    $reg = Get-ItemProperty $key -ErrorAction SilentlyContinue
    if ($reg -and $reg.PSObject.Properties['Path']) { $dirs += [string]$reg.Path }
    if (@($ProgramFilesDirs).Count -gt 0) { $dirs += Join-Path $ProgramFilesDirs[0] 'Betterbird' }
    foreach ($d in $dirs) {
        if ($d -and (Test-SystemWideInstall $d) -and (Test-Path -LiteralPath (Join-Path $d 'betterbird.exe'))) { return $d.TrimEnd('\') }
    }
    throw $NotSystemWide
}

function Get-IconTarget([string]$Dir) {
    $target = Join-Path $Dir 'chrome\icons\default'
    foreach ($p in (Join-Path $Dir 'chrome'), (Join-Path $Dir 'chrome\icons'), $target) {
        if (Test-ReparsePoint $p) { throw "$p is a link to another folder; not changing it." }
    }
    $target
}

function Get-Hash([string]$Path) {
    if (Test-Path -LiteralPath $Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash } else { $null }
}

function New-State {
    [pscustomobject]@{ Icon = $null; NewMail = $null; InstallDir = $null
                       Shortcuts = @(); OriginalShortcutIcons = [pscustomobject]@{} }
}

function Read-State {
    # Always returns every field, so callers don't need null checks.
    if (-not (Test-Path -LiteralPath $StateFile)) { return $null }
    # Treat an unreadable file as missing (keeps the backup).
    try { $saved = Get-Content -LiteralPath $StateFile -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { Write-Warn "This tool's record $StateFile can't be read."; return $null }
    if ($null -eq $saved) { return $null }
    $state = New-State
    foreach ($name in 'Icon', 'NewMail', 'InstallDir') {
        if ($saved.PSObject.Properties[$name] -and $saved.$name -is [string]) { $state.$name = $saved.$name }
    }
    if ($saved.PSObject.Properties['Shortcuts']) {
        $state.Shortcuts = @($saved.Shortcuts | Where-Object { $_ -is [string] -and $_ })
    }
    if ($saved.PSObject.Properties['OriginalShortcutIcons'] -and $saved.OriginalShortcutIcons -is [pscustomobject]) {
        $state.OriginalShortcutIcons = $saved.OriginalShortcutIcons
    }
    $state
}

function Save-State($State) {
    # UTF-8 for non-ASCII shortcut paths.
    $State | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $StateFile -Encoding UTF8
}

function Assert-NoLinks {
    foreach ($d in $DataDir, $BackupDir, $CurrentDir) {
        if (Test-ReparsePoint $d) { throw "$d is a link to another folder. Delete it and run this again." }
    }
}

function Test-OnlyAdminsCanWrite([string]$Dir, [switch]$CheckOwner) {
    # Only Administrators/SYSTEM may write here (and own it, with -CheckOwner).
    $acl = Get-Acl -LiteralPath $Dir
    if ($CheckOwner -and $acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -notin $Admins, $System) { return $false }
    # 0x2 WriteData/CreateFiles, 0x4 AppendData/CreateDirectories, 0x10 WriteExtendedAttributes,
    # 0x40 DeleteSubdirectoriesAndFiles, 0x100 WriteAttributes, 0x10000 Delete, 0x40000 ChangePermissions,
    # 0x80000 TakeOwnership, 0x10000000 GenericAll, 0x40000000 GenericWrite.
    $write = 0x2 -bor 0x4 -bor 0x10 -bor 0x40 -bor 0x100 -bor 0x10000 -bor 0x40000 -bor 0x80000 -bor 0x10000000 -bor 0x40000000
    foreach ($rule in $acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier])) {
        if ($rule.AccessControlType -eq 'Allow' -and ([long]$rule.FileSystemRights -band $write) -and
            $rule.IdentityReference.Value -notin $Admins, $System) { return $false }
    }
    $true
}

function Test-DataDirTrusted {
    # Ours = owned by Administrators/SYSTEM, admin-only writes, no links.
    # Anyone can create folders in ProgramData, so anything else is rejected.
    if (-not (Test-Path -LiteralPath $DataDir)) { return $false }
    try {
        # No links: folders, state file or icon files.
        $entries = @($DataDir, $BackupDir, $CurrentDir, $StateFile) +
                   @(foreach ($d in $BackupDir, $CurrentDir) { foreach ($name in $IconFiles) { Join-Path $d $name } })
        foreach ($e in $entries) { if (Test-ReparsePoint $e) { return $false } }
        if ($Mode -eq 'own') { return $true }   # user's own folder, own rights
        if (-not (Test-OnlyAdminsCanWrite $DataDir -CheckOwner)) { return $false }
        foreach ($d in $BackupDir, $CurrentDir) {
            # Owner too: whoever owns it can rewrite the DACL.
            if ((Test-Path -LiteralPath $d) -and -not (Test-OnlyAdminsCanWrite $d -CheckOwner)) { return $false }
        }
        $true
    }
    catch {
        # Only access-denied means untrusted. Anything else (e.g. a module that failed to load)
        # is a real error.
        $denied = $_.CategoryInfo.Category -eq 'PermissionDenied' -or
                  $_.Exception -is [UnauthorizedAccessException] -or
                  "$_" -match 'Access is denied'
        if ($denied) { return $false }
        throw
    }
}

function New-ProtectedDirectory([string]$Path) {
    # Create with the DACL already set, so nobody can add files in between.
    if (Test-Path -LiteralPath $Path) { throw "The folder $Path already exists." }
    $inherit = [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
    $none = [Security.AccessControl.PropagationFlags]::None
    $allow = [Security.AccessControl.AccessControlType]::Allow
    $full = [Security.AccessControl.FileSystemRights]::FullControl
    $read = [Security.AccessControl.FileSystemRights]'ReadAndExecute, Synchronize'
    $sec = New-Object Security.AccessControl.DirectorySecurity
    $sec.SetAccessRuleProtection($true, $false)
    $sec.SetOwner((New-Object Security.Principal.SecurityIdentifier $Admins))
    foreach ($pair in @(
            @{ Id = $Admins; Rights = $full },
            @{ Id = $System; Rights = $full },
            @{ Id = 'S-1-5-32-545'; Rights = $read })) {
        $who = New-Object Security.Principal.SecurityIdentifier $pair.Id
        $sec.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($who, $pair.Rights, $inherit, $none, $allow)))
    }
    if ($PSVersionTable.PSVersion.Major -ge 6) {
        [IO.FileSystemAclExtensions]::CreateDirectory($sec, $Path) | Out-Null
    }
    else {
        [IO.Directory]::CreateDirectory($Path, $sec) | Out-Null
    }
    $owner = (Get-Acl -LiteralPath $Path).GetOwner([Security.Principal.SecurityIdentifier]).Value
    if ($owner -ne $Admins) {
        & icacls.exe $Path /setowner "*$Admins" /Q | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Couldn't secure the folder $Path." }
    }
}

function Repair-ChildOwners {
    if ($Mode -eq 'own') { return }
    try {
        if (Test-ReparsePoint $DataDir) { return }
        if (-not (Test-OnlyAdminsCanWrite $DataDir -CheckOwner)) { return }
    }
    catch { return }   # unreadable: the trust check will move it aside
    foreach ($d in $BackupDir, $CurrentDir) {
        if ((Test-Path -LiteralPath $d) -and -not (Test-ReparsePoint $d)) {
            & icacls.exe $d /setowner "*$Admins" /Q | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "Couldn't secure the folder $d." }
        }
    }
}

function Initialize-DataDir {
    if ($Mode -eq 'own') {
        Assert-NoLinks
        New-Item -ItemType Directory -Path $BackupDir, $CurrentDir -Force | Out-Null
        Assert-NoLinks
        return
    }
    # Backups get copied into Program Files elevated, so this folder must be admin-only.
    $fresh = -not (Test-Path -LiteralPath $DataDir)
    if (-not $fresh) {
        # Older versions left backup/current owned by the user. Reclaim them if the parent is ours.
        Repair-ChildOwners
    }
    if (-not $fresh -and -not (Test-DataDirTrusted)) {
        # Not ours, or a link: rename it aside without opening it and start fresh.
        $aside = '{0}.untrusted-{1:yyyyMMdd-HHmmss}' -f (Split-Path $DataDir -Leaf), (Get-Date)
        Rename-Item -LiteralPath $DataDir -NewName $aside
        $moved = Join-Path (Split-Path $DataDir) $aside
        Write-Warn "Moved aside a folder this tool did not make: $moved. Anything backed up in there stays there. This tool will not look in that folder again. Copy the icons out by hand if you still need them."
        $fresh = $true
    }
    if ($fresh) {
        # Fails if someone else created it first.
        New-ProtectedDirectory $DataDir
        if (@(Get-ChildItem -LiteralPath $DataDir -Force).Count -gt 0) {
            # Rename aside now, otherwise its DACL passes the trust check next run.
            $aside = '{0}.untrusted-{1:yyyyMMdd-HHmmss}' -f (Split-Path $DataDir -Leaf), (Get-Date)
            try { Rename-Item -LiteralPath $DataDir -NewName $aside }
            catch {
                # Can't rename (open somewhere?): remove what we'd read from it and stop.
                Remove-DataDir
                throw "Something was put in $DataDir while it was being made. Delete that folder, then run this again."
            }
            throw "Something was put in $DataDir while it was being made, so it was moved aside to $(Join-Path (Split-Path $DataDir) $aside). Run this again; nothing else is needed."
        }
    }
    if (-not (Test-DataDirTrusted)) { throw "Couldn't secure the folder $DataDir." }
    foreach ($d in $BackupDir, $CurrentDir) {
        if (-not (Test-Path -LiteralPath $d)) { New-ProtectedDirectory $d }
        elseif (-not (Test-ReparsePoint $d)) {
            # May still be owned by whoever created it (older version, or a race). Reclaim before
            # trusting it.
            & icacls.exe $d /setowner "*$Admins" /Q | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "Couldn't secure the folder $d." }
        }
    }
    if (-not (Test-DataDirTrusted)) { throw "Couldn't secure the folder $DataDir." }
    Assert-NoLinks
}

function Test-SharedOwnData {
    # Per-user install (not portable): shares %LOCALAPPDATA%\BetterbirdIcons.
    $Mode -eq 'own' -and -not $Launcher
}

function Test-OtherOwnBetterbird([string]$Recorded, [string]$Dir) {
    # Shared record points at another per-user install that still exists. If that one is
    # gone, assume it was this one, moved or reinstalled.
    (Test-SharedOwnData) -and $Recorded -and $Recorded.TrimEnd('\') -ne $Dir.TrimEnd('\') -and
        (Test-Path -LiteralPath (Join-Path $Recorded 'betterbird.exe'))
}

function Test-HasBackup {
    @($IconFiles | Where-Object { Test-Path -LiteralPath (Join-Path $BackupDir $_) }).Count -gt 0
}

function Remove-DataDir([switch]$KeepBackup) {
    # Delete only our own files, never recursively. v1 leftovers go too.
    foreach ($f in (Join-Path $DataDir 'Set-BetterbirdIcon.ps1'), (Join-Path $DataDir 'reapply.log')) {
        Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue
    }
    # -KeepBackup: keep backup, record and current icons for a later Restore.
    if ($KeepBackup) { return }
    foreach ($d in $BackupDir, $CurrentDir) {
        # Don't delete through a link.
        if (Test-ReparsePoint $d) { continue }
        foreach ($name in $IconFiles) { Remove-Item -LiteralPath (Join-Path $d $name) -Force -ErrorAction SilentlyContinue }
    }
    Remove-Item -LiteralPath $StateFile -Force -ErrorAction SilentlyContinue
    foreach ($d in $BackupDir, $CurrentDir, $DataDir) {
        if ((Test-Path -LiteralPath $d) -and -not (Test-ReparsePoint $d) -and @(Get-ChildItem -LiteralPath $d -Force).Count -eq 0) {
            Remove-Item -LiteralPath $d -Force
        }
    }
    if (Test-Path -LiteralPath $DataDir) { Write-Warn "Left $DataDir in place: it holds files this tool did not make." }
}

function Remove-OldReapplyTask {
    # v1 could register a SYSTEM task to reapply the icons. Updates don't touch them, so
    # remove it.
    try { $task = Get-ScheduledTask -TaskName $OldTask -ErrorAction SilentlyContinue } catch { $task = $null }
    if (-not $task) { return }
    Unregister-ScheduledTask -TaskName $OldTask -Confirm:$false
    if (Test-DataDirTrusted) { Remove-Item -LiteralPath (Join-Path $DataDir 'Set-BetterbirdIcon.ps1') -Force -ErrorAction SilentlyContinue }
    Write-Step "Removed the old '$OldTask' task; it is not needed."
}

function Get-Betterbird {
    # Running instances of the Betterbird being changed (portable and installed are separate).
    # A process with an unreadable path counts.
    $dir = $null
    try { $dir = Get-InstallDir } catch { $null = $_ }
    @(Get-Process -Name betterbird -ErrorAction SilentlyContinue | Where-Object {
        try { $path = $_.Path } catch { $path = $null }   # e.g. exited meanwhile
        -not $dir -or -not $path -or (Test-PathUnder $path $dir) })
}

function Test-Interactive { -not [Console]::IsInputRedirected -and [Environment]::UserInteractive }

function Close-Betterbird([string]$Why) {
    if (@(Get-Betterbird).Count -eq 0) { return }
    if (-not $Force) {
        # Don't close it unasked. Non-interactive: fail.
        if (-not (Test-Interactive)) {
            throw "Betterbird is open. Close it $Why, or pass -Force to close it automatically."
        }
        $answer = Read-Host "  Betterbird is open and must be closed $Why. Close it now? (Y/N)"
        if ($answer -notmatch '^[Yy]') { throw 'Close Betterbird and run this again.' }
    }
    Get-Betterbird | ForEach-Object { [void]$_.CloseMainWindow() }
    for ($i = 0; $i -lt 30 -and @(Get-Betterbird).Count -gt 0; $i++) { Start-Sleep -Milliseconds 500 }
    if (@(Get-Betterbird).Count -gt 0) { throw 'Betterbird did not close. Close it yourself and run this again.' }
    Write-Step 'Closed Betterbird.'
}

function Get-IcoFrames([string]$Path) {
    # All image sizes in the .ico as bitmaps.
    Add-Type -AssemblyName System.Drawing
    $bytes = [IO.File]::ReadAllBytes($Path)
    $count = [BitConverter]::ToUInt16($bytes, 4)
    $frames = New-Object System.Collections.Generic.List[System.Drawing.Bitmap]
    for ($i = 0; $i -lt $count; $i++) {
        $entry = 6 + 16 * $i
        $wide = $bytes[$entry]; if ($wide -eq 0) { $wide = 256 }
        $length = [BitConverter]::ToInt32($bytes, $entry + 8)
        $offset = [BitConverter]::ToInt32($bytes, $entry + 12)
        $blob = New-Object byte[] $length
        [Array]::Copy($bytes, $offset, $blob, 0, $length)
        if ($blob[0] -eq 0x89) {
            $stream = New-Object IO.MemoryStream(,$blob)
            $loaded = New-Object System.Drawing.Bitmap $stream
            $copy = New-Object System.Drawing.Bitmap $loaded
            $loaded.Dispose(); $stream.Dispose()
            $frames.Add($copy)
            continue
        }
        $header = [BitConverter]::ToInt32($blob, 0)
        $height = [Math]::Abs([BitConverter]::ToInt32($blob, 8))
        $bpp = [BitConverter]::ToInt16($blob, 14)
        if ($height -gt $wide) { $height = [int]($height / 2) }
        if ($bpp -ne 32) { continue }
        $bmp = New-Object System.Drawing.Bitmap $wide, $height
        $stride = $wide * 4
        for ($y = 0; $y -lt $height; $y++) {
            $row = $header + (($height - 1 - $y) * $stride)
            for ($x = 0; $x -lt $wide; $x++) {
                $p = $row + $x * 4
                $bmp.SetPixel($x, $y, [System.Drawing.Color]::FromArgb($blob[$p + 3], $blob[$p + 2], $blob[$p + 1], $blob[$p]))
            }
        }
        $frames.Add($bmp)
    }
    if ($frames.Count -eq 0) { throw "$Path has no picture this tool can read." }
    $frames
}

function Write-IcoFile($Frames, [string]$Path) {
    # Same layout as tools/svg_to_ico.py: BMP below 256, PNG at 256.
    $blobs = New-Object System.Collections.Generic.List[byte[]]
    foreach ($bmp in $Frames) {
        if ($bmp.Width -ge 256) {
            $stream = New-Object IO.MemoryStream
            $bmp.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
            $blobs.Add($stream.ToArray()); $stream.Dispose()
            continue
        }
        $w = $bmp.Width; $h = $bmp.Height
        $header = [byte[]]::new(40)
        [BitConverter]::GetBytes([int]40).CopyTo($header, 0)
        [BitConverter]::GetBytes([int]$w).CopyTo($header, 4)
        [BitConverter]::GetBytes([int]($h * 2)).CopyTo($header, 8)
        [BitConverter]::GetBytes([int16]1).CopyTo($header, 12)
        [BitConverter]::GetBytes([int16]32).CopyTo($header, 14)
        $pixels = New-Object byte[] ($w * $h * 4)
        for ($y = 0; $y -lt $h; $y++) {
            for ($x = 0; $x -lt $w; $x++) {
                $c = $bmp.GetPixel($x, ($h - 1 - $y))
                $p = ($y * $w + $x) * 4
                $pixels[$p] = $c.B; $pixels[$p + 1] = $c.G; $pixels[$p + 2] = $c.R; $pixels[$p + 3] = $c.A
            }
        }
        $maskStride = [int](($w + 31) / 32) * 4
        $mask = New-Object byte[] ($maskStride * $h)
        for ($y = 0; $y -lt $h; $y++) {
            $srcY = $h - 1 - $y
            for ($x = 0; $x -lt $w; $x++) {
                if ($bmp.GetPixel($x, $srcY).A -eq 0) { $mask[$y * $maskStride + [int]($x / 8)] = $mask[$y * $maskStride + [int]($x / 8)] -bor (0x80 -shr ($x % 8)) }
            }
        }
        $blob = New-Object byte[] ($header.Length + $pixels.Length + $mask.Length)
        $header.CopyTo($blob, 0); $pixels.CopyTo($blob, 40); $mask.CopyTo($blob, 40 + $pixels.Length)
        $blobs.Add($blob)
    }
    $offset = 6 + 16 * $blobs.Count
    $out = New-Object System.Collections.Generic.List[byte]
    $out.AddRange([byte[]](0, 0, 1, 0))
    $count = [byte[]][BitConverter]::GetBytes([uint16]$blobs.Count)
    $out.AddRange($count)
    for ($i = 0; $i -lt $blobs.Count; $i++) {
        $w = $Frames[$i].Width % 256
        $entry = [byte[]]::new(16)
        $entry[0] = $w; $entry[1] = $w; $entry[4] = 1; $entry[6] = 32
        [BitConverter]::GetBytes([int]$blobs[$i].Length).CopyTo($entry, 8)
        [BitConverter]::GetBytes([int]$offset).CopyTo($entry, 12)
        $out.AddRange($entry)
        $offset += $blobs[$i].Length
    }
    foreach ($blob in $blobs) { $out.AddRange($blob) }
    [IO.File]::WriteAllBytes($Path, $out.ToArray())
}

function Add-IconDot([string]$Source, [string]$Dest, [string]$Hex) {
    # Dot at the lower right, same as the SVG sets.
    $frames = Get-IcoFrames $Source
    $color = [System.Drawing.ColorTranslator]::FromHtml($Hex)
    foreach ($bmp in $frames) {
        $draw = [System.Drawing.Graphics]::FromImage($bmp)
        $draw.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $size = [single]$bmp.Width
        $radius = $size * 0.16
        $x = ($size * 0.77) - $radius
        $y = ($size * 0.77) - $radius
        # Dark outline so a white dot shows on a light bird.
        if ($Hex -eq '#ffffff') {
            $edge = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 48, 48, 48))
            $ring = $radius * 1.18
            $draw.FillEllipse($edge, ($size * 0.77) - $ring, ($size * 0.77) - $ring, $ring * 2, $ring * 2)
            $edge.Dispose()
        }
        $brush = New-Object System.Drawing.SolidBrush $color
        $draw.FillEllipse($brush, $x, $y, $radius * 2, $radius * 2)
        $brush.Dispose(); $draw.Dispose()
    }
    Write-IcoFile $frames $Dest
    foreach ($bmp in $frames) { $bmp.Dispose() }
}

function Get-DotColourName([string]$Path) {
    # Which menu colour the dot is, or nothing if unknown or unreadable.
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return $null }
    $frames = @()
    try {
        $frames = @(Get-IcoFrames $Path)
        $bmp = $frames | Sort-Object Width -Descending | Select-Object -First 1
        $color = $bmp.GetPixel([int]($bmp.Width * 0.77), [int]($bmp.Height * 0.77))
        $found = $null
        foreach ($name in $DotColours.Keys) {
            $known = [System.Drawing.ColorTranslator]::FromHtml($DotColours[$name])
            $distance = [Math]::Abs($color.R - $known.R) + [Math]::Abs($color.G - $known.G) + [Math]::Abs($color.B - $known.B)
            if ($distance -le 40) { $found = $name }
        }
        $found
    }
    catch { $null }
    finally { foreach ($frame in $frames) { if ($frame) { $frame.Dispose() } } }
}

function Get-WindowIconPath([string]$Icon) {
    $set = Join-Path $PSScriptRoot "icons\$Icon\messengerWindow.ico"
    if (Test-Path -LiteralPath $set) { return $set }
    if (Test-Path -LiteralPath $Icon -PathType Leaf) { return (Resolve-Path -LiteralPath $Icon).Path }
    $null
}

function Get-CurrentNewMailPath([string]$Icon) {
    # Installed new-mail icon, else the set's own.
    try {
        $installed = Join-Path (Get-IconTarget (Get-InstallDir)) 'newmail.ico'
        if (Test-Path -LiteralPath $installed) { return $installed }
    } catch { $null = $_ }
    $set = Join-Path $PSScriptRoot "icons\$Icon\newmail.ico"
    if (Test-Path -LiteralPath $set) { return $set }
    $null
}

function Test-IcoFile([string]$Path) {
    $buf = New-Object byte[] 6
    $fs = [IO.File]::OpenRead($Path)
    try { $n = $fs.Read($buf, 0, 6) } finally { $fs.Close() }
    # ICO header: reserved 0, type 1, at least one image.
    $n -eq 6 -and $buf[0] -eq 0 -and $buf[1] -eq 0 -and $buf[2] -eq 1 -and $buf[3] -eq 0 -and ($buf[4] -bor $buf[5]) -ne 0
}

function Resolve-IconFile([string]$Value, [string]$FileName) {
    # Set name or .ico path.
    if (Test-Path -LiteralPath $Value -PathType Leaf) {
        $full = (Resolve-Path -LiteralPath $Value).Path
        if ([IO.Path]::GetExtension($full) -ne '.ico' -or -not (Test-IcoFile $full)) { throw "$Value is not an .ico icon file." }
        return $full
    }
    if ($Value -notmatch '^[A-Za-z0-9-]+$') { throw "There is no icon set or .ico file called '$Value'." }
    $setDir = Join-Path $PSScriptRoot "icons\$Value"
    if (-not (Test-Path -LiteralPath $setDir)) { throw "There is no icon set called '$Value'. Run with -List to see them." }
    $file = Join-Path $setDir $FileName
    if (Test-Path -LiteralPath $file) {
        if (-not (Test-IcoFile $file)) { throw "The icon set '$Value' has a damaged $FileName." }
        return $file
    }
    return $null
}

function Update-IconCache {
    $tool = Join-Path $env:SystemRoot 'System32\ie4uinit.exe'
    if (Test-Path -LiteralPath $tool) { & $tool -show 2>$null }
}

function Format-Arg([string]$Value) {
    # Quote one argument per the Windows command-line rules.
    '"' + ($Value -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"'
}

function Get-RelaunchArgs($Options) {
    # Relaunch arguments, keeping this user's folders. The menu waits for the result file.
    $pass = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Format-Arg $PSCommandPath), '-Relaunched',
              '-UserAppData', (Format-Arg $UserAppData), '-UserDesktop', (Format-Arg $UserDesktop),
              '-UserStartMenu', (Format-Arg $UserStartMenu))
    foreach ($kv in $Options.GetEnumerator()) {
        if ($kv.Key -in 'UserAppData', 'UserDesktop', 'UserStartMenu', 'Relaunched', 'ExitFile') { continue }
        if ($kv.Value -is [switch] -or $kv.Value -is [bool]) { if ($kv.Value) { $pass += "-$($kv.Key)" } }
        else {
            $value = [string]$kv.Value
            # Pass full paths: the new window starts in another folder. Test-Path throws on
            # invalid path chars in Windows PowerShell.
            $isPath = $false
            $word = ($kv.Key -eq 'NewMail' -and $value -eq 'none') -or ($kv.Key -eq 'StartPage' -and $value -eq 'Off')
            if ($kv.Key -in 'Icon', 'NewMail', 'StartPage', 'Portable' -and $value -and -not $word) {
                try { $isPath = Test-Path -LiteralPath $value } catch { $isPath = $false }
            }
            if ($isPath) { $value = (Resolve-Path -LiteralPath $value).ProviderPath }
            $pass += "-$($kv.Key)"; $pass += Format-Arg $value
        }
    }
    $pass
}

function Test-SafeExitFile([string]$Path) {
    # Result file must be inside this user's temp folder.
    if (-not $Path) { return $false }
    try { $full = [IO.Path]::GetFullPath($Path) } catch { return $false }
    $temp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
    if (-not $full.StartsWith($temp + '\', [StringComparison]::OrdinalIgnoreCase)) { return $false }
    if ([IO.Path]::GetExtension($full) -ne '.exit') { return $false }
    $dir = Split-Path $full
    if ((Test-Path -LiteralPath $dir) -and (Test-ReparsePoint $dir)) { return $false }
    if ((Test-Path -LiteralPath $full) -and (Test-ReparsePoint $full)) { return $false }
    $true
}

function Write-ExitFile([string]$Path, [int]$Code) {
    # Write then rename, so the reader never sees a partial file.
    if (-not (Test-SafeExitFile $Path)) { return $false }
    $lines = @("$Code")
    foreach ($n in @($script:Notes)) { $lines += "$($n.Kind):$($n.Text)" }
    $tmp = "$Path.writing"
    try {
        $utf8 = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllLines($tmp, [string[]]$lines, $utf8)
        if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force }
        [IO.File]::Move($tmp, $Path)
    }
    catch {
        Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue
        return $false
    }
    $true
}

function Read-ExitFile([string]$Path) {
    if (-not (Test-SafeExitFile $Path)) { return @{ Code = 1; Notes = @() } }
    $raw = @(Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue)
    Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    $code = 1
    if ($raw.Count -ge 1 -and $raw[0] -match '^\d+$') { $code = [int]$raw[0] }
    $notes = @()
    for ($i = 1; $i -lt $raw.Count; $i++) {
        $line = [string]$raw[$i]
        if ($line -match '^([DSW]):(.*)$') { $notes += [pscustomobject]@{ Kind = $Matches[1]; Text = $Matches[2] } }
        elseif ($line) { $notes += [pscustomobject]@{ Kind = 'S'; Text = $line } }
    }
    @{ Code = $code; Notes = $notes }
}

function Invoke-Elevated($Options) {
    # Full path, so a powershell.exe in the current folder isn't picked up.
    # RunAs returns before the elevated script ends, so wait for its result file.
    $exitFile = Join-Path ([IO.Path]::GetTempPath()) ("betterbird-icons-{0}.exit" -f [guid]::NewGuid().ToString('n'))
    $relaunch = @(Get-RelaunchArgs $Options) + @('-ExitFile', (Format-Arg $exitFile))
    try { $proc = Start-Process $WindowsPowerShell -Verb RunAs -ArgumentList $relaunch -PassThru }
    catch {
        $e = $_.Exception
        while ($e -and $e -isnot [ComponentModel.Win32Exception]) { $e = $e.InnerException }
        if ($e -and $e.NativeErrorCode -eq 1223) { Write-Warn 'Administrator permission was not given, so the icons were not changed.' }   # ERROR_CANCELLED
        else { Write-Warn "Couldn't start the administrator window, so the icons were not changed: $($_.Exception.Message)" }
        return $false
    }
    if (-not $proc) { Write-Warn "Couldn't start the administrator window, so the icons were not changed."; return $false }
    $deadline = (Get-Date).AddMinutes(3)
    while (-not (Test-Path -LiteralPath $exitFile)) {
        if ((Get-Date) -gt $deadline) {
            Write-Warn 'The administrator window did not finish, so the icons may not have changed.'
            return $false
        }
        Start-Sleep -Milliseconds 200
    }
    $result = Read-ExitFile $exitFile
    foreach ($n in @($result.Notes)) { Add-Note $n.Kind $n.Text -Quiet }
    return ($result.Code -eq 0)
}

function Invoke-AsStandardUser($Options) {
    # Relaunch de-elevated with runas /trustlevel. runas takes the command as one quoted
    # argument, so options can't contain quotes (paths can't anyway).
    foreach ($kv in $Options.GetEnumerator()) {
        if ("$($kv.Value)".Contains('"')) { throw "The option -$($kv.Key) can't contain a quote character." }
    }
    $command = (Format-Arg $WindowsPowerShell) + ' ' + ((Get-RelaunchArgs $Options) -join ' ')
    # Not hidden: it's interactive.
    Start-Process (Join-Path $env:SystemRoot 'System32\runas.exe') -ArgumentList ('/trustlevel:0x20000 ' + (Format-Arg $command))
    Write-Step 'Started again as a standard user in a new window.'
}

function Get-ElevatedOptions($Options) {
    # Everything except StartPage.
    $elevated = @{}
    foreach ($kv in $Options.GetEnumerator()) {
        if ($kv.Key -ne 'StartPage' -and $kv.Key -ne 'ExitFile') { $elevated[$kv.Key] = $kv.Value }
    }
    $elevated
}

function Resolve-OwnFolder([string]$Folder) {
    # Portable: BetterbirdLauncher.exe + core\betterbird.exe + profile\.
    # Per-user install: betterbird.exe, profiles in AppData.
    if (-not (Test-Path -LiteralPath $Folder -PathType Container)) { throw "Can't find the folder $Folder" }
    $full = (Resolve-Path -LiteralPath $Folder).ProviderPath
    if ($full.Length -gt 3) { $full = $full.TrimEnd('\') }   # keep a drive root like C:\
    if ((Split-Path $full -Leaf) -eq 'core' -and (Test-Path -LiteralPath (Join-Path (Split-Path $full) 'BetterbirdLauncher.exe'))) {
        $full = Split-Path $full
    }
    if ((Test-Path -LiteralPath (Join-Path $full 'BetterbirdLauncher.exe')) -and (Test-Path -LiteralPath (Join-Path $full 'core\betterbird.exe'))) {
        $portableProfile = Join-Path $full 'profile'
        $saved = Join-Path $full 'last-profile-location.txt'
        if (Test-Path -LiteralPath $saved) {
            $line = @(Read-Lines $saved | Where-Object { $_.Trim() })[0]
            if ($line) { $line = $line.Trim().Trim('"') }
            if ($line -and (Test-Path -LiteralPath $line -PathType Container)) { $portableProfile = $line.TrimEnd('\') }
        }
        $own = @{ AppDir = Join-Path $full 'core'; Launcher = Join-Path $full 'BetterbirdLauncher.exe'
                  ProfileDir = $portableProfile; DataDir = Join-Path $full 'BetterbirdIcons' }
    }
    elseif (Test-Path -LiteralPath (Join-Path $full 'betterbird.exe')) {
        if (-not $env:LOCALAPPDATA) { throw 'The LocalAppData folder is not set on this computer.' }
        $own = @{ AppDir = $full; Launcher = $null; ProfileDir = $null
                  DataDir = Join-Path $env:LOCALAPPDATA 'BetterbirdIcons' }
    }
    else { throw "There is no Betterbird in $full (no betterbird.exe or BetterbirdLauncher.exe)." }
    if (Test-SystemWideInstall $own.AppDir) {
        throw "$full is installed for all users. Run this without -Portable."
    }
    $own
}

function Enter-OwnFolderMode([string]$Folder) {
    $own = Resolve-OwnFolder $Folder
    $script:Mode       = 'own'
    $script:AppDir     = $own.AppDir
    $script:Launcher   = $own.Launcher
    $script:ProfileDir = $own.ProfileDir
    $script:DataDir    = $own.DataDir
    $script:BackupDir  = Join-Path $own.DataDir 'backup'
    $script:CurrentDir = Join-Path $own.DataDir 'current'
    $script:StateFile  = Join-Path $own.DataDir 'state.json'
    $kind = if ($own.Launcher) { 'portable' } else { 'in your own folder' }
    Write-Step "Using the Betterbird $kind at $($own.AppDir)"
}

function Confirm-StandardUser($Options) {
    # Own-folder installs don't need admin. If elevated, offer to restart de-elevated.
    # Returns $true to continue here.
    if (-not (Test-Admin) -or $Force) { return $true }
    if (-not (Test-Interactive)) {
        throw 'This is running as administrator, which a Betterbird in your own folder does not need. Run it without administrator rights, or add -Force to carry on.'
    }
    Write-Host ''
    Write-Host "  You're running as administrator. A Betterbird in your own folder doesn't need that." -ForegroundColor Yellow
    Write-Host '  1) Start again as a standard user   (recommended)'
    Write-Host '  2) Continue as administrator'
    Write-Host '  Q) Quit'
    switch ("$(Read-Host '  Choose')".Trim()) {
        '1' { Invoke-AsStandardUser $Options; return $false }
        '2' { return $true }
        default { return $false }
    }
}

function Get-BetterbirdExes([string]$Dir) {
    # Shortcut targets: the exe or the portable launcher.
    @(Join-Path $Dir 'betterbird.exe') + @($Launcher | Where-Object { $_ })
}

# ---------------------------------------------------------------- shortcuts

function Get-ShortcutFolders {
    # Desktops and taskbar are flat; only the Start menus are searched recursively.
    @{ Flat = @([Environment]::GetFolderPath('CommonDesktopDirectory'), $UserDesktop,
                (Join-Path $UserAppData 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'))
       Deep = @([Environment]::GetFolderPath('CommonStartMenu'), $UserStartMenu) }
}

function Get-LnkFiles([string]$Dir, [switch]$Recurse) {
    # .lnk files, optionally recursive, not following links.
    Get-ChildItem -LiteralPath $Dir -Filter *.lnk -File -ErrorAction SilentlyContinue
    if (-not $Recurse) { return }
    foreach ($sub in @(Get-ChildItem -LiteralPath $Dir -Directory -ErrorAction SilentlyContinue)) {
        if (-not ($sub.Attributes -band [IO.FileAttributes]::ReparsePoint)) { Get-LnkFiles $sub.FullName -Recurse }
    }
}

function Find-Shortcuts([string[]]$Exes) {
    $folders = Get-ShortcutFolders
    $shell = New-Object -ComObject WScript.Shell
    $files = @()
    foreach ($d in $folders.Flat) { if ($d -and (Test-Path -LiteralPath $d)) { $files += @(Get-LnkFiles $d) } }
    foreach ($d in $folders.Deep) { if ($d -and (Test-Path -LiteralPath $d)) { $files += @(Get-LnkFiles $d -Recurse) } }
    foreach ($f in $files) {
        # Skip shortcuts we can't read.
        try { $target = [Environment]::ExpandEnvironmentVariables($shell.CreateShortcut($f.FullName).TargetPath) }
        catch { continue }
        if ($Exes -contains $target) { $f.FullName }
    }
}

function Save-ShortcutIcon($Shell, [string]$Path, [string]$IconLocation) {
    # Clear read-only for the save, then put it back.
    if (Test-ReparsePoint $Path) { Write-Warn "Skipped $Path - it is a link."; return $false }
    $file = Get-Item -LiteralPath $Path
    $wasReadOnly = $file.IsReadOnly
    try {
        $file.IsReadOnly = $false
        $lnk = $Shell.CreateShortcut($Path)
        $lnk.IconLocation = $IconLocation
        # Re-check right before saving in case it was swapped for a link.
        if (Test-ReparsePoint $Path) { Write-Warn "Skipped $Path - it is a link."; return $false }
        $lnk.Save()
        return $true
    }
    catch { Write-Warn "Couldn't update the shortcut $Path ($($_.Exception.Message))"; return $false }
    finally { if (Test-Path -LiteralPath $Path) { (Get-Item -LiteralPath $Path).IsReadOnly = $wasReadOnly } }
}

function Set-ShortcutIcons($State, [string[]]$Exes) {
    $shell = New-Object -ComObject WScript.Shell
    $paths = @(@($State.Shortcuts) + @(Find-Shortcuts $Exes) | Where-Object { $_ } | Select-Object -Unique)
    $icon = (Join-Path $CurrentDir 'messengerWindow.ico') + ',0'
    $kept = @()
    foreach ($p in $paths) {
        if (-not (Test-Path -LiteralPath $p)) { continue }
        try { $lnk = $shell.CreateShortcut($p) } catch { continue }
        if ($Exes -notcontains [Environment]::ExpandEnvironmentVariables($lnk.TargetPath)) { continue }
        if ($null -eq $State.OriginalShortcutIcons.PSObject.Properties[$p]) {
            # Ours but unrecorded (interrupted run): treat the default icon as the original.
            $original = if ($lnk.IconLocation -like "$CurrentDir*") { ',0' } else { $lnk.IconLocation }
            $State.OriginalShortcutIcons | Add-Member -NotePropertyName $p -NotePropertyValue $original
        }
        if ($lnk.IconLocation -ne $icon -and -not (Save-ShortcutIcon $shell $p $icon)) { continue }
        $kept += $p
    }
    $State.Shortcuts = $kept
    return $kept.Count
}

function Restore-ShortcutIcons($State) {
    # Only reset shortcuts still using our icon; leave ones changed since.
    $shell = New-Object -ComObject WScript.Shell
    $ours = (Join-Path $CurrentDir 'messengerWindow.ico') + ',0'
    foreach ($prop in $State.OriginalShortcutIcons.PSObject.Properties) {
        if (-not (Test-Path -LiteralPath $prop.Name)) { continue }
        try { $now = $shell.CreateShortcut($prop.Name).IconLocation } catch { continue }
        if ($now -eq $ours) { [void](Save-ShortcutIcon $shell $prop.Name ([string]$prop.Value)) }
    }
}

# ---------------------------------------------------------------- icon actions

function Read-IconStamp([string]$Target) {
    # Hashes of the icons we installed, kept next to them so they're still recognised if
    # the data folder is lost.
    $stamp = @{}
    $path = Join-Path $Target $IconStamp
    if (-not (Test-Path -LiteralPath $path)) { return $stamp }
    foreach ($line in (Read-Lines $path)) {
        if ($line -match '^(messengerWindow\.ico|newmail\.ico)=([0-9A-F]{64})$') { $stamp[$Matches[1]] = $Matches[2] }
    }
    $stamp
}

function Write-IconStamp([string]$Target) {
    $path = Join-Path $Target $IconStamp
    if (Test-ReparsePoint $path) { throw "$path is a link; not changing it." }
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($name in $IconFiles) {
        $hash = Get-Hash (Join-Path $CurrentDir $name)
        if ($hash) { $lines.Add(('{0}={1}' -f $name, $hash)) }
    }
    if ($lines.Count -eq 0) {
        if ((Test-Path -LiteralPath $path) -and -not (Test-ReparsePoint $path)) { Remove-Item -LiteralPath $path -Force }
        return
    }
    Write-Text $path (($lines.ToArray() -join "`r`n") + "`r`n")
}

function Remove-IconStamp([string]$Target) {
    $path = Join-Path $Target $IconStamp
    if ((Test-Path -LiteralPath $path) -and -not (Test-ReparsePoint $path)) { Remove-Item -LiteralPath $path -Force }
}

function Backup-Originals([string]$Target) {
    # Back up anything in the icon folder that isn't ours. Never delete or overwrite an
    # existing backup here; only Restore removes backups.
    $stamp = Read-IconStamp $Target
    foreach ($name in $IconFiles) {
        $dest = Join-Path $BackupDir $name
        if (Test-Path -LiteralPath $dest) { continue }
        $hash = Get-Hash (Join-Path $Target $name)
        if (-not $hash) { continue }
        if ($hash -eq (Get-Hash (Join-Path $CurrentDir $name))) { continue }
        if ($stamp.ContainsKey($name) -and $stamp[$name] -eq $hash) { continue }
        Copy-Item -LiteralPath (Join-Path $Target $name) $dest -Force
    }
}

function Copy-CurrentToInstall([string]$Target, [switch]$BuiltInNewMail) {
    # Per file: ours, else the backup, else nothing (built-in icon).
    # -BuiltInNewMail forces the built-in new-mail icon.
    if (-not (Test-Path -LiteralPath $Target)) { New-Item -ItemType Directory -Path $Target -Force | Out-Null }
    foreach ($name in $IconFiles) {
        $src = Join-Path $CurrentDir $name
        $dst = Join-Path $Target $name
        $backup = Join-Path $BackupDir $name
        if (Test-ReparsePoint $dst) { throw "$dst is a link; not changing it." }
        if (Test-Path -LiteralPath $dst) { (Get-Item -LiteralPath $dst).IsReadOnly = $false }   # v1 could set read-only
        if (Test-Path -LiteralPath $src) {
            if ((Get-Hash $src) -ne (Get-Hash $dst)) { Copy-Item -LiteralPath $src $dst -Force }
        }
        elseif ((Test-Path -LiteralPath $backup) -and -not ($BuiltInNewMail -and $name -eq 'newmail.ico')) {
            Copy-Item -LiteralPath $backup $dst -Force
        }
        else { Remove-Item -LiteralPath $dst -ErrorAction SilentlyContinue }
    }
}

function Install-Icon([string]$Value, [string]$NewMailValue) {
    $dir = Get-InstallDir
    $target = Get-IconTarget $dir
    $main = Resolve-IconFile $Value 'messengerWindow.ico'
    if (-not $main) { throw "'$Value' only has a new-mail icon. Use it with -NewMail instead." }
    if ($NewMailValue -eq 'none') { $mail = $null }
    elseif ($NewMailValue) {
        $mail = Resolve-IconFile $NewMailValue 'newmail.ico'
        if (-not $mail) { throw "'$NewMailValue' has no new-mail icon." }
    }
    elseif (Test-Path -LiteralPath $Value -PathType Leaf) { $mail = $null }
    else { $mail = Resolve-IconFile $Value 'newmail.ico' }

    Initialize-DataDir
    $state = Read-State
    if (-not $state) { $state = New-State }
    # Per-user installs share the data folder: don't mix up two installs' backups.
    # Portable data moves with its folder, so a moved portable is fine.
    if ((Test-OtherOwnBetterbird $state.InstallDir $dir) -and (Test-HasBackup)) {
        throw "This tool has already changed the Betterbird in $($state.InstallDir) and keeps its backup in $DataDir. Restore that one first."
    }
    # Save InstallDir first so an interrupted run can still be restored.
    $state.InstallDir = $dir
    Save-State $state
    Backup-Originals $target

    Copy-Item -LiteralPath $main (Join-Path $CurrentDir 'messengerWindow.ico') -Force
    if ($mail) { Copy-Item -LiteralPath $mail (Join-Path $CurrentDir 'newmail.ico') -Force }
    else { Remove-Item -LiteralPath (Join-Path $CurrentDir 'newmail.ico') -ErrorAction SilentlyContinue }

    Copy-CurrentToInstall $target -BuiltInNewMail:($NewMailValue -eq 'none')
    Write-IconStamp $target
    $state.Icon = $Value
    # 'none' = built-in; 'original' = whatever was there (set has no new-mail icon).
    $state.NewMail = if ($mail) { if ($NewMailValue) { $NewMailValue } else { $Value } } elseif ($NewMailValue -eq 'none') { 'none' } else { 'original' }
    Save-State $state   # icons in place; save before touching shortcuts
    $n = Set-ShortcutIcons $state (Get-BetterbirdExes $dir)
    Save-State $state
    Update-IconCache

    Write-Done "Icon set to '$Value' (new-mail icon: $($state.NewMail)); $n shortcut(s) now use it."
    if (@(Get-Betterbird).Count -gt 0) { Write-Warn 'Restart Betterbird to see the new icon.' }
}

function Restore-Originals {
    if (-not (Test-Path -LiteralPath $DataDir)) {
        # No backup, but the stamp still identifies our files.
        $dir = $null
        try { $dir = Get-InstallDir } catch { $null = $_ }
        if ($dir) {
            $target = Get-IconTarget $dir
            $stamp = Read-IconStamp $target
            $removed = $false
            foreach ($name in $IconFiles) {
                $dst = Join-Path $target $name
                if ($stamp.ContainsKey($name) -and (Get-Hash $dst) -eq $stamp[$name]) {
                    if (Test-ReparsePoint $dst) { throw "$dst is a link; not changing it." }
                    Remove-Item -LiteralPath $dst -Force
                    $removed = $true
                }
            }
            if ($stamp.Count -gt 0) { Remove-IconStamp $target }
            if ($removed) {
                Update-IconCache
                Write-Warn "Removed this tool's icons. The backup of your earlier icons is gone, so they could not be put back."
                return
            }
        }
        Write-Step 'Nothing to restore - this script has not changed the icons.'
        return
    }
    if (-not (Test-DataDirTrusted)) {
        throw "$DataDir was not made by this tool, so its contents can't be trusted. Use the manual instructions (-Manual) to put the icons back by hand."
    }
    $state = Read-State
    if (-not ($state -and $state.InstallDir)) {
        # No usable record, so we can't tell where the backup belongs: keep it.
        if ($state) { Restore-ShortcutIcons $state }
        if (Test-HasBackup) {
            Write-Warn "This tool's record is missing, so your earlier icons were left in $BackupDir. Copy them back by hand (see -Manual)."
            return
        }
        Remove-DataDir
        Write-Done 'Nothing left to restore.'
        return
    }
    # Recorded InstallDir (written elevated), so this still works after an uninstall.
    $dir = [string]$state.InstallDir
    if ((Test-OtherOwnBetterbird $dir $AppDir) -and (Test-HasBackup)) {
        throw "The backup in $DataDir belongs to the Betterbird in $dir. Restore that one instead."
    }
    if ($Mode -eq 'own' -or -not (Test-SystemWideInstall $dir)) { $dir = Get-InstallDir }
    $target = Get-IconTarget $dir
    $restored = Test-Path -LiteralPath $target
    if ($restored) {
        $stamp = Read-IconStamp $target
        foreach ($name in $IconFiles) {
            $dst = Join-Path $target $name
            $backup = Join-Path $BackupDir $name
            if (Test-ReparsePoint $dst) { throw "$dst is a link; not changing it." }
            if (Test-Path -LiteralPath $dst) { (Get-Item -LiteralPath $dst).IsReadOnly = $false }
            $hash = Get-Hash $dst
            $ours = ($hash -and $hash -eq (Get-Hash (Join-Path $CurrentDir $name))) -or
                    ($hash -and $stamp.ContainsKey($name) -and $hash -eq $stamp[$name])
            if (Test-Path -LiteralPath $backup) { Copy-Item -LiteralPath $backup $dst -Force }
            elseif ($ours) { Remove-Item -LiteralPath $dst }
        }
        Remove-IconStamp $target
    }
    Restore-ShortcutIcons $state
    Update-IconCache
    if (-not $restored -and (Test-HasBackup)) {
        # Install folder is gone: keep the backup, it's the only copy.
        Remove-DataDir -KeepBackup
        Write-Warn "$target is not there any more, so your earlier icons were kept in $BackupDir."
        return
    }
    Remove-DataDir
    Write-Done 'Original icons and shortcuts restored.'
}

# ---------------------------------------------------------------- start page

function Read-Lines([string]$Path) {
    # UTF-16 if there's a BOM, else UTF-8 (what Mozilla writes), else the ANSI code page.
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) { return [Text.Encoding]::Unicode.GetString($bytes, 2, $bytes.Length - 2) -split "`r?`n" }
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) { return [Text.Encoding]::BigEndianUnicode.GetString($bytes, 2, $bytes.Length - 2) -split "`r?`n" }
    try { $text = (New-Object Text.UTF8Encoding $false, $true).GetString($bytes) }
    catch { $text = [Text.Encoding]::GetEncoding([Globalization.CultureInfo]::CurrentCulture.TextInfo.ANSICodePage).GetString($bytes) }
    $text.TrimStart([char]0xFEFF) -split "`r?`n"
}

function Get-IniValue([string]$Path, [string]$Name) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    foreach ($line in Read-Lines $Path) {
        if ($line -match ('^' + [regex]::Escape($Name) + '=(.*)$')) { return $Matches[1].Trim() }
    }
    return $null
}

function Get-Profiles([string]$InstallDir) {
    # Portable: one profile in its own folder.
    if ($ProfileDir) {
        if (Test-Path -LiteralPath $ProfileDir -PathType Container) { $ProfileDir }
        return
    }
    # Installed Betterbird shares profiles with Thunderbird. Keep the ones whose
    # compatibility.ini LastAppDir is this install.
    $found = foreach ($app in 'Thunderbird', 'Betterbird') {
        $root = Join-Path $UserAppData $app
        $ini = Join-Path $root 'profiles.ini'
        if (-not (Test-Path -LiteralPath $ini)) { continue }
        $path = $null; $relative = $true
        foreach ($line in @(Read-Lines $ini) + '[end]') {
            if ($line -match '^\[') {
                if ($path) {
                    $full = if ($relative) { Join-Path $root ($path -replace '/', '\') } else { $path }
                    if (Test-Path -LiteralPath $full) { $full.TrimEnd('\') }
                }
                $path = $null; $relative = $true
            }
            elseif ($line -match '^Path=(.+)$') { $path = $Matches[1] }
            elseif ($line -match '^IsRelative=0') { $relative = $false }
        }
    }
    foreach ($p in @($found | Select-Object -Unique)) {
        $appDir = Get-IniValue (Join-Path $p 'compatibility.ini') 'LastAppDir'
        if ($appDir -and $appDir.TrimEnd('\') -eq $InstallDir.TrimEnd('\')) { $p }
    }
}

function Test-ProfileInUse([string]$Dir) {
    # Betterbird keeps parent.lock open, so an exclusive open fails while it runs.
    $lock = Join-Path $Dir 'parent.lock'
    if (-not (Test-Path -LiteralPath $lock)) { return $false }
    try { [IO.File]::Open($lock, 'Open', 'ReadWrite', 'None').Close(); return $false }
    catch { return $true }
}

function Read-Text([string]$Path) {
    if (Test-Path -LiteralPath $Path) { [IO.File]::ReadAllText($Path) } else { '' }
}

function Write-Text([string]$Path, [string]$Text) {
    # UTF-8 without BOM. Written to a temp file and swapped in.
    $tmp = "$Path.betterbird-icons.tmp"
    [IO.File]::WriteAllText($tmp, $Text, (New-Object Text.UTF8Encoding $false))
    if (Test-Path -LiteralPath $Path) { [IO.File]::Replace($tmp, $Path, [NullString]::Value) } else { [IO.File]::Move($tmp, $Path) }
}

function Get-StartPrefLines([string]$Text) {
    @([regex]::Matches($Text, '(?m)^user_pref\("' + $StartPrefs + '",.*$') | ForEach-Object { $_.Value.TrimEnd() })
}

function Get-StartPageProfiles {
    if (Test-Admin) { throw $NoAdminProfiles }
    $profiles = @(Get-Profiles (Get-InstallDir))
    if ($profiles.Count -eq 0) {
        if ($ProfileDir) { throw "The portable Betterbird has no profile yet at $ProfileDir. Start it once, close it, and try again." }
        throw "No profiles that Betterbird has used were found under $UserAppData."
    }
    # Betterbird rewrites prefs.js on exit: it must not be running, and no profile may be locked.
    Close-Betterbird 'to change its start page'
    if (@($profiles | Where-Object { Test-ProfileInUse $_ }).Count -gt 0) {
        throw 'A Betterbird profile is still in use. Close Betterbird and run this again.'
    }
    # One object per path; a wrapped array would bind to a [string] parameter as one string.
    foreach ($p in $profiles) { $p }
}

function Save-PreviousStartPage([string]$ProfilePath, [string]$PrefsText) {
    # Save the profile's original start page once, for Off.
    $side = Join-Path $ProfilePath $SideFile
    if (-not (Test-Path -LiteralPath $side)) {
        Write-Text -Path $side -Text (((Get-StartPrefLines $PrefsText) -join "`r`n") + "`r`n")
    }
}

function Write-ProfileStartPrefs([string]$ProfilePath, [string]$PrefsText, [string[]]$Lines) {
    $prefsJs = Join-Path $ProfilePath 'prefs.js'
    $rest = [regex]::Replace($PrefsText, '(?m)^user_pref\("' + $StartPrefs + '",.*\r?\n?', '').TrimEnd()
    $newText = if ($rest) { $rest + "`r`n" } else { '' }
    if (@($Lines).Count) { $newText += (@($Lines) -join "`r`n") + "`r`n" }
    if (Test-Path -LiteralPath $prefsJs) { Write-Text -Path "$prefsJs.betterbird-icons.bak" -Text $PrefsText }
    Write-Text -Path $prefsJs -Text $newText
}

function Write-StartPageUserJsWarning([string]$ProfilePath) {
    # user.js overrides prefs.js on every start. Don't touch it, just warn.
    if (@(Get-StartPrefLines (Read-Text (Join-Path $ProfilePath 'user.js'))).Count -gt 0) {
        Write-Warn "user.js in $(Split-Path $ProfilePath -Leaf) also sets the start page and wins over this. Remove those lines from it to use this setting."
    }
}

function Set-StartPage([string]$Value) {
    if (Test-Admin) { throw $NoAdminProfiles }
    if ($Value -ne 'Off') {
        if ($Value -match '^https?://') {
            $uri = $null
            if (-not [Uri]::TryCreate($Value, [UriKind]::Absolute, [ref]$uri)) { throw "$Value is not a valid web address." }
        }
        else {
            if (-not (Test-Path -LiteralPath $Value -PathType Leaf)) { throw "Can't find the start page file: $Value" }
            $full = (Resolve-Path -LiteralPath $Value).Path
            if ([IO.Path]::GetExtension($full) -notmatch '^\.html?$') { throw "$full is not an .html file." }
            # Build the file URI by hand: [Uri] treats # as a fragment and % as an escape.
            $slashed = ($full -replace '%', '%25' -replace '#', '%23') -replace '\\', '/'
            $uri = [Uri]$(if ($slashed.StartsWith('//')) { "file:$slashed" } else { "file:///$slashed" })
        }
        $url = $uri.AbsoluteUri
        # Goes inside a quoted pref value: reject quotes, backslashes and control chars.
        if ($url -match '[\x00-\x1f"\\]') { throw "The start page address contains characters that aren't allowed." }
    }
    $profiles = @(Get-StartPageProfiles)
    foreach ($p in $profiles) {
        $side = Join-Path $p $SideFile
        $prefsText = Read-Text (Join-Path $p 'prefs.js')
        if ($Value -eq 'Off') {
            if (-not (Test-Path -LiteralPath $side)) { continue }
            # Restore the saved start page lines as they were.
            Write-ProfileStartPrefs -ProfilePath $p -PrefsText $prefsText -Lines @(Get-StartPrefLines (Read-Text $side))
            Remove-Item -LiteralPath $side
            Write-Done "Start page set back to the previous one in $(Split-Path $p -Leaf)."
        }
        else {
            Save-PreviousStartPage -ProfilePath $p -PrefsText $prefsText
            $lines = @('user_pref("mailnews.start_page.enabled", true);', "user_pref(`"mailnews.start_page.url`", `"$url`");")
            Write-ProfileStartPrefs -ProfilePath $p -PrefsText $prefsText -Lines $lines
            Write-Done "Start page set in $(Split-Path $p -Leaf)."
        }
        Write-StartPageUserJsWarning -ProfilePath $p
    }
}

function Test-StartPageEnabled([string]$PrefsText) {
    # No line means enabled (Thunderbird's default).
    $found = [regex]::Matches($PrefsText, '(?m)^user_pref\("mailnews\.start_page\.enabled",\s*(true|false)\);\s*$')
    if ($found.Count -eq 0) { return $true }
    return $found[$found.Count - 1].Groups[1].Value -eq 'true'
}

function Get-StartPageMode {
    # on, off, mixed or unknown (elevated, or no readable profile).
    if (Test-Admin) { return 'unknown' }
    $profiles = @()
    try { $profiles = @(Get-Profiles (Get-InstallDir)) } catch { return 'unknown' }
    if ($profiles.Count -eq 0) { return 'unknown' }
    $on = 0
    foreach ($p in $profiles) {
        if (Test-StartPageEnabled (Read-Text (Join-Path $p 'prefs.js'))) { $on++ }
    }
    if ($on -eq 0) { return 'off' }
    if ($on -eq $profiles.Count) { return 'on' }
    return 'mixed'
}

function Test-PreviousStartPageSaved {
    if (Test-Admin) { return $false }
    try {
        foreach ($p in @(Get-Profiles (Get-InstallDir))) {
            if (Test-Path -LiteralPath (Join-Path $p $SideFile)) { return $true }
        }
    }
    catch { return $false }
    return $false
}

function Set-StartPageEnabled([bool]$On) {
    # Show or hide the start page; the URL is kept.
    $profiles = @(Get-StartPageProfiles)
    $flag = if ($On) { 'true' } else { 'false' }
    foreach ($p in $profiles) {
        $prefsText = Read-Text (Join-Path $p 'prefs.js')
        Save-PreviousStartPage -ProfilePath $p -PrefsText $prefsText
        $urlLines = @(Get-StartPrefLines $prefsText | Where-Object { $_ -match 'start_page\.url' })
        $lines = @("user_pref(`"mailnews.start_page.enabled`", $flag);") + @($urlLines)
        Write-ProfileStartPrefs -ProfilePath $p -PrefsText $prefsText -Lines $lines
        $word = if ($On) { 'on' } else { 'off' }
        Write-Done "Start page turned $word in $(Split-Path $p -Leaf)."
        Write-StartPageUserJsWarning -ProfilePath $p
    }
}

function Get-StartPageStatus([string]$InstallDir) {
    foreach ($p in @(Get-Profiles $InstallDir)) {
        $m = [regex]::Match((Read-Text (Join-Path $p 'prefs.js')), '(?m)^user_pref\("mailnews\.start_page\.url", "([^"]*)"')
        $value = if ($m.Success) { $m.Groups[1].Value } else { '(Betterbird default)' }
        if (Test-Path -LiteralPath (Join-Path $p $SideFile)) { $value += '   (set by this script)' }
        if ($m.Success -and $m.Groups[1].Value -like 'file:*') {
            $uri = $null
            if ([Uri]::TryCreate($m.Groups[1].Value, [UriKind]::Absolute, [ref]$uri) -and -not (Test-Path -LiteralPath $uri.LocalPath)) {
                $value += '   - FILE NOT FOUND'
            }
        }
        if (@(Get-StartPrefLines (Read-Text (Join-Path $p 'user.js'))).Count -gt 0) { $value += '   - overridden by user.js' }
        $value += $(if (Test-StartPageEnabled (Read-Text (Join-Path $p 'prefs.js'))) { '   (on)' } else { '   (off)' })
        "    {0,-28} {1}" -f (Split-Path $p -Leaf), $value
    }
}

# ---------------------------------------------------------------- list, status, manual, menu

function Test-PopupPng([byte[]]$Bytes, [int]$Size) {
    # PNG at the size the popup expects.
    if ($Bytes.Length -lt 24) { return $false }
    $sig = [byte[]](0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A)
    for ($i = 0; $i -lt 8; $i++) { if ($Bytes[$i] -ne $sig[$i]) { return $false } }
    $width = ([int]$Bytes[16] -shl 24) -bor ([int]$Bytes[17] -shl 16) -bor ([int]$Bytes[18] -shl 8) -bor [int]$Bytes[19]
    $height = ([int]$Bytes[20] -shl 24) -bor ([int]$Bytes[21] -shl 16) -bor ([int]$Bytes[22] -shl 8) -bor [int]$Bytes[23]
    $width -eq $Size -and $height -eq $Size
}

function Get-BytesHash([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '') }
    finally { $sha.Dispose() }
}

function Get-PopupBytes([string]$Name) {
    if (-not $PopupChoices.Contains($Name)) { throw "There is no mail popup called '$Name'." }
    $dir = Join-Path $PSScriptRoot "icons\popup\$Name"
    $map = @{}
    foreach ($jarName in $PopupFiles.Keys) {
        $info = $PopupFiles[$jarName]
        $path = Join-Path $dir $info.File
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "The mail popup '$Name' is missing $($info.File)." }
        $bytes = [IO.File]::ReadAllBytes($path)
        if (-not (Test-PopupPng -Bytes $bytes -Size $info.Size)) { throw "The mail popup '$Name' has a damaged $($info.File)." }
        $map[$jarName] = $bytes
    }
    $map
}

function Initialize-StoredJar {
    # Rewrite a zip with every entry stored, like Betterbird's omni.ja.
    if ('BetterbirdIcons.StoredJar' -as [type]) { return }
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    # pwsh needs the reference assemblies for Add-Type; Windows PowerShell only needs the
    # zip ones.
    if ($PSVersionTable.PSVersion.Major -ge 6) {
        $refDir = Join-Path $PSHome 'ref'
        $refs = @(
            'System.Runtime.dll', 'System.Collections.dll', 'System.Collections.NonGeneric.dll',
            'System.IO.dll', 'System.IO.Compression.dll', 'System.IO.Compression.ZipFile.dll',
            'System.Reflection.dll'
        ) | ForEach-Object { Join-Path $refDir $_ }
    }
    else {
        $refs = @(
            ([IO.Compression.ZipArchive].Assembly.Location),
            ([IO.Compression.ZipFile].Assembly.Location)
        ) | Select-Object -Unique
    }
    $code = @'
using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Text;

namespace BetterbirdIcons {
    public static class StoredJar {
        static readonly uint[] Table = BuildTable();

        public static void Write(string sourcePath, string destPath, IDictionary replacements) {
            var items = new List<Item>();
            using (var source = ZipFile.OpenRead(sourcePath))
            using (var stream = new FileStream(destPath, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            using (var writer = new BinaryWriter(stream)) {
                foreach (ZipArchiveEntry entry in source.Entries) {
                    bool replaced = replacements != null && replacements.Contains(entry.FullName);
                    byte[] data = replaced ? Bytes(replacements[entry.FullName]) : ReadAll(entry);
                    if (data.LongLength > uint.MaxValue)
                        throw new InvalidDataException("A file in the picture archive is too large.");
                    uint crc = Crc32(data);
                    if (!replaced && ReadCrc(entry) != crc)
                        throw new InvalidDataException("The picture archive could not be read whole.");
                    if (stream.Position > uint.MaxValue)
                        throw new InvalidDataException("The picture archive is too large.");
                    var item = new Item();
                    item.Name = entry.FullName;
                    item.NameBytes = Encoding.UTF8.GetBytes(entry.FullName);
                    if (item.NameBytes.Length > ushort.MaxValue)
                        throw new InvalidDataException("A file name in the picture archive is too long.");
                    item.Flags = 0;
                    for (int i = 0; i < item.NameBytes.Length; i++) {
                        if (item.NameBytes[i] >= 128) { item.Flags = 0x800; break; }
                    }
                    item.Crc = crc;
                    item.Size = (uint)data.LongLength;
                    DateTime local = entry.LastWriteTime.LocalDateTime;
                    if (local.Year < 1980) local = new DateTime(1980, 1, 1);
                    item.DosTime = (ushort)((local.Hour << 11) | (local.Minute << 5) | (local.Second / 2));
                    item.DosDate = (ushort)(((local.Year - 1980) << 9) | (local.Month << 5) | local.Day);
                    item.Attr = unchecked((uint)entry.ExternalAttributes);
                    item.LocalOffset = (uint)stream.Position;
                    WriteLocal(writer, item, data);
                    items.Add(item);
                }
                if (items.Count > ushort.MaxValue)
                    throw new InvalidDataException("The picture archive has too many files.");
                if (stream.Position > uint.MaxValue)
                    throw new InvalidDataException("The picture archive is too large.");
                uint cdOffset = (uint)stream.Position;
                for (int i = 0; i < items.Count; i++) WriteCentral(writer, items[i]);
                uint cdSize = (uint)stream.Position - cdOffset;
                WriteEnd(writer, (ushort)items.Count, cdSize, cdOffset);
                writer.Flush();
            }
            Verify(destPath, items);
        }

        static byte[] Bytes(object value) {
            byte[] data = value as byte[];
            if (data == null) throw new InvalidDataException("A replacement picture is missing.");
            return data;
        }

        static byte[] ReadAll(ZipArchiveEntry entry) {
            using (Stream input = entry.Open())
            using (var memory = new MemoryStream()) {
                input.CopyTo(memory);
                return memory.ToArray();
            }
        }

        static void Verify(string path, List<Item> items) {
            using (ZipArchive zip = ZipFile.OpenRead(path)) {
                if (zip.Entries.Count != items.Count)
                    throw new InvalidDataException("The new picture archive is incomplete.");
                for (int i = 0; i < items.Count; i++) {
                    ZipArchiveEntry entry = zip.Entries[i];
                    if (entry.FullName != items[i].Name || entry.Length != items[i].Size || ReadCrc(entry) != items[i].Crc)
                        throw new InvalidDataException("The new picture archive changed a file.");
                    var property = entry.GetType().GetProperty("CompressionMethod", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
                    if (property == null)
                        throw new InvalidDataException("Could not read the picture archive's metadata on this .NET version.");
                    object method = property.GetValue(entry, null);
                    if (method == null || method.ToString() != "Stored")
                        throw new InvalidDataException("The new picture archive is not stored.");
                }
            }
        }

        static uint ReadCrc(ZipArchiveEntry entry) {
            var field = entry.GetType().GetField("_crc32", BindingFlags.Instance | BindingFlags.NonPublic);
            if (field == null)
                throw new InvalidDataException("Could not read the picture archive's metadata on this .NET version.");
            return (uint)field.GetValue(entry);
        }

        static void WriteLocal(BinaryWriter writer, Item item, byte[] data) {
            writer.Write(0x04034b50);
            writer.Write((ushort)20);
            writer.Write(item.Flags);
            writer.Write((ushort)0);
            writer.Write(item.DosTime);
            writer.Write(item.DosDate);
            writer.Write(item.Crc);
            writer.Write(item.Size);
            writer.Write(item.Size);
            writer.Write((ushort)item.NameBytes.Length);
            writer.Write((ushort)0);
            writer.Write(item.NameBytes);
            writer.Write(data);
        }

        static void WriteCentral(BinaryWriter writer, Item item) {
            writer.Write(0x02014b50);
            writer.Write((ushort)0x0314);
            writer.Write((ushort)20);
            writer.Write(item.Flags);
            writer.Write((ushort)0);
            writer.Write(item.DosTime);
            writer.Write(item.DosDate);
            writer.Write(item.Crc);
            writer.Write(item.Size);
            writer.Write(item.Size);
            writer.Write((ushort)item.NameBytes.Length);
            writer.Write((ushort)0);
            writer.Write((ushort)0);
            writer.Write((ushort)0);
            writer.Write((ushort)0);
            writer.Write(item.Attr);
            writer.Write(item.LocalOffset);
            writer.Write(item.NameBytes);
        }

        static void WriteEnd(BinaryWriter writer, ushort count, uint size, uint offset) {
            writer.Write(0x06054b50);
            writer.Write((ushort)0);
            writer.Write((ushort)0);
            writer.Write(count);
            writer.Write(count);
            writer.Write(size);
            writer.Write(offset);
            writer.Write((ushort)0);
        }

        static uint[] BuildTable() {
            var table = new uint[256];
            for (uint i = 0; i < 256; i++) {
                uint c = i;
                for (int k = 0; k < 8; k++)
                    c = (c & 1) != 0 ? 0xedb88320u ^ (c >> 1) : c >> 1;
                table[i] = c;
            }
            return table;
        }

        static uint Crc32(byte[] data) {
            uint crc = 0xffffffffu;
            for (int i = 0; i < data.Length; i++)
                crc = Table[(crc ^ data[i]) & 0xff] ^ (crc >> 8);
            return crc ^ 0xffffffffu;
        }

        sealed class Item {
            public string Name;
            public byte[] NameBytes;
            public ushort Flags;
            public uint Crc;
            public uint Size;
            public ushort DosTime;
            public ushort DosDate;
            public uint Attr;
            public uint LocalOffset;
        }
    }
}
'@
    Add-Type -TypeDefinition $code -ReferencedAssemblies $refs
}

function Get-MailPopupName {
    # Which known popup image omni.ja has, or nothing.
    $omni = Join-Path (Get-InstallDir) 'omni.ja'
    if (-not (Test-Path -LiteralPath $omni -PathType Leaf) -or (Test-ReparsePoint $omni)) { return $null }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($omni)
    try {
        $found = @{}
        foreach ($jarName in $PopupFiles.Keys) {
            $entry = $zip.GetEntry($jarName)
            if (-not $entry) { return $null }
            $stream = $entry.Open()
            try {
                $memory = New-Object IO.MemoryStream
                $stream.CopyTo($memory)
                $found[$jarName] = Get-BytesHash -Bytes $memory.ToArray()
            }
            finally { $stream.Dispose() }
        }
    }
    finally { $zip.Dispose() }
    foreach ($name in $PopupChoices.Keys) {
        $bytes = Get-PopupBytes -Name $name
        $match = $true
        foreach ($jarName in $PopupFiles.Keys) {
            if ($found[$jarName] -ne (Get-BytesHash -Bytes $bytes[$jarName])) { $match = $false; break }
        }
        if ($match) { return $name }
    }
    $null
}

function Test-FileInUse($ErrorRecord) {
    $e = $ErrorRecord.Exception
    while ($e) {
        if ($e.HResult -eq -2147024864) { return $true }   # sharing violation
        if ($e -is [ComponentModel.Win32Exception] -and $e.NativeErrorCode -eq 32) { return $true }
        $e = $e.InnerException
    }
    $false
}

function Set-MailPopup([string]$Name) {
    # Replace the two popup images in omni.ja; copy everything else as is.
    $replacements = Get-PopupBytes -Name $Name
    $dir = Get-InstallDir
    if (Test-ReparsePoint $dir) { throw "$dir is a link to another folder; not changing it." }
    $omni = Join-Path $dir 'omni.ja'
    if (-not (Test-Path -LiteralPath $omni -PathType Leaf)) { throw "Can't find Betterbird's picture file in $dir." }
    if (Test-ReparsePoint $omni) { throw "$omni is a link; not changing it." }
    $tmp = Join-Path $dir 'omni.ja.betterbird-icons.tmp'
    if (Test-ReparsePoint $tmp) { throw "$tmp is a link; not changing it." }
    $sddl = $null
    $wasReadOnly = $false
    try {
        if ((Get-MailPopupName) -eq $Name) {
            Write-Done "Mail popup is already $Name."
            return
        }
        Assert-MailPopupEntries -Omni $omni
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force }
        $sddl = (Get-Acl -LiteralPath $omni).Sddl
        Initialize-StoredJar
        [BetterbirdIcons.StoredJar]::Write($omni, $tmp, $replacements)
        $file = Get-Item -LiteralPath $omni
        $wasReadOnly = $file.IsReadOnly
        if ($wasReadOnly) { $file.IsReadOnly = $false }
        [IO.File]::Replace($tmp, $omni, [NullString]::Value)
        Write-Done "Mail popup set to $Name."
        Write-Warn 'Quit Betterbird and open it again to see it. A Betterbird update puts the original bird back.'
    }
    catch {
        if (Test-FileInUse -ErrorRecord $_) { throw 'Betterbird is using that picture. Quit it completely, including the tray icon, then try again.' }
        throw
    }
    finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
        if ($sddl) {
            try {
                $acl = Get-Acl -LiteralPath $omni
                if ($acl.Sddl -ne $sddl) {
                    $acl.SetSecurityDescriptorSddlForm($sddl)
                    Set-Acl -LiteralPath $omni -AclObject $acl
                }
            }
            catch { Write-Warn 'The mail popup was changed, but its permissions could not be put back.' }
        }
        if ($wasReadOnly -and (Test-Path -LiteralPath $omni)) {
            try { (Get-Item -LiteralPath $omni).IsReadOnly = $true }
            catch { Write-Warn 'The mail popup was changed, but it could not be marked read-only again.' }
        }
    }
}

function Assert-MailPopupEntries([string]$Omni) {
    # Stop if either image is missing (renamed in a newer Betterbird?).
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($Omni)
    try {
        foreach ($jarName in $PopupFiles.Keys) {
            if (-not $zip.GetEntry($jarName)) {
                throw 'This Betterbird build does not have the expected picture files (icon64.png / icon128.png); the mail popup cannot be changed on this version.'
            }
        }
    }
    finally { $zip.Dispose() }
}


function Get-MenuIconSets([string]$Kind = 'all') {
    # window: sets usable as the main icon. newmail: sets with a new-mail icon.
    foreach ($name in $SetNotes.Keys) {
        $dir = Join-Path $PSScriptRoot "icons\$name"
        if (-not (Test-Path -LiteralPath $dir)) { continue }
        $window = Test-Path -LiteralPath (Join-Path $dir 'messengerWindow.ico')
        $mail = Test-Path -LiteralPath (Join-Path $dir 'newmail.ico')
        if ($Kind -eq 'window' -and -not $window) { continue }
        if ($Kind -eq 'newmail' -and -not $mail) { continue }
        $name
    }
}

function Resolve-MenuIcon([string]$Answer, [string]$Kind = 'all') {
    # List number, set name or path.
    $names = @(Get-MenuIconSets $Kind)
    if ($Answer -match '^\d+$') {
        $n = [int]$Answer
        if ($n -ge 1 -and $n -le $names.Count) { return $names[$n - 1] }
        throw "There is no icon number $Answer."
    }
    $Answer
}

function Open-IconPage {
    # Open the icon preview page.
    $page = Join-Path $PSScriptRoot 'images\choose.html'
    if (-not (Test-Path -LiteralPath $page)) { return }
    Start-Process ([Uri](Resolve-Path -LiteralPath $page).Path).AbsoluteUri
}

function Show-List([string]$Kind = 'all') {
    Write-Host ''
    Write-Host $(if ($Kind -eq 'newmail') { '  New-mail icons:' } else { '  Icon sets:' })
    $i = 1
    foreach ($name in (Get-MenuIconSets $Kind)) {
        $note = $SetNotes[$name]
        if ($name -eq 'blue') { $note = "yours - $note" }
        Write-Host ('    {0}) {1,-11} {2}' -f $i, $name, $note)
        $i++
    }
}

function Show-Status {
    Write-Host ''
    $dir = $null
    $kind = if ($Mode -eq 'system') { 'installed for all users' } elseif ($Launcher) { 'portable' } else { 'in your own folder' }
    try { $dir = Get-InstallDir; Write-Host "  Betterbird:     $dir   ($kind)" } catch { Write-Warn $_.Exception.Message }
    if (-not (Test-Path -LiteralPath $DataDir)) { Write-Host '  Icon:           original (not changed by this script)' }
    elseif (-not (Test-DataDirTrusted)) { Write-Warn "Icon:           unknown - $DataDir was not made by this tool" }
    else {
        $state = Read-State
        if ($state -and $state.Icon) {
            Write-Host "  Icon:           $($state.Icon)   (new-mail icon: $($state.NewMail))"
            Write-Host "  Shortcuts:      $(@($state.Shortcuts).Count) using the icon"
        }
        else { Write-Host '  Icon:           original (not changed by this script)' }
    }
    if ($dir) {
        $popupText = 'not changed by this tool'
        try {
            $popup = Get-MailPopupName
            if ($popup) { $popupText = $popup }
        }
        catch { $popupText = 'not changed by this tool' }
        Write-Host "  Mail popup:     $popupText"
    }
    if ($dir -and (Test-Admin)) { Write-Host '  Start page:     run this without administrator rights to see it' }
    elseif ($dir) {
        Write-Host '  Start page:'
        Get-StartPageStatus $dir | ForEach-Object { Write-Host $_ }
    }
}

function Show-Manual {
    $dir = Join-Path $env:ProgramFiles 'Betterbird'
    try { $dir = Get-InstallDir } catch { $null = $_ }
    $target = Join-Path $dir 'chrome\icons\default'
    $icons = Join-Path $PSScriptRoot 'icons'
    $exe = if ($Launcher) { $Launcher } else { Join-Path $dir 'betterbird.exe' }
    $copyStep = if ($Mode -eq 'own') {
        @('    4. Copy the new icon into that folder, named messengerWindow.ico. For the new-mail',
          '       notification icon, also copy one there named newmail.ico.')
    }
    else {
        @('    4. Copy the new icon into that folder, named messengerWindow.ico, and allow the administrator',
          '       prompt. For the new-mail notification icon, also copy one there named newmail.ico.')
    }
    @(
        ''
        '  Doing it by hand'
        '  ================'
        ''
        '  Change the icon'
        '    1. Close Betterbird.'
        "    2. In File Explorer, open:  $target   (create the folder if it is not there)"
        '    3. If there is already a messengerWindow.ico or newmail.ico there, copy it somewhere safe.'
        '       (A fresh install has neither: Betterbird''s own icons are built into the program.)'
        $copyStep
        "       The icons in this download are in:  $icons\<set name>\"
        '    5. Start Betterbird.'
        '    Betterbird updates leave these two files alone, so your icon stays.'
        ''
        '  Change the icon of a shortcut'
        '    - Desktop: right-click the Betterbird shortcut, Properties, Change Icon, Browse to the .ico file.'
        '    - Start menu: right-click Betterbird, Open file location, then do the same to the shortcut there.'
        '    - Taskbar: right-click the Betterbird button, right-click "Betterbird" in the list that opens,'
        '      Properties, Change Icon. The new icon shows after you sign out and back in.'
        ''
        '  Start page'
        '    1. In Betterbird, open the menu (three lines, top right), Settings, General.'
        '    2. In the Start Page section, tick the option to show the Start Page when Betterbird launches,'
        '       and in Location enter a web address or a file, for example  file:///C:/Docs/manual.html'
        '    3. To go back, use Restore Default there, or untick the option.'
        ''
        '  Mail popup'
        '    The large popup for a new message uses a picture built into Betterbird.'
        '    In this tool, choose Change the mail popup. 1 is yours. 2 (factory) puts'
        '    Betterbird''s own bird back. Quit Betterbird and open it again.'
        '    A Betterbird update puts the original bird back, so choose it again afterwards.'
        '    Restoring the original icons does not change this popup.'
        ''
        '  Put the original icon back'
        '    1. Close Betterbird.'
        "    2. Delete messengerWindow.ico and newmail.ico from  $target"
        '       (or copy back the ones you saved in step 3 above).'
        "    3. For each shortcut: Properties, Change Icon, Browse to  $exe  and pick its icon."
        ''
    ) | ForEach-Object { Write-Host $_ }
}

function Show-Menu {
    # Runs as the user; in system mode only the icon actions elevate.
    # Each screen clears the previous one.
    while ($true) {
        Clear-Host
        $ask = if ($Mode -eq 'system' -and -not (Test-Admin)) { '(asks for administrator permission)' } else { '' }
        $where = if ($Mode -eq 'system') { 'installed for all users' } elseif ($Launcher) { "portable, $AppDir" } else { $AppDir }
        Write-Host ''
        Write-Host "  Betterbird Icons   - Betterbird $where" -ForegroundColor Cyan
        if ($script:MenuNotice) {
            foreach ($note in @($script:MenuNotice)) {
                if ($note -is [string]) { Write-Host "  $note" -ForegroundColor Green }
                else {
                    $color = switch ($note.Kind) { 'W' { 'Yellow' } 'D' { 'Green' } default { 'Gray' } }
                    Write-Host "  $($note.Text)" -ForegroundColor $color
                }
            }
            $script:MenuNotice = $null
        }
        Write-Host "  1) Change icon                 $ask"
        Write-Host '  2) Start page'
        Write-Host "  3) Restore original icons      $ask"
        Write-Host '  4) Status'
        Write-Host '  5) Manual instructions (do it by hand)'
        Write-Host "  6) Change the new-mail icon    $ask"
        Write-Host '  7) See the icons'
        Write-Host "  8) Change the dot colour       $ask"
        Write-Host "  9) Change the mail popup       $ask"
        Write-Host '  P) Use a portable Betterbird, or one in your own folder'
        Write-Host '  Q) Quit'
        $choice = Read-Host '  Choose'
        $pause = $false
        try {
            switch ($choice) {
                '1' {
                    Clear-Host
                    Show-List 'window'
                    $answer = "$(Read-Host '  Number, or the path to your own .ico file')".Trim().Trim('"')
                    if (-not $answer) { continue }
                    $name = Resolve-MenuIcon $answer 'window'
                    # Also switches to the set's new-mail icon.
                    $asks = $Mode -eq 'system' -and -not (Test-Admin)
                    Show-Working "Changing the icon to $name." $asks
                    $script:Notes = @()
                    $changed = $false
                    if (-not $asks) { Install-Icon $name $null; $changed = $true }
                    else { $changed = Invoke-Elevated @{ Icon = $name } }
                    Set-MenuResult $changed "Changed the icon to $name."
                }
                { $_ -match '^[Pp]$' } {
                    Clear-Host
                    $folder = "$(Read-Host '  Betterbird folder (the one with BetterbirdLauncher.exe or betterbird.exe)')".Trim().Trim('"')
                    if (-not $folder) { continue }
                    Enter-OwnFolderMode $folder
                    if (-not (Confirm-StandardUser @{ Portable = $folder })) { return }
                }
                '2' {
                    Clear-Host
                    Write-Host ''
                    Write-Host '  Start page:'
                    switch (Get-StartPageMode) {
                        'on'    { Write-Host '  It is on.' }
                        'off'   { Write-Host '  It is off.' }
                        'mixed' { Write-Host '  It is on in some profiles and off in others.' }
                    }
                    Write-Host '    1) Set a page'
                    Write-Host '    2) Turn it on'
                    Write-Host '    3) Turn it off'
                    $saved = Test-PreviousStartPageSaved
                    if ($saved) { Write-Host '    4) Put the previous page back' }
                    $answer = "$(Read-Host '  Number')".Trim()
                    if (-not $answer) { continue }
                    if ($answer -eq '1') {
                        $page = "$(Read-Host '  Path to the .html file (or an https:// address)')".Trim().Trim('"')
                        if (-not $page) { continue }
                        Set-StartPage $page
                        $pause = $true
                    }
                    elseif ($answer -eq '2') { Set-StartPageEnabled -On $true; $pause = $true }
                    elseif ($answer -eq '3') { Set-StartPageEnabled -On $false; $pause = $true }
                    elseif ($saved -and $answer -eq '4') { Set-StartPage 'Off'; $pause = $true }
                    else { throw "There is no start page choice $answer." }
                }
                '3' {
                    $asks = $Mode -eq 'system' -and -not (Test-Admin)
                    Show-Working 'Restoring the original icons.' $asks
                    $script:Notes = @()
                    $changed = $false
                    if (-not $asks) { Restore-Originals; $changed = $true }
                    else { $changed = Invoke-Elevated @{ Restore = $true } }
                    Set-MenuResult $changed 'Restored the original icons.'
                }
                '4' { Clear-Host; Show-Status; $pause = $true }
                '5' { Clear-Host; Show-Manual; $pause = $true }
                '6' {
                    Clear-Host
                    $current = $null
                    if (Test-DataDirTrusted) { $state = Read-State; if ($state -and $state.Icon) { $current = [string]$state.Icon } }
                    if (-not $current) { throw 'Choose an icon first (option 1). The new-mail icon is updated with that set.' }
                    Show-List 'newmail'
                    $answer = "$(Read-Host '  Number, or none for Betterbird''s own')".Trim().Trim('"')
                    if (-not $answer) { continue }
                    $mail = if ($answer -eq 'none') { 'none' } else { Resolve-MenuIcon $answer 'newmail' }
                    $asks = $Mode -eq 'system' -and -not (Test-Admin)
                    Show-Working 'Changing the new-mail icon.' $asks
                    $script:Notes = @()
                    $changed = $false
                    if (-not $asks) { Install-Icon $current $mail; $changed = $true }
                    else { $changed = Invoke-Elevated @{ Icon = $current; NewMail = $mail } }
                    Set-MenuResult $changed 'Changed the new-mail icon.'
                }
                '7' { Open-IconPage; continue }
                '8' {
                    Clear-Host
                    $current = $null
                    if (Test-DataDirTrusted) { $state = Read-State; if ($state -and $state.Icon) { $current = [string]$state.Icon } }
                    if (-not $current) { throw 'Choose an icon first (option 1).' }
                    $window = Get-WindowIconPath $current
                    if (-not $window) { throw 'This icon has no window picture to put a dot on.' }
                    $marked = Get-DotColourName (Get-CurrentNewMailPath $current)
                    Write-Host ''
                    Write-Host '  Dot colour:'
                    if (-not $marked) { Write-Host "  Current dot: the set's own colour" }
                    $n = 1
                    foreach ($colourName in $DotColours.Keys) {
                        $mark = if ($colourName -eq $marked) { '    current' } else { '' }
                        Write-Host "    $n) $colourName$mark"
                        $n++
                    }
                    $answer = "$(Read-Host '  Number')".Trim()
                    if (-not $answer) { continue }
                    $colourNames = @($DotColours.Keys)
                    if ($answer -notmatch '^\d+$' -or [int]$answer -lt 1 -or [int]$answer -gt $colourNames.Count) { throw "There is no dot colour $answer." }
                    $picked = $colourNames[[int]$answer - 1]
                    $asks = $Mode -eq 'system' -and -not (Test-Admin)
                    Show-Working "Changing the dot to $picked." $asks
                    $script:Notes = @()
                    if (-not $env:LOCALAPPDATA) { throw 'The LocalAppData folder is not set on this computer.' }
                    $out = Join-Path $env:LOCALAPPDATA 'BetterbirdIcons\dot-newmail.ico'
                    New-Item -ItemType Directory -Force -Path (Split-Path $out) | Out-Null
                    Add-IconDot -Source $window -Dest $out -Hex $DotColours[$picked]
                    $changed = $false
                    if (-not $asks) { Install-Icon $current $out; $changed = $true }
                    else { $changed = Invoke-Elevated @{ Icon = $current; NewMail = $out } }
                    Set-MenuResult $changed "Changed the dot to $picked."
                }
                '9' {
                    Clear-Host
                    $marked = $null
                    try { $marked = Get-MailPopupName } catch { $marked = $null }
                    Write-Host ''
                    Write-Host '  Mail popup:'
                    $n = 1
                    foreach ($popupName in $PopupChoices.Keys) {
                        $mark = if ($popupName -eq $marked) { '    current' } else { '' }
                        Write-Host ("    {0}) {1,-10} {2}{3}" -f $n, $popupName, $PopupChoices[$popupName], $mark)
                        $n++
                    }
                    $answer = "$(Read-Host '  Number')".Trim()
                    if (-not $answer) { continue }
                    $popupNames = @($PopupChoices.Keys)
                    if ($answer -notmatch '^\d+$' -or [int]$answer -lt 1 -or [int]$answer -gt $popupNames.Count) { throw "There is no mail popup $answer." }
                    $picked = $popupNames[[int]$answer - 1]
                    $asks = $Mode -eq 'system' -and -not (Test-Admin)
                    Show-Working "Changing the mail popup to $picked." $asks
                    $script:Notes = @()
                    $changed = $false
                    if (-not $asks) { Set-MailPopup -Name $picked; $changed = $true }
                    else { $changed = Invoke-Elevated @{ MailPopup = $picked } }
                    Set-MenuResult $changed "Changed the mail popup to $picked."
                }
                { $_ -match '^[Qq]$' } { return }
            }
        }
        catch {
            Write-Warn $_.Exception.Message
            $pause = $true
        }
        if ($pause) {
            Read-Host '  Press Enter to return to the menu' | Out-Null
            $script:Notes = @()
        }
    }
}

function Show-Working([string]$Text, [bool]$AsksAdmin) {
    # Clear the list; the main menu redraws afterwards.
    Clear-Host
    Write-Host ''
    Write-Host "  $Text"
    if ($AsksAdmin) { Write-Host '  Windows will ask for administrator permission.' }
}

function Set-MenuResult([bool]$Ok, [string]$Fallback) {
    if ($script:Notes.Count -gt 0) {
        $script:MenuNotice = @($script:Notes)
        $script:Notes = @()
        return
    }
    if ($Ok -and $Fallback) {
        $script:MenuNotice = @([pscustomobject]@{ Kind = 'D'; Text = $Fallback })
    }
}

function Show-CollectedNotes {
    # Command line: the elevated window has closed, so print its result here.
    foreach ($note in @($script:Notes)) {
        if ($note.Shown) { continue }
        $color = switch ($note.Kind) { 'W' { 'Yellow' } 'D' { 'Green' } default { 'Gray' } }
        Write-Host "  $($note.Text)" -ForegroundColor $color
    }
    $script:Notes = @()
}

function Invoke-Tool($Options) {
    # Runs the requested actions once the target Betterbird is known. Throws on error.
    $o = @{}
    foreach ($k in $Options.Keys) { $o[$k] = $Options[$k] }
    $iconValue = [string]$o['Icon']; $mailValue = [string]$o['NewMail']; $pageValue = [string]$o['StartPage']
    $popupValue = [string]$o['MailPopup']
    $doRestore = [bool]$o['Restore']
    $menu = -not ($iconValue -or $mailValue -or $pageValue -or $popupValue -or $doRestore -or $o['List'] -or $o['Status'] -or $o['Manual'])
    if ($o['Manual']) { Show-Manual; return }
    if ($o['Status']) { Show-Status; return }

    if ($Mode -eq 'own') {
        # No admin needed; if elevated, offer to restart de-elevated.
        if (-not (Confirm-StandardUser $Options)) { return }
    }
    elseif (($iconValue -or $mailValue -or $doRestore -or $popupValue) -and -not (Test-Admin)) {
        # Only icon actions need admin; the start page runs here, unelevated.
        $elevatedOk = Invoke-Elevated (Get-ElevatedOptions $Options)
        Show-CollectedNotes
        if (-not $elevatedOk) { $script:ToolExit = 1 }
        if (-not $pageValue) { return }
        $iconValue = ''; $mailValue = ''; $doRestore = $false; $popupValue = ''
    }

    # Checked before changing anything.
    if ($pageValue -and (Test-Admin)) { throw $NoAdminProfiles }
    if ($Mode -eq 'system' -and (Test-Admin)) { Remove-OldReapplyTask }
    if ($menu) { Show-Menu; return }
    if ($mailValue -and -not $iconValue) {
        $state = if (Test-DataDirTrusted) { Read-State } else { $null }
        if (-not ($state -and $state.Icon)) { throw 'Choose an icon with -Icon as well.' }
        $iconValue = $state.Icon
    }
    if ($doRestore) { Restore-Originals }
    if ($iconValue) { Install-Icon $iconValue $mailValue }
    if ($popupValue) { Set-MailPopup -Name $popupValue }
    if ($pageValue) { Set-StartPage $pageValue }
}

# ---------------------------------------------------------------- main

# Dot-sourced by the tests: define the functions only.
if ($MyInvocation.InvocationName -eq '.') { return }

$script:ToolExit = 0
try {
    $menuMode = -not ($Icon -or $NewMail -or $MailPopup -or $StartPage -or $Restore -or $List -or $Status -or $Manual)
    $handled = $false
    if ($List) { Show-List; $handled = $true }

    if (-not $handled) {
        try {
            if ($Portable) { Enter-OwnFolderMode $Portable }
            elseif (-not ($Restore -or $Status -or $Manual)) {
                # Look for a system-wide install before elevating. -Restore is allowed without one.
                try { [void](Get-InstallDir) }
                catch {
                    if (-not ($menuMode -and (Test-Interactive))) { throw }
                    Write-Warn $_.Exception.Message
                    $folder = "$(Read-Host '  Betterbird folder for a portable or own-folder Betterbird (Enter for the manual instructions)')".Trim().Trim('"')
                    if (-not $folder) { Show-Manual; Read-Host '  Press Enter to close' | Out-Null; $handled = $true }
                    else {
                        Enter-OwnFolderMode $folder
                        $PSBoundParameters['Portable'] = $folder
                    }
                }
            }
        }
        catch {
            Write-Warn $_.Exception.Message
            $script:ToolExit = 1
            $handled = $true
        }
    }

    if (-not $handled) {
        try { Invoke-Tool $PSBoundParameters }
        catch {
            Write-Warn $_.Exception.Message
            $script:ToolExit = 1
        }
    }
}
finally {
    $wrote = $false
    if ($ExitFile) { $wrote = Write-ExitFile $ExitFile $script:ToolExit }
    # No result file: this is the visible window, so leave the error on screen.
    if (-not $wrote -and $Relaunched -and $script:ToolExit -ne 0) { Read-Host '  Press Enter to close' | Out-Null }
}
exit $script:ToolExit

