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
    -MailPopup <set> changes it to that set's bird. -MailPopup factory puts Betterbird's own bird back.
    Quit Betterbird and open it again to see it. A Betterbird update puts that original bird back.

    Betterbird reads its window, taskbar and system tray icon when it starts, so close it before a
    change (the menu offers to, and starts it again afterwards) or restart it afterwards.
    Each icon change gives the shortcuts a new icon file name, so the desktop and taskbar shortcuts
    update by themselves. -RestartExplorer restarts Explorer if one still shows the old icon (open
    File Explorer windows close); it is never done as administrator.

    Run with no options for a simple menu. Options can be combined; they run in the order
    Restore, FactoryReset, MailPopup, Icon, StartPage.

    Works with Betterbird installed for all users (system-wide) in Program Files, which needs
    administrator rights, and with a portable Betterbird or one installed in your own folder
    (-Portable), which doesn't. -Manual shows how to make the same changes by hand.

.PARAMETER Icon
    An icon set name (see -List) or the path to your own .ico file. Leave it out with -NewMail
    to change only the new-mail icon and keep the window icon as it is.

.PARAMETER NewMail
    The new-mail notification icon: a set name, the path to an .ico file, "none" for
    Betterbird's built-in one, or "keep" to leave the one in place. Defaults to the chosen set's
    own new-mail icon. With your own .ico (or a set that has none), the new-mail icon you had
    before using this tool comes back, or Betterbird's built-in one if you had none.

.PARAMETER MailPopup
    The picture on the large new-mail popup: an icon set name (blue, bb, uk and so on), the path to
    an .ico file, or "factory" for Betterbird's own bird. "yours" is another name for blue.
    Only blue has a ready-made picture; for the others it is made from the set's icon.

.PARAMETER RestartExplorer
    Restart Explorer once the change is done, if the desktop or taskbar still show the old icon.
    Open File Explorer windows close. Never done as administrator.

.PARAMETER RestartBetterbird
    Close Betterbird before the change (it asks first, or closes it at once with -Force) and start
    it again afterwards, so its window, taskbar button and system tray icon show the new picture.
    On its own it just restarts Betterbird. Never done as administrator: a Betterbird started from an
    administrator window would run as administrator.

.PARAMETER StartPage
    The path to an .html file (or an http/https address) to show as Betterbird's start page,
    or "Off" to go back to the previous start page. Only profiles Betterbird has used are changed.
    This is done with your normal rights, never as administrator.

.PARAMETER Restore
    Put back the icons and shortcuts you had before this script changed them, and remove
    everything it installed. (The mail popup and start page are separate.)

.PARAMETER FactoryReset
    Put Betterbird back to its own pictures: remove the icon files from its icon folder (any that
    this tool did not make are saved first), point the shortcuts at Betterbird's own icon, put
    Betterbird's own mail popup back, put back the start page you had before this tool changed it,
    and remove this tool's data.

.PARAMETER Portable
    The folder of a portable Betterbird (the one holding BetterbirdLauncher.exe), or of a
    Betterbird installed in your own folder. Then nothing needs administrator rights.

.PARAMETER Manual
    Show step-by-step instructions for making all of these changes by hand.

.EXAMPLE
    .\Set-BetterbirdIcon.ps1 -MailPopup uk
.EXAMPLE
    .\Set-BetterbirdIcon.ps1 -MailPopup factory
.EXAMPLE
    .\Set-BetterbirdIcon.ps1 -Icon blue
.EXAMPLE
    .\Set-BetterbirdIcon.ps1 -Icon green2 -MailPopup green2 -RestartBetterbird
.EXAMPLE
    .\Set-BetterbirdIcon.ps1 -Icon blue -RestartExplorer
.EXAMPLE
    .\Set-BetterbirdIcon.ps1 -Icon uk -NewMail keep
.EXAMPLE
    .\Set-BetterbirdIcon.ps1 -NewMail none
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
    [switch]$FactoryReset,
    [switch]$RestartExplorer,
    [switch]$RestartBetterbird,
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
# Started from an administrator window these would run as administrator.
$NoAdminExplorer = 'Explorer was not restarted: this window runs as administrator, and Explorer would then run as administrator too. Sign out and back in, or restart Windows, to see the new icon.'
$NoAdminBetterbird = 'Betterbird was not started again: this window runs as administrator, and Betterbird would then run as administrator too. Start it yourself.'
$NoAdminDebug = 'This window runs as administrator, and Explorer would then run as administrator too. Run this again from a normal window (for example by double-clicking Set-BetterbirdIcon.cmd).'
$PopupInUse = 'Betterbird is using that picture. Quit it completely, including the tray icon, then try again.'

# 'system': Program Files install, needs admin.
# 'own':    portable or per-user install, no admin.
$Mode       = 'system'
$AppDir     = $null   # own mode: folder with betterbird.exe
$Launcher   = $null   # portable: BetterbirdLauncher.exe, which shortcuts target
$ProfileDir = $null   # portable: its profile
# Messages for the next menu screen (D done, W warning, S step), cleared once shown.
$script:Notes = @()
$script:MenuNotice = $null
$script:BetterbirdClosed = $false   # this run closed Betterbird, so it may start it again

if (-not $UserAppData)   { $UserAppData   = $env:APPDATA }
if (-not $UserDesktop)   { $UserDesktop   = [Environment]::GetFolderPath('Desktop') }
if (-not $UserStartMenu) { $UserStartMenu = [Environment]::GetFolderPath('StartMenu') }

$SetNotes = [ordered]@{
    'blue'       = 'light blue to green bird on a dark circle'
    'bb'         = 'orange/red, the standard Betterbird icon'
    'bb-green'   = 'green/yellow gradient'
    'green2'     = 'green only, grey circle'
    'uk'         = 'blue/yellow gradient'
    'lightgrey'  = 'light grey for dark OS mode'
    'newmail-sm' = 'SeaMonkey new-mail icon only'
}

# New-mail dot colours. Amber matches bb-green, Red matches blue.
$DotColours = [ordered]@{
    Amber  = '#ff6000'
    Gold   = '#ffd700'
    White  = '#ffffff'
    Pink   = '#ff1493'
    Purple = '#6a1b9a'
    Red    = '#ff2100'
    Grey   = '#808080'
}

# Mail popup images. These live in omni.ja, not in the .ico files. Any window set can be the
# popup; only blue (icons\popup\yours) and factory have ready-made pictures, the rest are drawn
# from the set's window icon.
$PopupFiles = [ordered]@{
    'chrome/messenger/content/branding/icon64.png'  = @{ File = 'icon64.png';  Size = 64 }
    'chrome/messenger/content/branding/icon128.png' = @{ File = 'icon128.png'; Size = 128 }
}
# Betterbird's own popup pictures are kept inside omni.ja under this suffix, so "factory" puts
# back exactly what that build had. An update replaces omni.ja and drops them.
$PopupSaved = '.betterbird-icons-original'
# Also kept in omni.ja: which set the popup shows, with the hashes of the pictures it made.
$PopupMarker = 'chrome/messenger/content/branding/betterbird-icons-popup.txt'

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
                   @(foreach ($d in $BackupDir, $CurrentDir) { foreach ($name in $IconFiles) { Join-Path $d $name } }) +
                   @(Get-ShortcutIconFiles | ForEach-Object { $_.FullName })
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
    if (-not (Test-ReparsePoint $CurrentDir)) {
        foreach ($f in @(Get-ShortcutIconFiles)) { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue }
    }
    Remove-Item -LiteralPath $StateFile -Force -ErrorAction SilentlyContinue
    foreach ($d in $BackupDir, $CurrentDir, $DataDir) {
        if ((Test-Path -LiteralPath $d) -and -not (Test-ReparsePoint $d) -and @(Get-ChildItem -LiteralPath $d -Force).Count -eq 0) {
            Remove-Item -LiteralPath $d -Force
        }
    }
    # A factory reset's saved icons (saved-*) are reported by Reset-Factory.
    if ((Test-Path -LiteralPath $DataDir) -and @(Get-ChildItem -LiteralPath $DataDir -Force | Where-Object { $_.Name -notlike 'saved-*' }).Count -gt 0) {
        Write-Warn "Left $DataDir in place: it holds files this tool did not make."
    }
}

function Remove-OldDotFile {
    # Before 2026-11-07 the dot icon was left in %LOCALAPPDATA%\BetterbirdIcons. Runs as the user.
    if (-not $env:LOCALAPPDATA) { return }
    $dir = Join-Path $env:LOCALAPPDATA 'BetterbirdIcons'
    $file = Join-Path $dir 'dot-newmail.ico'
    if ((Test-Path -LiteralPath $file) -and -not (Test-ReparsePoint $dir) -and -not (Test-ReparsePoint $file)) {
        Remove-Item -LiteralPath $file -Force
    }
    if ((Test-Path -LiteralPath $dir) -and -not (Test-ReparsePoint $dir) -and @(Get-ChildItem -LiteralPath $dir -Force).Count -eq 0) {
        Remove-Item -LiteralPath $dir -Force
    }
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

function Stop-Betterbird {
    # Closes it the normal way first. A Betterbird minimised to the tray has no main window, so that
    # can fail: then, only if the user agrees, stop the process. $true once none is left.
    Get-Betterbird | ForEach-Object { [void]$_.CloseMainWindow() }
    for ($i = 0; $i -lt 30 -and @(Get-Betterbird).Count -gt 0; $i++) { Start-Sleep -Milliseconds 500 }
    if (@(Get-Betterbird).Count -eq 0) { return $true }
    if (-not (Test-Interactive)) { return $false }
    $answer = Read-Host '  Betterbird did not close. Force it closed? Anything unsaved, such as a message being written, will be lost. (Y/N)'
    if ($answer -notmatch '^[Yy]') { return $false }
    Get-Betterbird | ForEach-Object { Stop-Process -Id $_.Id -Force }
    for ($i = 0; $i -lt 10 -and @(Get-Betterbird).Count -gt 0; $i++) { Start-Sleep -Milliseconds 500 }
    @(Get-Betterbird).Count -eq 0
}

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
    if (-not (Stop-Betterbird)) { throw 'Betterbird did not close. Close it yourself and run this again.' }
    $script:BetterbirdClosed = $true
    Write-Step 'Closed Betterbird.'
}

function Request-BetterbirdClosed([string]$StopMessage) {
    # Menu, in the user's own window and before any administrator prompt. $true: it closed Betterbird,
    # so the caller starts it again after the change. On N, a change that can't be made while it is
    # open stops with -StopMessage; the others carry on and say to restart Betterbird.
    if (@(Get-Betterbird).Count -eq 0) { return $false }
    Write-Host ''
    Write-Host '  Betterbird is open. Its window, taskbar button and system tray icon keep the old picture until it restarts.'
    $answer = "$(Read-Host '  Close Betterbird now and start it again when the change is done? (Y/N)')".Trim()
    if ($answer -match '^[Yy]') {
        if (Stop-Betterbird) { Write-Step 'Closed Betterbird.'; return $true }
        Write-Warn 'Betterbird is still open.'
    }
    if ($StopMessage) { throw $StopMessage }
    $false
}

function Start-Betterbird {
    # The portable launcher if there is one, else betterbird.exe. Only from the user's own window:
    # started from an administrator window it would run as administrator.
    if (Test-Admin) { Write-Warn $NoAdminBetterbird; return $false }
    $exe = if ($Launcher) { $Launcher } else { Join-Path (Get-InstallDir) 'betterbird.exe' }
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { Write-Warn "Couldn't find $exe to start Betterbird again. Start it yourself."; return $false }
    Start-Process -FilePath $exe
    Write-Done 'Started Betterbird again.'
    $true
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
    # Own .ico first, so its path is never joined onto icons\.
    if (Test-Path -LiteralPath $Icon -PathType Leaf) { return (Resolve-Path -LiteralPath $Icon).Path }
    $set = Join-Path $PSScriptRoot "icons\$Icon\messengerWindow.ico"
    if (Test-Path -LiteralPath $set) { return $set }
    $null
}

function Get-NewMailLabel([string]$Value) {
    # For the record and Status: a set name, 'none', or what kind of file it was.
    if (-not $Value -or -not (Test-Path -LiteralPath $Value -PathType Leaf)) { return $Value }
    if ((Split-Path $Value -Leaf) -like 'betterbird-icons-dot-*.ico') {
        $colour = Get-DotColourName $Value
        if ($colour) { return "$colour dot" }
    }
    "your own file ($(Split-Path $Value -Leaf))"
}

function Format-NewMailText([string]$Value) {
    # The recorded new-mail icon in words.
    switch ($Value) {
        'none'     { "Betterbird's own" }
        'original' { 'the one you had before' }
        default    { $Value }
    }
}

function Get-CurrentNewMailPath {
    # The installed new-mail (tray) icon, if there is one.
    try {
        $installed = Join-Path (Get-IconTarget (Get-InstallDir)) 'newmail.ico'
        if (Test-Path -LiteralPath $installed) { return $installed }
    } catch { $null = $_ }
    $null
}

function Get-DotBasePath {
    # The picture the dot goes on: the window icon this tool installed, else the one the record
    # names, else Betterbird's own design.
    try {
        $dir = Get-InstallDir
        if ((Get-InstalledIcon $dir).Kind -eq 'ours') { return (Join-Path (Get-IconTarget $dir) 'messengerWindow.ico') }
    } catch { $null = $_ }
    if (Test-DataDirTrusted) {
        $state = Read-State
        if ($state -and $state.Icon) {
            $window = Get-WindowIconPath $state.Icon
            if ($window) { return $window }
        }
    }
    Join-Path $PSScriptRoot 'icons\bb\messengerWindow.ico'
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

function Initialize-ShellNotify {
    if ('BetterbirdIcons.ShellNotify' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace BetterbirdIcons {
    public static class ShellNotify {
        [DllImport("shell32.dll", CharSet = CharSet.Unicode, EntryPoint = "SHChangeNotify")]
        static extern void NotifyPath(int eventId, uint flags, string item1, IntPtr item2);

        [DllImport("shell32.dll", EntryPoint = "SHChangeNotify")]
        static extern void NotifyAll(int eventId, uint flags, IntPtr item1, IntPtr item2);

        // SHCNE_UPDATEITEM, SHCNF_PATHW
        public static void UpdateItem(string path) { NotifyPath(0x00002000, 0x0005, path, IntPtr.Zero); }

        // SHCNE_ASSOCCHANGED, SHCNF_IDLIST
        public static void AssocChanged() { NotifyAll(0x08000000, 0x0000, IntPtr.Zero, IntPtr.Zero); }
    }
}
'@
}

function Send-ShellNotify([string]$Path) {
    # Tell Explorer a shortcut changed; with no path, that icons changed everywhere.
    # Only a hint, so never an error.
    try {
        Initialize-ShellNotify
        if ($Path) { [BetterbirdIcons.ShellNotify]::UpdateItem($Path) }
        else { [BetterbirdIcons.ShellNotify]::AssocChanged() }
    }
    catch { $null = $_ }
}

function Update-IconCache {
    $tool = Join-Path $env:SystemRoot 'System32\ie4uinit.exe'
    if (Test-Path -LiteralPath $tool) { & $tool -show 2>$null }
    Send-ShellNotify
}

function Copy-IconFile([string]$Source, [string]$Destination) {
    # Windows caches icons by path and file time: a copy that keeps the old time can keep
    # showing the old picture.
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
    try {
        $file = Get-Item -LiteralPath $Destination
        $readOnly = $file.IsReadOnly
        if ($readOnly) { $file.IsReadOnly = $false }
        $file.LastWriteTime = Get-Date
        if ($readOnly) { $file.IsReadOnly = $true }
    }
    catch { $null = $_ }
}

function Get-ShortcutIconFiles {
    # current\shortcut-<12 hex>.ico: the file the shortcuts use, named after its contents.
    if (-not (Test-Path -LiteralPath $CurrentDir) -or (Test-ReparsePoint $CurrentDir)) { return }
    Get-ChildItem -LiteralPath $CurrentDir -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^shortcut-[0-9A-Fa-f]{12}\.ico$' }
}

function Test-OurShortcutIcon([string]$Location) {
    # A shortcut icon this tool set: the old fixed file or a shortcut-*.ico, in current\.
    if (-not $Location) { return $false }
    $file = $Location -replace ',-?\d+$', ''
    try { $dir = [IO.Path]::GetDirectoryName($file); $leaf = [IO.Path]::GetFileName($file) }
    catch { return $false }
    if (-not $dir -or -not $dir.TrimEnd('\').Equals($CurrentDir.TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)) { return $false }
    $leaf -ieq 'messengerWindow.ico' -or $leaf -match '^shortcut-[0-9A-Fa-f]{12}\.ico$'
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
            $word = ($kv.Key -eq 'NewMail' -and $value -in 'none', 'keep') -or ($kv.Key -eq 'StartPage' -and $value -eq 'Off')
            if ($kv.Key -in 'Icon', 'NewMail', 'StartPage', 'Portable' -and $value -and -not $word) {
                # A set name like blue must not become a folder of that name.
                $type = if ($kv.Key -eq 'Portable') { 'Container' } else { 'Leaf' }
                try { $isPath = Test-Path -LiteralPath $value -PathType $type } catch { $isPath = $false }
            }
            elseif ($kv.Key -eq 'MailPopup' -and $value) {
                try { $isPath = [IO.Path]::GetExtension($value) -eq '.ico' -and (Test-Path -LiteralPath $value -PathType Leaf) } catch { $isPath = $false }
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
    # Everything except StartPage, RestartExplorer and RestartBetterbird.
    $elevated = @{}
    foreach ($kv in $Options.GetEnumerator()) {
        # Explorer and Betterbird are restarted by the normal window, never the administrator one.
        if ($kv.Key -notin 'StartPage', 'ExitFile', 'RestartExplorer', 'RestartBetterbird') { $elevated[$kv.Key] = $kv.Value }
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
        Send-ShellNotify $Path
        return $true
    }
    catch { Write-Warn "Couldn't update the shortcut $Path ($($_.Exception.Message))"; return $false }
    finally { if (Test-Path -LiteralPath $Path) { (Get-Item -LiteralPath $Path).IsReadOnly = $wasReadOnly } }
}

function Set-ShortcutIcons($State, [string[]]$Exes) {
    # Shortcuts get current\shortcut-<hash>.ico, a new path whenever the picture changes: Windows
    # keeps showing the old picture for a path it has already seen. messengerWindow.ico stays
    # for the backup logic and for shortcuts that still use it.
    $shell = New-Object -ComObject WScript.Shell
    $paths = @(@($State.Shortcuts) + @(Find-Shortcuts $Exes) | Where-Object { $_ } | Select-Object -Unique)
    $main = Join-Path $CurrentDir 'messengerWindow.ico'
    $file = Join-Path $CurrentDir ('shortcut-{0}.ico' -f (Get-Hash $main).Substring(0, 12))
    if ((Get-Hash $file) -ne (Get-Hash $main)) { Copy-IconFile $main $file }
    $icon = $file + ',0'
    $kept = @()
    $stillUsed = @{}   # our icon files that a shortcut we couldn't change still points at
    foreach ($p in $paths) {
        if (-not (Test-Path -LiteralPath $p)) { continue }
        try { $lnk = $shell.CreateShortcut($p) } catch { continue }
        if ($Exes -notcontains [Environment]::ExpandEnvironmentVariables($lnk.TargetPath)) { continue }
        $before = $lnk.IconLocation
        if ($null -eq $State.OriginalShortcutIcons.PSObject.Properties[$p]) {
            # Ours but unrecorded (interrupted run): treat the default icon as the original.
            $original = if (Test-OurShortcutIcon $before) { ',0' } else { $before }
            $State.OriginalShortcutIcons | Add-Member -NotePropertyName $p -NotePropertyValue $original
        }
        if ($before -ne $icon -and -not (Save-ShortcutIcon $shell $p $icon)) {
            if (Test-OurShortcutIcon $before) { $stillUsed[([IO.Path]::GetFileName(($before -replace ',-?\d+$', ''))).ToLowerInvariant()] = $true }
            continue
        }
        $kept += $p
    }
    # Older shortcut files go once every shortcut has moved.
    foreach ($old in @(Get-ShortcutIconFiles)) {
        if ($old.FullName -eq $file -or $stillUsed.ContainsKey($old.Name.ToLowerInvariant())) { continue }
        if (-not (Test-ReparsePoint $old.FullName)) { Remove-Item -LiteralPath $old.FullName -Force -ErrorAction SilentlyContinue }
    }
    $State.Shortcuts = $kept
    return $kept.Count
}

function Restore-ShortcutIcons($State, [string[]]$Exes) {
    # Only reset shortcuts still using our icon; leave ones changed since. Ones using our icon
    # that the record doesn't list (record lost, interrupted run) get Betterbird's own icon.
    # Returns how many couldn't be saved: their icon file must not be deleted.
    $shell = New-Object -ComObject WScript.Shell
    $failed = 0
    $recorded = @()
    foreach ($prop in $State.OriginalShortcutIcons.PSObject.Properties) {
        $recorded += $prop.Name
        if (-not (Test-Path -LiteralPath $prop.Name)) { continue }
        try { $now = $shell.CreateShortcut($prop.Name).IconLocation } catch { continue }
        if ((Test-OurShortcutIcon $now) -and -not (Save-ShortcutIcon $shell $prop.Name ([string]$prop.Value))) { $failed++ }
    }
    if ($Exes) {
        foreach ($p in @(Find-Shortcuts $Exes)) {
            if ($recorded -contains $p) { continue }
            try { $now = $shell.CreateShortcut($p).IconLocation } catch { continue }
            if ((Test-OurShortcutIcon $now) -and -not (Save-ShortcutIcon $shell $p ',0')) { $failed++ }
        }
    }
    $failed
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

function Copy-CurrentToInstall([string]$Target, [switch]$BuiltInNewMail, [switch]$KeepNewMail) {
    # Per file: ours, else the backup, else nothing (built-in icon).
    # -BuiltInNewMail forces the built-in new-mail icon; -KeepNewMail leaves it untouched.
    if (-not (Test-Path -LiteralPath $Target)) { New-Item -ItemType Directory -Path $Target -Force | Out-Null }
    foreach ($name in $IconFiles) {
        if ($KeepNewMail -and $name -eq 'newmail.ico') { continue }
        $src = Join-Path $CurrentDir $name
        $dst = Join-Path $Target $name
        $backup = Join-Path $BackupDir $name
        if (Test-ReparsePoint $dst) { throw "$dst is a link; not changing it." }
        if (Test-Path -LiteralPath $dst) { (Get-Item -LiteralPath $dst).IsReadOnly = $false }   # v1 could set read-only
        if (Test-Path -LiteralPath $src) {
            if ((Get-Hash $src) -ne (Get-Hash $dst)) { Copy-IconFile $src $dst }
        }
        elseif ((Test-Path -LiteralPath $backup) -and -not ($BuiltInNewMail -and $name -eq 'newmail.ico')) {
            Copy-IconFile $backup $dst
        }
        else { Remove-Item -LiteralPath $dst -ErrorAction SilentlyContinue }
    }
}

function Restore-CurrentFromInstall([string]$Target, [string]$Name) {
    # Keeping an icon this tool installed whose copy in current\ has been lost: take it back from
    # the install folder, but only if the stamp says it is ours.
    $current = Join-Path $CurrentDir $Name
    $installed = Join-Path $Target $Name
    if ((Test-Path -LiteralPath $current) -or -not (Test-Path -LiteralPath $installed)) { return }
    $stamp = Read-IconStamp $Target
    if ($stamp.ContainsKey($Name) -and $stamp[$Name] -eq (Get-Hash $installed)) { Copy-IconFile $installed $current }
}

function Install-Icon([string]$Value, [string]$NewMailValue) {
    # $Value empty: keep the window icon as it is (only the new-mail icon changes).
    # $NewMailValue empty: the set's own new-mail icon; none: Betterbird's own; keep: as it is.
    $keepMain = -not $Value
    $keepMail = $NewMailValue -eq 'keep'
    if ($keepMain -and (-not $NewMailValue -or $keepMail)) { throw 'Nothing to change: give an icon, or a new-mail icon.' }
    $dir = Get-InstallDir
    $target = Get-IconTarget $dir
    $main = $null
    if (-not $keepMain) {
        $main = Resolve-IconFile $Value 'messengerWindow.ico'
        if (-not $main) { throw "'$Value' only has a new-mail icon. Use it with -NewMail instead." }
    }
    if ($keepMail -or $NewMailValue -eq 'none') { $mail = $null }
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
    if ($keepMain) { Restore-CurrentFromInstall $target 'messengerWindow.ico' }
    if ($keepMail) { Restore-CurrentFromInstall $target 'newmail.ico' }
    Backup-Originals $target

    if ($main) { Copy-IconFile $main (Join-Path $CurrentDir 'messengerWindow.ico') }
    if ($mail) { Copy-IconFile $mail (Join-Path $CurrentDir 'newmail.ico') }
    elseif (-not $keepMail) { Remove-Item -LiteralPath (Join-Path $CurrentDir 'newmail.ico') -ErrorAction SilentlyContinue }

    Copy-CurrentToInstall $target -BuiltInNewMail:($NewMailValue -eq 'none') -KeepNewMail:$keepMail
    Write-IconStamp $target
    if (-not $keepMain) { $state.Icon = $Value }
    # 'none' = built-in; 'original' = whatever was there (set has no new-mail icon).
    if ($keepMail) { if (-not $state.NewMail) { $state.NewMail = 'original' } }
    else { $state.NewMail = if ($mail) { if ($NewMailValue) { Get-NewMailLabel $NewMailValue } else { $Value } } elseif ($NewMailValue -eq 'none') { 'none' } else { 'original' } }
    Save-State $state   # icons in place; save before touching shortcuts
    # Shortcuts show the window icon, which only exists in current\ if this tool installed one.
    $n = 0
    if (Test-Path -LiteralPath (Join-Path $CurrentDir 'messengerWindow.ico')) {
        $n = Set-ShortcutIcons $state (Get-BetterbirdExes $dir)
        Save-State $state
    }
    Update-IconCache

    if ($keepMain) { Write-Done "New-mail icon set to '$(Format-NewMailText $state.NewMail)'; the window icon is as it was." }
    else {
        $mailText = if ($keepMail) { 'as it was' } else { Format-NewMailText $state.NewMail }
        Write-Done "Icon set to '$Value' (new-mail icon: $mailText); $n shortcut(s) now use it."
    }
    if (@(Get-Betterbird).Count -gt 0) { Write-Warn 'Restart Betterbird to see the new window, taskbar and tray icon.' }
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
            # Shortcuts still pointing at the lost data folder get Betterbird's own icon.
            [void](Restore-ShortcutIcons (New-State) (Get-BetterbirdExes $dir))
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
        # No usable record. System-wide and portable each have their own data folder, so the
        # backup belongs to the Betterbird found now. A per-user install shares it: keep it.
        $found = $null
        if (-not (Test-SharedOwnData)) { try { $found = Get-InstallDir } catch { $null = $_ } }
        if (-not $found) {
            if (-not $state) { $state = New-State }
            if ((Restore-ShortcutIcons $state) -gt 0 -or (Test-HasBackup)) {
                Remove-DataDir -KeepBackup
                Write-Warn "This tool's record is missing, so your earlier icons were left in $BackupDir. Copy them back by hand (see -Manual)."
                return
            }
            Remove-DataDir
            Write-Done 'Nothing left to restore.'
            return
        }
        if (-not $state) { $state = New-State }
        $state.InstallDir = $found
        Write-Step "This tool's record was missing; restoring the Betterbird in $found."
    }
    # Recorded InstallDir (written elevated), so this still works after an uninstall.
    $dir = [string]$state.InstallDir
    if ((Test-OtherOwnBetterbird $dir $AppDir) -and (Test-HasBackup)) {
        throw "The backup in $DataDir belongs to the Betterbird in $dir. Restore that one instead."
    }
    if ($Mode -eq 'own' -or -not (Test-SystemWideInstall $dir)) { $dir = Get-InstallDir }
    $target = Get-IconTarget $dir
    $restored = Test-Path -LiteralPath $target
    $handMade = @()
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
            if ($hash -and -not $ours) {
                # Not ours: the original (nothing to do), or changed by hand since - leave that.
                if ((Test-Path -LiteralPath $backup) -and $hash -ne (Get-Hash $backup)) { $handMade += $name }
                continue
            }
            if (Test-Path -LiteralPath $backup) { Copy-IconFile $backup $dst }
            elseif ($ours) { Remove-Item -LiteralPath $dst }
        }
        Remove-IconStamp $target
    }
    $failed = Restore-ShortcutIcons $state (Get-BetterbirdExes $dir)
    Update-IconCache
    if (-not $restored -and (Test-HasBackup)) {
        # Install folder is gone: keep the backup, it's the only copy.
        Remove-DataDir -KeepBackup
        Write-Warn "$target is not there any more, so your earlier icons were kept in $BackupDir."
        return
    }
    if ($handMade.Count -gt 0 -or $failed -gt 0) {
        Remove-DataDir -KeepBackup
        if ($handMade.Count -gt 0) {
            Write-Warn "$($handMade -join ' and ') in $target was changed after this tool backed it up, so it was left as it is. The earlier one is kept in $BackupDir. Revert to Betterbird defaults removes both."
        }
        if ($failed -gt 0) {
            Write-Warn "$failed shortcut(s) could not be put back, so the icon they use was kept in $CurrentDir. Run Restore again once they can be changed."
        }
        return
    }
    Remove-DataDir
    Write-Done 'Original icons and shortcuts restored.'
}

# ---------------------------------------------------------------- factory reset

function Get-InstalledIcon([string]$Dir, [string]$File = 'messengerWindow.ico') {
    # The icon actually installed (the window icon, or newmail.ico for the tray): Kind builtin
    # (no file), ours (matches our stamp) or other; Set is the bundled set it equals, if any.
    $target = Join-Path $Dir 'chrome\icons\default'
    $hash = Get-Hash (Join-Path $target $File)
    if (-not $hash) { return @{ Kind = 'builtin'; Set = $null } }
    $stamp = Read-IconStamp $target
    $set = $null
    foreach ($name in $SetNotes.Keys) {
        if ((Get-Hash (Join-Path $PSScriptRoot "icons\$name\$File")) -eq $hash) { $set = $name; break }
    }
    $kind = if ($stamp.ContainsKey($File) -and $stamp[$File] -eq $hash) { 'ours' } else { 'other' }
    @{ Kind = $kind; Set = $set }
}

function Reset-Factory {
    # Everything back to Betterbird's own, whatever put it there: icon files, shortcut icons,
    # mail popup, this tool's data. Icons this tool didn't make are saved first. The start page
    # needs the user's rights: Reset-StartPageToPrevious.
    $dir = Get-InstallDir
    $target = Get-IconTarget $dir
    Close-Betterbird 'for a factory reset'
    # A folder this tool didn't make is never read; Initialize-DataDir moves it aside if needed.
    $trusted = (Test-Path -LiteralPath $DataDir) -and (Test-DataDirTrusted)
    $state = if ($trusted) { Read-State } else { $null }
    if ($state -and (Test-OtherOwnBetterbird $state.InstallDir $dir) -and (Test-HasBackup)) {
        throw "The backup in $DataDir belongs to the Betterbird in $($state.InstallDir). Restore that one first."
    }

    # Icon files: keep a copy of anything that isn't ours, including the backups of what was
    # there before this tool.
    $stamp = Read-IconStamp $target
    $toSave = @()
    foreach ($name in $IconFiles) {
        $dst = Join-Path $target $name
        if (-not (Test-Path -LiteralPath $dst)) { continue }
        if (Test-ReparsePoint $dst) { throw "$dst is a link; not changing it." }
        $hash = Get-Hash $dst
        $ours = ($trusted -and $hash -eq (Get-Hash (Join-Path $CurrentDir $name))) -or
                ($stamp.ContainsKey($name) -and $hash -eq $stamp[$name])
        if (-not $ours) { $toSave += @{ From = $dst; Name = $name; Hash = $hash } }
    }
    if ($trusted) {
        foreach ($name in $IconFiles) {
            $backup = Join-Path $BackupDir $name
            $hash = Get-Hash $backup
            if ($hash -and -not ($toSave | Where-Object { $_.Hash -eq $hash })) {
                $toSave += @{ From = $backup; Name = $name -replace '\.ico$', ' (before this tool).ico'; Hash = $hash }
            }
        }
    }
    $saved = $null
    if ($toSave.Count -gt 0) {
        Initialize-DataDir
        $saved = Join-Path $DataDir ('saved-{0:yyyyMMdd-HHmmss}' -f (Get-Date))
        # Inherits the data folder's admin-only permissions; never read back by this tool.
        New-Item -ItemType Directory -Path $saved | Out-Null
        foreach ($s in $toSave) { Copy-Item -LiteralPath $s.From (Join-Path $saved $s.Name) }
        foreach ($s in $toSave) {
            if ((Get-Hash (Join-Path $saved $s.Name)) -ne $s.Hash) { throw "Couldn't save a copy of $($s.From), so nothing was removed." }
        }
        $state = Read-State   # Initialize-DataDir may have moved an untrusted folder aside
        $trusted = $true
    }
    foreach ($name in $IconFiles) {
        $dst = Join-Path $target $name
        if (-not (Test-Path -LiteralPath $dst)) { continue }
        (Get-Item -LiteralPath $dst).IsReadOnly = $false
        Remove-Item -LiteralPath $dst -Force
    }
    Remove-IconStamp $target

    # Shortcuts: every Betterbird shortcut found, plus any this tool recorded.
    $exes = Get-BetterbirdExes $dir
    $shell = New-Object -ComObject WScript.Shell
    $paths = @(@(if ($state) { $state.Shortcuts }) + @(Find-Shortcuts $exes) | Where-Object { $_ } | Select-Object -Unique)
    $failed = 0
    foreach ($p in $paths) {
        if (-not (Test-Path -LiteralPath $p)) { continue }
        try { $lnk = $shell.CreateShortcut($p) } catch { continue }
        if ($exes -notcontains [Environment]::ExpandEnvironmentVariables($lnk.TargetPath)) { continue }
        if ($lnk.IconLocation -in ',0', '') { continue }
        if (-not (Save-ShortcutIcon $shell $p ',0')) { $failed++ }
    }
    Update-IconCache

    # Mail popup: only if omni.ja is there; a failure here doesn't undo the rest.
    $popupOk = $true
    if (Test-Path -LiteralPath (Join-Path $dir 'omni.ja')) {
        try { Set-MailPopup -Name 'factory' }
        catch { $popupOk = $false; Write-Warn "Mail popup not changed: $($_.Exception.Message)" }
    }

    if ($trusted) {
        if ($failed -gt 0) {
            # Keep current\: a shortcut that couldn't be changed may still use it. The backups
            # are in the saved copy.
            if (-not (Test-ReparsePoint $BackupDir)) {
                foreach ($name in $IconFiles) { Remove-Item -LiteralPath (Join-Path $BackupDir $name) -Force -ErrorAction SilentlyContinue }
            }
            Remove-Item -LiteralPath $StateFile -Force -ErrorAction SilentlyContinue
        }
        else { Remove-DataDir }
    }
    if ($saved) { Write-Warn "Icons this tool did not make were removed; a copy is in $saved." }
    if ($failed -gt 0) {
        Write-Warn "$failed shortcut(s) could not be changed. Change their icon by hand (see -Manual)."
    }
    if ($failed -eq 0 -and $popupOk) { Write-Done "Betterbird is back to its own icons and mail popup. Start it again to see them." }
}

function Reset-StartPageToPrevious {
    # The start page part of a factory reset: put back what was there before this tool, in
    # profiles it changed. A start page you set yourself stays.
    if (Test-Admin) {
        Write-Warn 'The start page was left as it is: it is only changed with your normal rights. Use Start page, then Put the previous page back, from a normal window.'
        return
    }
    $profiles = @()
    try { $profiles = @(Get-Profiles (Get-InstallDir)) } catch { $null = $_ }
    if (@($profiles | Where-Object { Test-Path -LiteralPath (Join-Path $_ $SideFile) }).Count -eq 0) {
        Write-Step 'Start page: not changed by this tool, so left as it is.'
        return
    }
    Set-StartPage 'Off'
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

function Resolve-PopupName([string]$Name) {
    # A window set, 'factory', or the full path of an .ico. 'yours' is the old name for blue.
    if ($Name -eq 'yours') { return 'blue' }
    if ($Name -eq 'factory') { return 'factory' }
    $set = @(Get-MenuIconSets 'window') | Where-Object { $_ -eq $Name } | Select-Object -First 1
    if ($set) { return $set }
    $isFile = $false
    try { $isFile = [bool]$Name -and (Test-Path -LiteralPath $Name -PathType Leaf) } catch { $isFile = $false }
    if ($isFile) {
        $full = (Resolve-Path -LiteralPath $Name).Path
        if ([IO.Path]::GetExtension($full) -ne '.ico' -or -not (Test-IcoFile $full)) { throw "$Name is not an .ico icon file." }
        return $full
    }
    throw "There is no mail popup called '$Name'."
}

function Get-PopupSetName([string]$Key) {
    # What the marker and the messages call it: a set name, factory, or custom (your own .ico).
    if ($Key -match '^[A-Za-z0-9-]+$') { $Key } else { 'custom' }
}

function Get-PopupLabel([string]$SetName) {
    switch ($SetName) {
        'factory' { "Betterbird's own" }
        'custom'  { 'your own picture' }
        default   { $SetName }
    }
}

function New-PopupBytes([string]$Ico) {
    # Draw the popup pictures from the largest picture in an .ico, at the sizes the popup uses.
    $frames = @(Get-IcoFrames $Ico)
    try {
        $big = $frames | Sort-Object Width -Descending | Select-Object -First 1
        $map = @{}
        foreach ($jarName in $PopupFiles.Keys) {
            $size = $PopupFiles[$jarName].Size
            $bitmap = New-Object System.Drawing.Bitmap $size, $size, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
            $draw = [System.Drawing.Graphics]::FromImage($bitmap)
            $attributes = New-Object System.Drawing.Imaging.ImageAttributes
            $memory = New-Object IO.MemoryStream
            try {
                $draw.Clear([System.Drawing.Color]::Transparent)
                $draw.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $draw.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
                $draw.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
                $draw.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
                # No faint edge around the picture.
                $attributes.SetWrapMode([System.Drawing.Drawing2D.WrapMode]::TileFlipXY)
                $draw.DrawImage($big, (New-Object System.Drawing.Rectangle 0, 0, $size, $size), 0, 0, $big.Width, $big.Height,
                    [System.Drawing.GraphicsUnit]::Pixel, $attributes)
                $bitmap.Save($memory, [System.Drawing.Imaging.ImageFormat]::Png)
                $map[$jarName] = $memory.ToArray()
            }
            finally { $memory.Dispose(); $attributes.Dispose(); $draw.Dispose(); $bitmap.Dispose() }
            if (-not (Test-PopupPng -Bytes $map[$jarName] -Size $size)) { throw "Couldn't make the mail popup picture from $Ico." }
        }
        $map
    }
    finally { foreach ($frame in $frames) { $frame.Dispose() } }
}

function Get-PopupBytes([string]$Name) {
    # The two popup pictures by entry name: ready-made for blue and factory, else drawn.
    $key = Resolve-PopupName $Name
    $folder = switch ($key) { 'factory' { 'factory' } 'blue' { 'yours' } default { $null } }
    if (-not $folder) {
        $ico = if ($key -match '^[A-Za-z0-9-]+$') { Join-Path $PSScriptRoot "icons\$key\messengerWindow.ico" } else { $key }
        return (New-PopupBytes $ico)
    }
    $dir = Join-Path $PSScriptRoot "icons\popup\$folder"
    $map = @{}
    foreach ($jarName in $PopupFiles.Keys) {
        $info = $PopupFiles[$jarName]
        $path = Join-Path $dir $info.File
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "The mail popup '$key' is missing $($info.File)." }
        $bytes = [IO.File]::ReadAllBytes($path)
        if (-not (Test-PopupPng -Bytes $bytes -Size $info.Size)) { throw "The mail popup '$key' has a damaged $($info.File)." }
        $map[$jarName] = $bytes
    }
    $map
}

function New-PopupMarker([string]$Key, $Bytes) {
    # Which set the popup shows, with the hashes of the pictures that were put there.
    $lines = @('set=' + (Get-PopupSetName $Key))
    foreach ($jarName in $PopupFiles.Keys) {
        $lines += '{0}={1}' -f ($PopupFiles[$jarName].File -replace '\.png$', ''), (Get-BytesHash -Bytes $Bytes[$jarName])
    }
    , [Text.Encoding]::UTF8.GetBytes((($lines -join "`r`n") + "`r`n"))   # the comma keeps it one byte array
}

function Get-PopupMarkerSet($Found) {
    # The set the marker names, if the pictures in omni.ja still are the ones it recorded.
    if (-not $Found.ContainsKey($PopupMarker)) { return $null }
    $text = [Text.Encoding]::UTF8.GetString($Found[$PopupMarker])
    $set = [regex]::Match($text, '(?m)^set=([A-Za-z0-9-]+)\s*$')
    if (-not $set.Success) { return $null }
    if ($set.Groups[1].Value -notin @(Get-MenuIconSets 'window') + 'custom') { return $null }
    foreach ($jarName in $PopupFiles.Keys) {
        $line = [regex]::Match($text, '(?m)^' + ($PopupFiles[$jarName].File -replace '\.png$', '') + '=([0-9A-F]{64})\s*$')
        if (-not $line.Success -or -not $Found.ContainsKey($jarName)) { return $null }
        if ((Get-BytesHash -Bytes $Found[$jarName]) -ne $line.Groups[1].Value) { return $null }
    }
    $set.Groups[1].Value
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

        // replacements: entry name -> new bytes. A null value drops the entry; a name not in
        // the archive is added at the end.
        public static void Write(string sourcePath, string destPath, IDictionary replacements) {
            var items = new List<Item>();
            var seen = new Dictionary<string, bool>(StringComparer.Ordinal);
            using (var source = ZipFile.OpenRead(sourcePath))
            using (var stream = new FileStream(destPath, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            using (var writer = new BinaryWriter(stream)) {
                foreach (ZipArchiveEntry entry in source.Entries) {
                    seen[entry.FullName] = true;
                    bool replaced = replacements != null && replacements.Contains(entry.FullName);
                    if (replaced && replacements[entry.FullName] == null) continue;
                    byte[] data = replaced ? Bytes(replacements[entry.FullName]) : ReadAll(entry);
                    uint crc = Crc32(data);
                    if (!replaced && ReadCrc(entry) != crc)
                        throw new InvalidDataException("The picture archive could not be read whole.");
                    Add(writer, stream, items, entry.FullName, data, crc, entry.LastWriteTime.LocalDateTime,
                        unchecked((uint)entry.ExternalAttributes));
                }
                if (replacements != null) {
                    var added = new List<string>();
                    foreach (DictionaryEntry pair in replacements) {
                        string name = (string)pair.Key;
                        if (pair.Value != null && !seen.ContainsKey(name)) added.Add(name);
                    }
                    added.Sort(StringComparer.Ordinal);
                    foreach (string name in added) {
                        byte[] data = Bytes(replacements[name]);
                        Add(writer, stream, items, name, data, Crc32(data), DateTime.Now, 0);
                    }
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

        static void Add(BinaryWriter writer, Stream stream, List<Item> items, string name, byte[] data,
                        uint crc, DateTime local, uint attr) {
            if (data.LongLength > uint.MaxValue)
                throw new InvalidDataException("A file in the picture archive is too large.");
            if (stream.Position > uint.MaxValue)
                throw new InvalidDataException("The picture archive is too large.");
            var item = new Item();
            item.Name = name;
            item.NameBytes = Encoding.UTF8.GetBytes(name);
            if (item.NameBytes.Length > ushort.MaxValue)
                throw new InvalidDataException("A file name in the picture archive is too long.");
            item.Flags = 0;
            for (int i = 0; i < item.NameBytes.Length; i++) {
                if (item.NameBytes[i] >= 128) { item.Flags = 0x800; break; }
            }
            item.Crc = crc;
            item.Size = (uint)data.LongLength;
            if (local.Year < 1980) local = new DateTime(1980, 1, 1);
            item.DosTime = (ushort)((local.Hour << 11) | (local.Minute << 5) | (local.Second / 2));
            item.DosDate = (ushort)(((local.Year - 1980) << 9) | (local.Month << 5) | local.Day);
            item.Attr = attr;
            item.LocalOffset = (uint)stream.Position;
            WriteLocal(writer, item, data);
            items.Add(item);
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

function Read-PopupEntries([string]$Omni) {
    # The popup pictures in omni.ja and any saved originals, by entry name (missing ones left out).
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($Omni)
    $found = @{}
    try {
        foreach ($jarName in @($PopupFiles.Keys) + @($PopupFiles.Keys | ForEach-Object { $_ + $PopupSaved }) + $PopupMarker) {
            $entry = $zip.GetEntry($jarName)
            if (-not $entry) { continue }
            $stream = $entry.Open()
            try {
                $memory = New-Object IO.MemoryStream
                $stream.CopyTo($memory)
                $found[$jarName] = $memory.ToArray()
            }
            finally { $stream.Dispose() }
        }
    }
    finally { $zip.Dispose() }
    $found
}

function Test-PopupMatch($Found, $Bytes) {
    foreach ($jarName in $PopupFiles.Keys) {
        if (-not $Found.ContainsKey($jarName)) { return $false }
        if ((Get-BytesHash -Bytes $Found[$jarName]) -ne (Get-BytesHash -Bytes $Bytes[$jarName])) { return $false }
    }
    $true
}

function Get-MailPopupName {
    # The set the popup shows (from the marker), 'custom' for your own .ico, 'factory' (the copy
    # that comes with this tool), or nothing: not changed by this tool, possibly another build's
    # own picture.
    $omni = Join-Path (Get-InstallDir) 'omni.ja'
    if (-not (Test-Path -LiteralPath $omni -PathType Leaf) -or (Test-ReparsePoint $omni)) { return $null }
    $found = Read-PopupEntries $omni
    $set = Get-PopupMarkerSet $found
    if ($set) { return $set }
    # Changed before the marker existed.
    foreach ($name in 'blue', 'factory') {
        if (Test-PopupMatch $found (Get-PopupBytes -Name $name)) { return $name }
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
    # Replace the two popup images in omni.ja; copy everything else as is. The first change keeps
    # Betterbird's own pictures inside omni.ja; 'factory' puts those back.
    $key = Resolve-PopupName $Name   # also checks the name
    $wanted = Get-PopupBytes -Name $key
    $label = Get-PopupLabel (Get-PopupSetName $key)
    $blue = Get-PopupBytes -Name 'blue'
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
        Assert-MailPopupEntries -Omni $omni
        $found = Read-PopupEntries $omni
        $saved = @{}
        foreach ($jarName in $PopupFiles.Keys) {
            if ($found.ContainsKey($jarName + $PopupSaved)) { $saved[$jarName] = $found[$jarName + $PopupSaved] }
        }
        $hasSaved = $saved.Count -eq $PopupFiles.Count
        $shown = Get-PopupMarkerSet $found
        # Blue from an older version, which kept no copy of the original and left no marker.
        $isOldBlue = -not $shown -and (Test-PopupMatch $found $blue)
        $replacements = @{}
        if ($key -eq 'factory') {
            if ($hasSaved) {
                foreach ($jarName in $PopupFiles.Keys) {
                    $replacements[$jarName] = $saved[$jarName]
                    $replacements[$jarName + $PopupSaved] = $null
                }
                $replacements[$PopupMarker] = $null
            }
            elseif ($shown -or $isOldBlue) {
                foreach ($jarName in $PopupFiles.Keys) { $replacements[$jarName] = $wanted[$jarName] }
                $replacements[$PopupMarker] = $null
                Write-Warn "Betterbird's own popup picture was not kept when it was changed, so the copy that comes with this tool was used. If it doesn't look right, reinstall Betterbird."
            }
            else {
                Write-Done "Mail popup already has Betterbird's own picture."
                return
            }
        }
        else {
            if (Test-PopupMatch $found $wanted) { Write-Done "Mail popup is already $label."; return }
            foreach ($jarName in $PopupFiles.Keys) {
                $replacements[$jarName] = $wanted[$jarName]
                if (-not $hasSaved -and -not $shown -and -not $isOldBlue) { $replacements[$jarName + $PopupSaved] = $found[$jarName] }
            }
            $replacements[$PopupMarker] = New-PopupMarker $key $wanted
        }
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force }
        $sddl = (Get-Acl -LiteralPath $omni).Sddl
        Initialize-StoredJar
        [BetterbirdIcons.StoredJar]::Write($omni, $tmp, $replacements)
        $file = Get-Item -LiteralPath $omni
        $wasReadOnly = $file.IsReadOnly
        if ($wasReadOnly) { $file.IsReadOnly = $false }
        [IO.File]::Replace($tmp, $omni, [NullString]::Value)
        Write-Done "Mail popup set to $label."
        Write-Warn 'Quit Betterbird and open it again to see it. A Betterbird update puts the original bird back.'
    }
    catch {
        if (Test-FileInUse -ErrorRecord $_) { throw $PopupInUse }
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

function Get-PopupMenuChoices {
    # Every window set, then Betterbird's own.
    @(Get-MenuIconSets 'window') + 'factory'
}

function Resolve-MenuPopup([string]$Answer) {
    # List number or set name.
    $names = @(Get-PopupMenuChoices)
    if ($Answer -match '^\d+$') {
        $n = [int]$Answer
        if ($n -ge 1 -and $n -le $names.Count) { return $names[$n - 1] }
        throw "There is no mail popup number $Answer."
    }
    $Answer
}

function Get-IconPageHtml([switch]$Absolute) {
    # The preview page, built from the same lists as the menu so the numbers match. Popup pictures
    # are drawn here and embedded; -Absolute points the other pictures at this download folder.
    $base = if ($Absolute) { ([Uri]$PSScriptRoot).AbsoluteUri.TrimEnd('/') + '/icons' } else { '../icons' }
    $window = @(Get-MenuIconSets 'window')
    $tray = @(Get-MenuIconSets 'newmail')
    $rows = New-Object System.Collections.Generic.List[string]
    foreach ($name in (Get-MenuIconSets 'all')) {
        $w = [array]::IndexOf($window, $name) + 1
        $t = [array]::IndexOf($tray, $name) + 1
        $cells = @()
        $cells += if ($w) { "<td class=`"num`">$w</td><td><img src=`"$base/$name/messengerWindow.ico`" alt=`"`"></td>" } else { '<td></td><td></td>' }
        $cells += if ($t) { "<td class=`"num`">$t</td><td><img src=`"$base/$name/newmail.ico`" alt=`"`"></td>" } else { '<td></td><td></td>' }
        $cells += if ($w) { "<td class=`"num`">$w</td><td><img src=`"$(Get-PopupDataUri $name)`" alt=`"`"></td>" } else { '<td></td><td></td>' }
        $class = if ($name -eq 'blue') { ' class="yours"' } else { '' }
        $rows.Add("  <tr><td$class>$name</td>$($cells -join '')</tr>")
    }
    $own = $window.Count + 1
    $rows.Add("  <tr><td>Betterbird's own</td><td></td><td></td><td class=`"num`">none</td><td>Betterbird's built-in icon</td><td class=`"num`">$own</td><td><img src=`"$(Get-PopupDataUri 'factory')`" alt=`"`"></td></tr>")
    @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Betterbird icons</title>
<style>
  body { font-family: Segoe UI, sans-serif; background: #161616; color: #f2f2f2; margin: 32px; }
  h1 { font-size: 22px; font-weight: 600; }
  p { color: #c8c8c8; }
  table { border-collapse: collapse; }
  th, td { text-align: left; padding: 12px 18px; border-bottom: 1px solid #333; vertical-align: middle; }
  th { color: #aaa; font-weight: 600; }
  img { width: 64px; height: 64px; background: #000; }
  .num { font-size: 24px; }
  .yours { color: #9ee7c4; }
</style>
</head>
<body>
<h1>Betterbird icons</h1>
<p>Type the number in the menu: <b>Window</b> for options 1 and 2, <b>Tray</b> for option 3, <b>Popup</b> for option 5. The tray picture is the same bird with a dot.</p>
<table>
  <tr><th>Name</th><th>Window</th><th></th><th>Tray</th><th></th><th>Popup</th><th></th></tr>
$($rows -join "`r`n")
</table>
</body>
</html>
"@
}

function Get-PopupDataUri([string]$Name) {
    # A 64 px popup picture as a data address, for the preview page.
    $bytes = (Get-PopupBytes -Name $Name)['chrome/messenger/content/branding/icon64.png']
    'data:image/png;base64,' + [Convert]::ToBase64String($bytes)
}

function Open-IconPage {
    # Open the icon preview page. It is made fresh in the temp folder, so its numbers always
    # match the menu; the printed page in images\ is the fallback.
    $page = Join-Path $PSScriptRoot 'images\choose.html'
    try {
        $made = Join-Path ([IO.Path]::GetTempPath()) 'betterbird-icons-choose.html'
        if (Test-ReparsePoint $made) { throw "$made is a link." }
        [IO.File]::WriteAllText($made, (Get-IconPageHtml -Absolute), (New-Object Text.UTF8Encoding $false))
        $page = $made
    }
    catch { $null = $_ }
    if (-not (Test-Path -LiteralPath $page)) { return }
    Start-Process ([Uri](Resolve-Path -LiteralPath $page).Path).AbsoluteUri
}

function Show-List([string]$Kind = 'all', [string]$Current) {
    Write-Host ''
    Write-Host $(switch ($Kind) { 'newmail' { '  New-mail icons:' } 'popup' { '  New-mail popup pictures:' } default { '  Icon sets:' } })
    $i = 1
    foreach ($name in $(if ($Kind -eq 'popup') { Get-PopupMenuChoices } else { Get-MenuIconSets $Kind })) {
        $note = if ($name -eq 'factory') { "Betterbird's own" } else { $SetNotes[$name] }
        $mark = if ($Current -and $name -eq $Current) { '    current' } else { '' }
        Write-Host ('    {0}) {1,-11} {2}{3}' -f $i, $(if ($name -eq 'factory') { 'Betterbird' } else { $name }), $note, $mark)
        $i++
    }
}

# ---------------------------------------------------------------- explorer

function Restart-Explorer {
    # Only with the user's own rights: an Explorer started from an administrator window would run
    # as administrator. This user's Explorer = the ones in this Windows session.
    if (Test-Admin) {
        Write-Warn $NoAdminExplorer
        return $false
    }
    $session = [Diagnostics.Process]::GetCurrentProcess().SessionId
    $oldIds = @(Get-Process -Name explorer -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $session } | ForEach-Object { $_.Id })
    if ($oldIds.Count -gt 0) { Stop-Process -Id $oldIds -Force }
    # Windows starts the shell again by itself; start it only if that hasn't happened.
    $back = $false
    for ($i = 0; $i -lt 10 -and -not $back; $i++) {
        Start-Sleep -Milliseconds 500
        $back = @(Get-Process -Name explorer -ErrorAction SilentlyContinue |
                Where-Object { $_.SessionId -eq $session -and $oldIds -notcontains $_.Id }).Count -gt 0
    }
    if (-not $back) { Start-Process -FilePath (Join-Path $WindowsDir 'explorer.exe') }
    Write-Done 'Explorer restarted.'
    return $true
}

function Complete-Restarts([bool]$Explorer, [bool]$Betterbird) {
    # Command line, in the user's own window once the change is done: Explorer, then Betterbird.
    if ($Explorer) { [void](Restart-Explorer) }
    if ($Betterbird -and $script:BetterbirdClosed) {
        $script:BetterbirdClosed = $false
        [void](Start-Betterbird)
    }
    Show-CollectedNotes
}

function Invoke-DebugRestart {
    # Menu D, for debugging: close Betterbird and restart Windows Explorer. Own window only, never
    # elevated (Explorer would then run as administrator).
    Write-Host ''
    Write-Host '  Closes Betterbird if it is open, and restarts Windows Explorer (File Explorer windows close).'
    if (Test-Admin) { Write-Warn $NoAdminDebug; return }
    $answer = "$(Read-Host '  Go ahead? (Y/N)')".Trim()
    if ($answer -notmatch '^[Yy]') { return }
    if (@(Get-Betterbird).Count -gt 0) {
        if (Stop-Betterbird) { Write-Step 'Closed Betterbird.' }
        else { Write-Warn 'Betterbird is still open, so it was left as it is.' }
    }
    else { Write-Step 'Betterbird was not open.' }
    [void](Restart-Explorer)
}

function Show-Status {
    Write-Host ''
    $dir = $null
    $kind = if ($Mode -eq 'system') { 'installed for all users' } elseif ($Launcher) { 'portable' } else { 'in your own folder' }
    try { $dir = Get-InstallDir; Write-Host "  Betterbird:     $dir   ($kind)" } catch { Write-Warn $_.Exception.Message }
    # What is installed, checked against the stamp, not just what the record says.
    $state = $null
    $trusted = (Test-Path -LiteralPath $DataDir) -and (Test-DataDirTrusted)
    if ($trusted) { $state = Read-State }
    elseif (Test-Path -LiteralPath $DataDir) { Write-Warn "This tool's data folder $DataDir was not made by this tool, so it is ignored." }
    if ($dir) {
        $installed = Get-InstalledIcon $dir
        $like = if ($installed.Set) { ", the same as the '$($installed.Set)' set" } else { '' }
        switch ($installed.Kind) {
            'builtin' { Write-Host "  Icon:           Betterbird's own" }
            'ours' {
                $name = if ($state -and $state.Icon) { $state.Icon } elseif ($installed.Set) { $installed.Set } else { 'set by this tool' }
                $mail = if ($state -and $state.NewMail) { "   (new-mail icon: $($state.NewMail))" } else { '' }
                Write-Host "  Icon:           $name$mail"
            }
            default { Write-Host "  Icon:           a custom icon not put there by this tool$like. Revert to Betterbird defaults removes it." }
        }
        if ($installed.Kind -ne 'ours' -and $state -and $state.Icon) {
            Write-Warn "This tool's record says '$($state.Icon)', but that is not what is installed. Revert to Betterbird defaults tidies this up."
        }
        $tray = Get-InstalledIcon $dir 'newmail.ico'
        $trayLike = if ($tray.Set) { ", the same as the '$($tray.Set)' set" } else { '' }
        switch ($tray.Kind) {
            'builtin' { Write-Host "  Tray icon:      Betterbird's own" }
            'ours' {
                $text = if ($state -and $state.NewMail -and $state.NewMail -notin 'none', 'original') { $state.NewMail } elseif ($tray.Set) { $tray.Set } else { 'set by this tool' }
                Write-Host "  Tray icon:      $text"
            }
            default { Write-Host "  Tray icon:      a custom icon not put there by this tool$trayLike. Revert to Betterbird defaults removes it." }
        }
    }
    if ($state -and @($state.Shortcuts).Count -gt 0) { Write-Host "  Shortcuts:      $(@($state.Shortcuts).Count) using this tool's icon" }
    if ($dir) {
        $popupText = 'not changed by this tool'
        try {
            $popup = Get-MailPopupName
            if ($popup) { $popupText = Get-PopupLabel $popup }
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
        '  If the old icon keeps showing'
        '    Betterbird reads its window, taskbar button and system tray icon when it starts: quit it'
        '    completely (including the tray icon) and open it again. In this tool, the menu offers to do that'
        '    before a change; -RestartBetterbird does the same from the command line.'
        '    If the desktop or taskbar shortcut still shows the old icon, Windows is keeping it in a cache until'
        '    Explorer restarts. Sign out and back in, or restart Windows. To do it at once: Ctrl+Shift+Esc,'
        '    right-click Windows Explorer in the list, Restart. Open File Explorer windows close.'
        '    In this tool, D (Debug issues) closes Betterbird and restarts Explorer; -RestartExplorer restarts Explorer'
        '    from the command line. They only ever use your normal rights, never administrator.'
        ''
        '  Start page'
        '    1. In Betterbird, open the menu (three lines, top right), Settings, General.'
        '    2. In the Start Page section, tick the option to show the Start Page when Betterbird launches,'
        '       and in Location enter a web address or a file, for example  file:///C:/Docs/manual.html'
        '    3. To go back, use Restore Default there, or untick the option.'
        ''
        '  Mail popup'
        '    The large popup for a new message uses a picture built into Betterbird.'
        '    In this tool, choose 5 (Change the "new mail" popup icon): any icon set, or Betterbird''s own'
        '    to put the original bird back. Only blue has a ready-made picture; for the others the tool'
        '    draws one from the set''s icon. Choosing 1 (all at once) changes the popup too.'
        '    Quit Betterbird and open it again.'
        '    A Betterbird update puts the original bird back, so choose it again afterwards.'
        '    -Restore (put the earlier icons back) does not change this popup; R does.'
        ''
        '  Back to factory'
        '    Revert to Betterbird defaults (menu R) removes every icon file from the folder above (a copy of any this'
        '    tool did not make is kept), gives the shortcuts Betterbird''s own icon, puts Betterbird''s'
        '    own popup back, and puts back the start page you had before this tool changed it.'
        '    By hand: delete messengerWindow.ico and newmail.ico from the folder above, and for each'
        '    shortcut use Properties, Change Icon and pick the icon in betterbird.exe. Reinstalling'
        '    Betterbird puts its own popup back.'
        ''
        '  Put the original icon back'
        '    1. Close Betterbird.'
        "    2. Delete messengerWindow.ico and newmail.ico from  $target"
        '       (or copy back the ones you saved in step 3 above).'
        "    3. For each shortcut: Properties, Change Icon, Browse to  $exe  and pick its icon."
        ''
    ) | ForEach-Object { Write-Host $_ }
}

function Write-MenuItem([string]$Text, [switch]$Admin) {
    $ask = if ($Admin -and $Mode -eq 'system' -and -not (Test-Admin)) { '(asks for administrator permission)' } else { '' }
    Write-Host ('  {0,-48}{1}' -f $Text, $ask).TrimEnd()
}

function Show-Menu {
    # Runs as the user; in system mode only the icon actions elevate.
    # Each screen clears the previous one.
    while ($true) {
        Clear-Host
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
        Write-MenuItem '1) Change all at once (2, 3 and 5)' -Admin
        Write-MenuItem '2) Change the standard icon (Windows app icon)' -Admin
        Write-MenuItem '3) Change the system tray icon' -Admin
        Write-MenuItem '4) Change the system tray dot colour' -Admin
        Write-MenuItem '5) Change the "new mail" popup icon' -Admin
        Write-MenuItem '6) Show the icons for selection'
        Write-MenuItem '7) Show manual instructions'
        Write-MenuItem '8) Change the start page'
        Write-MenuItem '9) Show the current setup'
        Write-MenuItem 'D) Debug issues: close Betterbird and restart Windows Explorer'
        Write-MenuItem 'R) Revert to Betterbird defaults' -Admin
        Write-MenuItem 'S) Select a different Betterbird folder (such as a portable one)'
        Write-MenuItem 'Q) Quit'
        $choice = Read-Host '  Choose'
        $pause = $false
        try {
            switch ($choice) {
                { $_ -in '1', '2' } {
                    Clear-Host
                    Show-List 'window'
                    $answer = "$(Read-Host '  Number, or the path to your own .ico file')".Trim().Trim('"')
                    if (-not $answer) { continue }
                    $name = Resolve-MenuIcon $answer 'window'
                    $asks = $Mode -eq 'system' -and -not (Test-Admin)
                    $all = $choice -eq '1'
                    # 1: its own tray icon and popup too. 2: the tray icon stays as it is.
                    $mail = if ($all) { $null } else { 'keep' }
                    $what = if ($all) { "the icon, the tray icon and the popup to $name" } else { "the standard icon to $name" }
                    # 1 changes the popup, which can't be done while Betterbird holds omni.ja open.
                    $closed = Request-BetterbirdClosed $(if ($all) { $PopupInUse })
                    Show-Working "Changing $what." $asks
                    $script:Notes = @()
                    $changed = $false
                    try {
                        if (-not $asks) {
                            # Popup first: if Betterbird holds omni.ja open, nothing has changed yet.
                            if ($all) { Set-MailPopup -Name $name }
                            Install-Icon $name $mail
                            $changed = $true
                        }
                        else {
                            $options = @{ Icon = $name }
                            if ($all) { $options.MailPopup = $name } else { $options.NewMail = 'keep' }
                            $changed = Invoke-Elevated $options
                        }
                    }
                    finally { if ($closed) { [void](Start-Betterbird) } }
                    Set-MenuResult $changed "Changed $what."
                }
                '3' {
                    Clear-Host
                    Show-List 'newmail'
                    $answer = "$(Read-Host '  Number, or none for Betterbird''s own')".Trim().Trim('"')
                    if (-not $answer) { continue }
                    $mail = if ($answer -eq 'none') { 'none' } else { Resolve-MenuIcon $answer 'newmail' }
                    $asks = $Mode -eq 'system' -and -not (Test-Admin)
                    Show-Working 'Changing the system tray icon.' $asks
                    $script:Notes = @()
                    $changed = $false
                    if (-not $asks) { Install-Icon '' $mail; $changed = $true }
                    else { $changed = Invoke-Elevated @{ NewMail = $mail } }
                    Set-MenuResult $changed 'Changed the system tray icon.'
                }
                '4' {
                    Clear-Host
                    $base = Get-DotBasePath
                    $installedMail = Get-CurrentNewMailPath
                    $marked = Get-DotColourName $installedMail
                    Write-Host ''
                    Write-Host '  Dot colour of the system tray icon:'
                    if (-not $installedMail) { Write-Host "  Current icon: Betterbird's own" }
                    elseif (-not $marked) { Write-Host "  Current dot: the set's own colour" }
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
                    # A new file each time, deleted once installed (a copy is kept in current\).
                    $out = Join-Path ([IO.Path]::GetTempPath()) ('betterbird-icons-dot-{0}.ico' -f [guid]::NewGuid().ToString('n'))
                    $changed = $false
                    try {
                        Add-IconDot -Source $base -Dest $out -Hex $DotColours[$picked]
                        if (-not $asks) { Install-Icon '' $out; $changed = $true }
                        else { $changed = Invoke-Elevated @{ NewMail = $out } }
                    }
                    finally { Remove-Item -LiteralPath $out -Force -ErrorAction SilentlyContinue }
                    Remove-OldDotFile
                    Set-MenuResult $changed "Changed the dot to $picked."
                }
                '5' {
                    Clear-Host
                    $marked = $null
                    try { $marked = Get-MailPopupName } catch { $marked = $null }
                    Show-List 'popup' $marked
                    $answer = "$(Read-Host '  Number')".Trim().Trim('"')
                    if (-not $answer) { continue }
                    $picked = Resolve-MenuPopup $answer
                    [void](Resolve-PopupName $picked)   # a wrong name fails here, before any administrator prompt
                    $label = Get-PopupLabel (Get-PopupSetName $picked)
                    $asks = $Mode -eq 'system' -and -not (Test-Admin)
                    Show-Working "Changing the new-mail popup to $label." $asks
                    $script:Notes = @()
                    $changed = $false
                    if (-not $asks) { Set-MailPopup -Name $picked; $changed = $true }
                    else { $changed = Invoke-Elevated @{ MailPopup = $picked } }
                    Set-MenuResult $changed "Changed the new-mail popup to $label."
                }
                '6' { Open-IconPage; continue }
                '7' { Clear-Host; Show-Manual; $pause = $true }
                '8' {
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
                '9' { Clear-Host; Show-Status; $pause = $true }
                { $_ -match '^[Dd]$' } {
                    Clear-Host
                    Invoke-DebugRestart
                    $pause = $true
                }
                { $_ -match '^[Rr]$' } {
                    Clear-Host
                    Write-Host ''
                    Write-Host '  Revert to Betterbird defaults puts Betterbird back to its own pictures:'
                    Write-Host '    - removes the icon files from Betterbird''s icon folder, even ones you put there'
                    Write-Host '      yourself (a copy of those is kept, and you are told where)'
                    Write-Host '    - gives the Betterbird shortcuts Betterbird''s own icon'
                    Write-Host '    - puts Betterbird''s own new-mail popup back'
                    Write-Host '    - puts back the start page you had before this tool changed it'
                    Write-Host '    - removes this tool''s backups and records'
                    Write-Host '  Betterbird has to be closed.'
                    $answer = "$(Read-Host '  Go ahead? (Y/N)')".Trim()
                    if ($answer -notmatch '^[Yy]') { continue }
                    $asks = $Mode -eq 'system' -and -not (Test-Admin)
                    Show-Working 'Reverting to Betterbird defaults.' $asks
                    $script:Notes = @()
                    $changed = $false
                    if (-not $asks) { Reset-Factory; $changed = $true }
                    else { $changed = Invoke-Elevated @{ FactoryReset = $true } }
                    if ($changed) { Reset-StartPageToPrevious; Remove-OldDotFile }
                    Set-MenuResult $changed 'Reverted to Betterbird defaults.'
                }
                { $_ -match '^[Ss]$' } {
                    Clear-Host
                    $folder = "$(Read-Host '  Betterbird folder (the one with BetterbirdLauncher.exe or betterbird.exe)')".Trim().Trim('"')
                    if (-not $folder) { continue }
                    Enter-OwnFolderMode $folder
                    if (-not (Confirm-StandardUser @{ Portable = $folder })) { return }
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
    # Whatever happens, a Betterbird this run closed is started again if asked to, from the user's
    # own window (the administrator window never gets -RestartBetterbird).
    try { Invoke-ToolSteps $Options }
    finally {
        if ($Options.ContainsKey('RestartBetterbird') -and $Options['RestartBetterbird'] -and -not $Relaunched -and $script:BetterbirdClosed) {
            $script:BetterbirdClosed = $false
            [void](Start-Betterbird)
            Show-CollectedNotes
        }
    }
}

function Invoke-ToolSteps($Options) {
    # Runs the requested actions once the target Betterbird is known. Throws on error.
    $o = @{}
    foreach ($k in $Options.Keys) { $o[$k] = $Options[$k] }
    $iconValue = [string]$o['Icon']; $mailValue = [string]$o['NewMail']; $pageValue = [string]$o['StartPage']
    $popupValue = [string]$o['MailPopup']
    $doRestore = [bool]$o['Restore']
    $doFactory = [bool]$o['FactoryReset']
    $wantRestart = [bool]$o['RestartExplorer']
    $wantBirdRestart = [bool]$o['RestartBetterbird']
    $menu = -not ($iconValue -or $mailValue -or $pageValue -or $popupValue -or $doRestore -or $doFactory -or $wantRestart -or $wantBirdRestart -or $o['List'] -or $o['Status'] -or $o['Manual'])
    if ($o['Manual']) { Show-Manual; return }
    if ($o['Status']) { Show-Status; return }

    if ($Mode -eq 'own') {
        # No admin needed; if elevated, offer to restart de-elevated.
        if (-not (Confirm-StandardUser $Options)) { return }
    }
    if (-not $menu -and -not $Relaunched) {
        # Closed here, in the user's own window, so the administrator window finds nothing to close
        # and Betterbird can be started again from here afterwards.
        if ($doFactory) { Close-Betterbird 'for a factory reset' }
        elseif ($wantBirdRestart) {
            Close-Betterbird $(if ($iconValue -or $mailValue -or $popupValue -or $doRestore -or $pageValue) { 'for the change' } else { 'to restart it' })
        }
    }
    if ($Mode -eq 'system' -and ($iconValue -or $mailValue -or $doRestore -or $doFactory -or $popupValue) -and -not (Test-Admin)) {
        # Only icon actions need admin; the start page runs here, unelevated.
        $elevatedOk = Invoke-Elevated (Get-ElevatedOptions $Options)
        Show-CollectedNotes
        if (-not $elevatedOk) { $script:ToolExit = 1 }
        if ($elevatedOk -and ($doRestore -or $doFactory)) { Remove-OldDotFile }
        if ($elevatedOk -and $doFactory) { Reset-StartPageToPrevious; Show-CollectedNotes }
        if (-not $pageValue) {
            Complete-Restarts ($elevatedOk -and $wantRestart) $false
            return
        }
        $wantRestart = $wantRestart -and $elevatedOk
        $iconValue = ''; $mailValue = ''; $doRestore = $false; $doFactory = $false; $popupValue = ''
    }

    # Checked before changing anything.
    if ($pageValue -and (Test-Admin)) { throw $NoAdminProfiles }
    if ($Mode -eq 'system' -and (Test-Admin)) { Remove-OldReapplyTask }
    if ($menu) { Show-Menu; return }
    if ($doRestore) { Restore-Originals }
    if ($doFactory) {
        Reset-Factory
        # Relaunched elevated: the window that started this does the start page.
        if (-not $Relaunched) { Reset-StartPageToPrevious }
    }
    if (($doRestore -or $doFactory) -and -not $Relaunched) { Remove-OldDotFile }
    # Popup before icons: it fails while Betterbird runs, and then nothing should have changed.
    if ($popupValue) { Set-MailPopup -Name $popupValue }
    if ($iconValue -or $mailValue) { Install-Icon $iconValue $mailValue }
    if ($pageValue) { Set-StartPage $pageValue }
    # The first window does this; the administrator window it started leaves it to that one.
    if ($wantRestart -and -not $Relaunched) { Complete-Restarts $true $false }
}

# ---------------------------------------------------------------- main

# Dot-sourced by the tests: define the functions only.
if ($MyInvocation.InvocationName -eq '.') { return }

$script:ToolExit = 0
try {
    $menuMode = -not ($Icon -or $NewMail -or $MailPopup -or $StartPage -or $Restore -or $FactoryReset -or $RestartExplorer -or $RestartBetterbird -or $List -or $Status -or $Manual)
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

