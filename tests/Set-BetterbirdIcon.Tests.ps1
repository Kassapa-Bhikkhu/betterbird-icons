# Pester tests for Set-BetterbirdIcon.ps1.
# Runs against a fake install, profiles and shortcuts in TestDrive; anything touching the
# real system (ACLs, icon cache, closing Betterbird) is stubbed.
#
#   Invoke-Pester -Path tests

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Pester: variables set in BeforeAll are used in the It blocks')]
param()

BeforeAll {
    $Script = Join-Path $PSScriptRoot '..\Set-BetterbirdIcon.ps1'
    $Root = Split-Path $PSScriptRoot -Parent
    . $Script

    function Initialize-DataDir { Assert-NoLinks; New-Item -ItemType Directory -Path $BackupDir, $CurrentDir -Force | Out-Null }
    function Update-IconCache { }
    function Get-Betterbird { @() }
    function Test-Admin { $false }
    function Test-Interactive { $false }
    function Test-DataDirTrusted { -not (Test-ReparsePoint $DataDir) }   # TestDrive folders aren't owned by Administrators
    # Test folders only, not the real public desktop and Start menu.
    function Get-ShortcutFolders {
        @{ Flat = @($UserDesktop, (Join-Path $UserAppData 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'))
           Deep = @($UserStartMenu) }
    }

    function Test-IsAdmin {
        (New-Object Security.Principal.WindowsPrincipal ([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole(
            [Security.Principal.WindowsBuiltInRole]::Administrator)
    }

    function New-PlantedDataDir([string]$Name) {
        # Data folder as a standard user could pre-create it: owned by them, with a junction
        # inside pointing at a decoy for a system folder.
        $dir = Join-Path $TestDrive $Name
        $decoy = Join-Path $TestDrive "$Name-decoy"
        New-Item -ItemType Directory -Path $dir, $decoy | Out-Null
        Set-Content (Join-Path $decoy 'system-file.txt') 'must survive'
        New-Item -ItemType Junction -Path (Join-Path $dir 'backup') -Target $decoy | Out-Null
        Set-Content (Join-Path $dir 'state.json') '{"Icon":"x","NewMail":"none","InstallDir":"C:\\Windows","Shortcuts":[],"OriginalShortcutIcons":{}}'
        $me = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        & icacls.exe $dir /setowner "*$me" /Q | Out-Null
        @{ Dir = $dir; Decoy = $decoy }
    }

    function Get-Sha([string]$Path) { (Get-FileHash $Path -Algorithm SHA256).Hash }

    function Test-IcoStructure([string]$Path) {
        # Stricter than the script's header check: every entry must fit in the file.
        $b = [IO.File]::ReadAllBytes($Path)
        if ($b.Length -lt 6 -or [BitConverter]::ToUInt16($b, 0) -ne 0 -or [BitConverter]::ToUInt16($b, 2) -ne 1) { return $false }
        $count = [BitConverter]::ToUInt16($b, 4)
        if ($count -lt 1) { return $false }
        for ($i = 0; $i -lt $count; $i++) {
            $e = 6 + 16 * $i
            $size = [BitConverter]::ToUInt32($b, $e + 8)
            $offset = [BitConverter]::ToUInt32($b, $e + 12)
            if ($offset + $size -gt $b.Length) { return $false }
        }
        return $true
    }
}

Describe 'Icon sets' {
    It 'has a folder for every set the menu lists' {
        foreach ($name in $SetNotes.Keys) { Join-Path $Root "icons\$name" | Should -Exist }
    }

    It 'contains only valid .ico files' {
        foreach ($f in Get-ChildItem (Join-Path $Root 'icons') -Recurse -Filter *.ico) {
            Test-IcoStructure $f.FullName | Should -BeTrue -Because $f.FullName
            Test-IcoFile $f.FullName | Should -BeTrue -Because $f.FullName
        }
    }

    It 'gives every set except newmail-sm a main window icon and a new-mail icon' {
        foreach ($name in $SetNotes.Keys | Where-Object { $_ -ne 'newmail-sm' }) {
            Join-Path $Root "icons\$name\messengerWindow.ico" | Should -Exist
            Join-Path $Root "icons\$name\newmail.ico" | Should -Exist
        }
    }

    It 'offers every dot colour and marks the one already on the icon' {
        @($DotColours.Keys) | Should -Be @('Amber', 'Gold', 'White', 'Pink', 'Purple', 'Red', 'Grey')
        Get-DotColourName (Join-Path $Root 'icons\blue\newmail.ico') | Should -Be 'Red'
        Get-DotColourName (Join-Path $Root 'icons\green\newmail.ico') | Should -Be 'Amber'
        Get-DotColourName (Join-Path $Root 'icons\bb-green\newmail.ico') | Should -Be 'Amber'
        Get-DotColourName (Join-Path $Root 'icons\bb\newmail.ico') | Should -Be 'White'
        $unreadable = Join-Path $TestDrive 'not-an-icon.ico'
        Set-Content -LiteralPath $unreadable 'not an icon'
        Get-DotColourName $unreadable | Should -BeNullOrEmpty
        $src = Join-Path $Root 'icons\uk\messengerWindow.ico'
        foreach ($name in $DotColours.Keys) {
            $out = Join-Path $TestDrive "dot-$name.ico"
            Add-IconDot -Source $src -Dest $out -Hex $DotColours[$name]
            Get-DotColourName $out | Should -Be $name
        }
    }

    It 'offers yours and factory for the mail popup' {
        @($PopupChoices.Keys) | Should -Be @('yours', 'factory')
        foreach ($name in $PopupChoices.Keys) {
            $files = Get-PopupBytes -Name $name
            Test-PopupPng -Bytes $files['chrome/messenger/content/branding/icon64.png'] -Size 64 | Should -BeTrue
            Test-PopupPng -Bytes $files['chrome/messenger/content/branding/icon128.png'] -Size 128 | Should -BeTrue
        }
        { Set-MailPopup -Name 'green' } | Should -Throw '*no mail popup*'
    }

    It 'changes only the mail popup pictures, then factory puts the original back' {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $dir = Join-Path $TestDrive 'PopupBird'
        New-Item -ItemType Directory -Path $dir | Out-Null
        $omni = Join-Path $dir 'omni.ja'
        $zip = [IO.Compression.ZipFile]::Open($omni, 'Create')
        try {
            foreach ($pair in @(
                    @{ Name = 'chrome/messenger/content/branding/icon64.png'; Text = 'old-64' },
                    @{ Name = 'chrome/messenger/content/branding/icon128.png'; Text = 'old-128' },
                    @{ Name = 'chrome/keep.txt'; Text = 'keep-me' },
                    @{ Name = 'chrome/empty.txt'; Text = '' }
                )) {
                $entry = $zip.CreateEntry($pair.Name)
                $out = $entry.Open()
                try {
                    $bytes = [Text.Encoding]::ASCII.GetBytes($pair.Text)
                    if ($bytes.Length) { $out.Write($bytes, 0, $bytes.Length) }
                }
                finally { $out.Dispose() }
            }
        }
        finally { $zip.Dispose() }
        function Read-JarBytes([string]$Path, [string]$EntryName) {
            $read = [IO.Compression.ZipFile]::OpenRead($Path)
            try {
                $stream = $read.GetEntry($EntryName).Open()
                try {
                    $memory = New-Object IO.MemoryStream
                    $stream.CopyTo($memory)
                    return ,$memory.ToArray()
                }
                finally { $stream.Dispose() }
            }
            finally { $read.Dispose() }
        }
        $Mode = 'own'
        $AppDir = $dir
        function Get-AceText([string]$Path) {
            @((Get-Acl -LiteralPath $Path).Access | ForEach-Object {
                '{0}|{1}|{2}|{3}' -f $_.IdentityReference, $_.FileSystemRights, $_.AccessControlType, $_.InheritanceFlags
            }) -join ';'
        }
        $beforeAcl = Get-AceText $omni
        Set-MailPopup -Name 'yours'
        Get-BytesHash -Bytes (Read-JarBytes $omni 'chrome/messenger/content/branding/icon64.png') |
            Should -Be (Get-BytesHash -Bytes ([IO.File]::ReadAllBytes((Join-Path $Root 'icons\popup\yours\icon64.png'))))
        Get-BytesHash -Bytes (Read-JarBytes $omni 'chrome/messenger/content/branding/icon128.png') |
            Should -Be (Get-BytesHash -Bytes ([IO.File]::ReadAllBytes((Join-Path $Root 'icons\popup\yours\icon128.png'))))
        [Text.Encoding]::ASCII.GetString((Read-JarBytes $omni 'chrome/keep.txt')) | Should -Be 'keep-me'
        $check = [IO.Compression.ZipFile]::OpenRead($omni)
        try { $check.GetEntry('chrome/empty.txt').Length | Should -Be 0 }
        finally { $check.Dispose() }
        Get-MailPopupName | Should -Be 'yours'
        Get-AceText $omni | Should -Be $beforeAcl
        Set-MailPopup -Name 'factory'
        Get-MailPopupName | Should -Be 'factory'
        Get-BytesHash -Bytes (Read-JarBytes $omni 'chrome/messenger/content/branding/icon64.png') |
            Should -Be (Get-BytesHash -Bytes ([IO.File]::ReadAllBytes((Join-Path $Root 'icons\popup\factory\icon64.png'))))
        $stamp = (Get-Item -LiteralPath $omni).LastWriteTimeUtc
        Set-MailPopup -Name 'factory'
        (Get-Item -LiteralPath $omni).LastWriteTimeUtc | Should -Be $stamp
    }

    It 'does not follow a link to the picture file' {
        $dir = Join-Path $TestDrive 'PopupLink'
        New-Item -ItemType Directory -Path $dir | Out-Null
        $omni = Join-Path $dir 'omni.ja'
        Set-Content -LiteralPath $omni 'leave this'
        $Mode = 'own'
        $AppDir = $dir
        Mock Test-ReparsePoint { $Path -eq $omni }
        { Set-MailPopup -Name 'yours' } | Should -Throw '*is a link*'
        Get-Content -LiteralPath $omni -Raw | Should -Be "leave this`r`n"
    }

    It 'stops when Betterbird still has the picture file open' {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $dir = Join-Path $TestDrive 'PopupBusy'
        New-Item -ItemType Directory -Path $dir | Out-Null
        $omni = Join-Path $dir 'omni.ja'
        $zip = [IO.Compression.ZipFile]::Open($omni, 'Create')
        try {
            $entry = $zip.CreateEntry('chrome/keep.txt')
            $out = $entry.Open()
            $out.Dispose()
        }
        finally { $zip.Dispose() }
        $Mode = 'own'
        $AppDir = $dir
        $held = [IO.File]::Open($omni, 'Open', 'Read', 'None')
        try { { Set-MailPopup -Name 'yours' } | Should -Throw '*Quit it completely*' }
        finally { $held.Dispose() }
    }

    It 'does not rewrite the picture file when those pictures are not in it' {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $dir = Join-Path $TestDrive 'PopupMissing'
        New-Item -ItemType Directory -Path $dir | Out-Null
        $omni = Join-Path $dir 'omni.ja'
        $zip = [IO.Compression.ZipFile]::Open($omni, 'Create')
        try {
            $entry = $zip.CreateEntry('chrome/keep.txt')
            $out = $entry.Open()
            try {
                $bytes = [Text.Encoding]::ASCII.GetBytes('stay')
                $out.Write($bytes, 0, $bytes.Length)
            }
            finally { $out.Dispose() }
        }
        finally { $zip.Dispose() }
        $before = (Get-FileHash -LiteralPath $omni -Algorithm SHA256).Hash
        $Mode = 'own'
        $AppDir = $dir
        { Set-MailPopup -Name 'yours' } | Should -Throw '*cannot be changed on this version*'
        (Get-FileHash -LiteralPath $omni -Algorithm SHA256).Hash | Should -Be $before
    }

    It 'puts the read-only mark back on the picture file' {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $dir = Join-Path $TestDrive 'PopupReadOnly'
        New-Item -ItemType Directory -Path $dir | Out-Null
        $omni = Join-Path $dir 'omni.ja'
        $zip = [IO.Compression.ZipFile]::Open($omni, 'Create')
        try {
            foreach ($name in @('chrome/messenger/content/branding/icon64.png', 'chrome/messenger/content/branding/icon128.png')) {
                $entry = $zip.CreateEntry($name)
                $out = $entry.Open()
                try {
                    $bytes = [Text.Encoding]::ASCII.GetBytes('old')
                    $out.Write($bytes, 0, $bytes.Length)
                }
                finally { $out.Dispose() }
            }
        }
        finally { $zip.Dispose() }
        (Get-Item -LiteralPath $omni).IsReadOnly = $true
        $Mode = 'own'
        $AppDir = $dir
        try {
            Set-MailPopup -Name 'yours'
            (Get-Item -LiteralPath $omni).IsReadOnly | Should -BeTrue
            Get-MailPopupName | Should -Be 'yours'
        }
        finally { (Get-Item -LiteralPath $omni).IsReadOnly = $false }
    }

    It 'numbers the window icons with the blue set first' {
        $names = @(Get-MenuIconSets 'window')
        $names[0] | Should -Be 'blue'
        $names | Should -Not -Contain 'newmail-sm'
        Resolve-MenuIcon '1' 'window' | Should -Be 'blue'
        Resolve-MenuIcon 'blue' 'window' | Should -Be 'blue'
        Resolve-MenuIcon (Join-Path $Root 'icons\blue\messengerWindow.ico') 'window' | Should -Be (Join-Path $Root 'icons\blue\messengerWindow.ico')
        { Resolve-MenuIcon '99' 'window' } | Should -Throw
    }

    It 'resolves a set name and an .ico path, and rejects anything else' {
        Resolve-IconFile 'blue' 'messengerWindow.ico' | Should -Be (Join-Path $Root 'icons\blue\messengerWindow.ico')
        Resolve-IconFile 'green2' 'newmail.ico' | Should -Be (Join-Path $Root 'icons\green2\newmail.ico')
        Resolve-IconFile 'uk' 'newmail.ico' | Should -Be (Join-Path $Root 'icons\uk\newmail.ico')
        $own = Join-Path $Root 'icons\uk\messengerWindow.ico'
        Resolve-IconFile $own 'messengerWindow.ico' | Should -Be (Resolve-Path $own).Path
        { Resolve-IconFile 'no-such-set' 'messengerWindow.ico' } | Should -Throw
        { Resolve-IconFile '..\..\Windows' 'messengerWindow.ico' } | Should -Throw
        { Resolve-IconFile (Join-Path $Root 'README.md') 'messengerWindow.ico' } | Should -Throw
    }

    It 'rejects a file that is named .ico but is not an icon' {
        $fake = Join-Path $TestDrive 'fake.ico'
        Set-Content $fake 'not an icon'
        { Resolve-IconFile $fake 'messengerWindow.ico' } | Should -Throw
    }
}

Describe 'Safety checks' {
    It 'quotes arguments for the administrator window so they cannot add options' {
        Format-Arg 'C:\Program Files\x' | Should -Be '"C:\Program Files\x"'
        Format-Arg 'C:\dir\' | Should -Be '"C:\dir\\"'
        Format-Arg 'a" -Restore "b' | Should -Be '"a\" -Restore \"b"'
    }

    It 'only accepts Betterbird installed under Program Files' {
        Test-SystemWideInstall (Join-Path $env:ProgramFiles 'Betterbird') | Should -BeTrue
        Test-SystemWideInstall 'C:\Users\Someone\Betterbird' | Should -BeFalse
        Test-SystemWideInstall ($env:ProgramFiles + 'Evil\Betterbird') | Should -BeFalse
    }

    It 'refuses Betterbird that is not installed for all users' {
        Mock Get-ItemProperty { [pscustomobject]@{ Path = 'C:\Users\Someone\AppData\Local\Betterbird' } }
        Mock Test-Path -ParameterFilter { $LiteralPath -like '*betterbird.exe' } { $LiteralPath -notlike "$env:ProgramFiles*" }
        { Get-InstallDir } | Should -Throw '*system-wide*'
    }

    It 'shows manual instructions with the real folders' {
        $text = (Show-Manual 6>&1 | Out-String)
        $text | Should -Match ([regex]::Escape('chrome\icons\default'))
        $text | Should -Match ([regex]::Escape((Join-Path $Root 'icons')))
        $text | Should -Match 'updates leave these two files alone'
        $text | Should -Match 'Start page'
    }

    It 'reports a cancelled administrator prompt cleanly, and passes options safely' {
        Mock Start-Process { throw (New-Object ComponentModel.Win32Exception 1223) }   # what a cancelled UAC prompt throws
        (Invoke-Elevated @{ Icon = 'my "icon"'; Restore = $true } 6>&1 | Out-String) | Should -Match 'permission was not given'
        Should -Invoke Start-Process -Times 1 -ParameterFilter {
            ($ArgumentList -contains '-Icon') -and ($ArgumentList -contains '"my \"icon\""') -and
            ($ArgumentList -contains '-Restore') -and ($ArgumentList -contains '-ExitFile')
        }
        Mock Start-Process { throw 'something else went wrong' }
        (Invoke-Elevated @{ Icon = 'blue' } 6>&1 | Out-String) | Should -Match "Couldn't start the administrator window"
    }

    It 'gives the administrator window full paths, and keeps the start page out of it' {
        Push-Location (Join-Path $Root 'icons')
        try { $relaunch = Get-RelaunchArgs @{ Icon = 'blue\messengerWindow.ico'; NewMail = 'none' } }
        finally { Pop-Location }
        $relaunch | Should -Contain (Format-Arg (Join-Path $Root 'icons\blue\messengerWindow.ico'))
        $relaunch | Should -Contain '"none"'
        # Files named 'none' and 'Off' in the current folder must not turn into paths.
        Push-Location $TestDrive
        try {
            Set-Content (Join-Path $TestDrive 'none') 'x'; Set-Content (Join-Path $TestDrive 'Off') 'x'
            $words = Get-RelaunchArgs @{ NewMail = 'none'; StartPage = 'Off' }
        }
        finally { Pop-Location }
        $words | Should -Contain '"none"'
        $words | Should -Contain '"Off"'
        $popupArgs = Get-RelaunchArgs @{ MailPopup = 'factory' }
        $popupArgs | Should -Contain '-MailPopup'
        $popupArgs | Should -Contain '"factory"'
        $elevated = Get-ElevatedOptions @{ Icon = 'blue'; StartPage = 'C:\x.html'; Restore = $true }
        $elevated.Keys | Should -Not -Contain 'StartPage'
        $elevated.Icon | Should -Be 'blue'
        $elevated.Restore | Should -BeTrue
    }

    It 'starts PowerShell by its full path, from the menu and the launcher' {
        Mock Start-Process { }
        Invoke-Elevated @{ Icon = 'blue' }
        Should -Invoke Start-Process -Times 1 -ParameterFilter { $FilePath -eq (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') }
        Get-Content (Join-Path $Root 'Set-BetterbirdIcon.cmd') | Where-Object { $_ -match 'powershell\.exe' -and $_ -notmatch '^rem' } |
            Should -Match '^"%SystemRoot%\\System32\\WindowsPowerShell\\v1\.0\\powershell\.exe" '
    }

    It 'writes the administrator result only inside this user''s temp folder' {
        $script:Notes = @()
        Add-Note 'D' "Icon set to 'blue'"
        Add-Note 'W' "Restart Betterbird to see the new icon."
        $f = Join-Path ([IO.Path]::GetTempPath()) ("betterbird-icons-{0}.exit" -f [guid]::NewGuid().ToString('n'))
        Write-ExitFile $f 0 | Should -BeTrue
        $read = Read-ExitFile $f
        $read.Code | Should -Be 0
        @($read.Notes).Count | Should -Be 2
        $read.Notes[0].Text | Should -Be "Icon set to 'blue'"
        $read.Notes[1].Kind | Should -Be 'W'
        Test-Path -LiteralPath $f | Should -BeFalse
        Write-ExitFile 'C:\Windows\Temp\betterbird-icons-nope.exit' 0 | Should -BeFalse
        Test-SafeExitFile 'C:\Windows\Temp\betterbird-icons-nope.exit' | Should -BeFalse
        $script:Notes = @()
    }

    It 'reads Mozilla files as UTF-8, and other files in the Windows code page' {
        $name = 'B' + [char]0xFC + 'ro'   # u-umlaut, from char codes so this file's encoding can't change it
        $utf8 = Join-Path $TestDrive 'utf8.ini'
        [IO.File]::WriteAllText($utf8, "[Compatibility]`r`nLastAppDir=D:\$name\Betterbird`r`n", (New-Object Text.UTF8Encoding $false))
        Get-IniValue $utf8 'LastAppDir' | Should -Be "D:\$name\Betterbird"
        $ansi = Join-Path $TestDrive 'ansi.txt'
        $codePage = [Text.Encoding]::GetEncoding([Globalization.CultureInfo]::CurrentCulture.TextInfo.ANSICodePage)
        [IO.File]::WriteAllBytes($ansi, $codePage.GetBytes("D:\$name`r`n"))
        if ($codePage.GetString($codePage.GetBytes($name)) -eq $name) { @(Read-Lines $ansi)[0] | Should -Be "D:\$name" }
    }

    It 'reads a damaged state file without tripping over missing or empty fields' {
        $DataDir = Join-Path $TestDrive 'DamagedState'
        $StateFile = Join-Path $DataDir 'state.json'
        New-Item -ItemType Directory -Path $DataDir | Out-Null
        Set-Content $StateFile '{"Icon":"blue","InstallDir":5,"Shortcuts":null,"OriginalShortcutIcons":null}'
        $state = Read-State
        $state.Icon | Should -Be 'blue'
        $state.InstallDir | Should -BeNullOrEmpty   # not a string: ignored
        @($state.Shortcuts).Count | Should -Be 0
        $state.OriginalShortcutIcons | Should -BeOfType [pscustomobject]
        $null -eq $state.OriginalShortcutIcons.PSObject.Properties['x'] | Should -BeTrue
    }

    It 'moves aside a data folder someone else made, without following anything inside it' {
        if (-not (Test-IsAdmin)) { Set-ItResult -Skipped -Because 'it needs administrator rights'; return }
        . $Script   # real Initialize-DataDir and Test-DataDirTrusted, this test only
        $planted = New-PlantedDataDir 'PlantedA'
        $DataDir = $planted.Dir
        $BackupDir = Join-Path $DataDir 'backup'
        $CurrentDir = Join-Path $DataDir 'current'
        $decoyAcl = (Get-Acl (Join-Path $planted.Decoy 'system-file.txt')).Sddl
        Test-DataDirTrusted | Should -BeFalse

        New-Item -ItemType Junction -Path (Join-Path $DataDir 'deeper') -Target $planted.Decoy | Out-Null

        Initialize-DataDir 6>$null

        @(Get-ChildItem $TestDrive -Directory -Filter 'PlantedA.untrusted-*').Count | Should -Be 1
        Join-Path $DataDir 'deeper' | Should -Not -Exist   # fresh folder, not the planted one
        (Get-Acl $DataDir).GetOwner([Security.Principal.SecurityIdentifier]).Value | Should -Be 'S-1-5-32-544'
        $writers = @((Get-Acl $DataDir).Access | Where-Object {
            ($_.FileSystemRights -band [Security.AccessControl.FileSystemRights]::Write) -and
            $_.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value -notin 'S-1-5-32-544', 'S-1-5-18' })
        $writers.Count | Should -Be 0
        Get-Content (Join-Path $planted.Decoy 'system-file.txt') | Should -Be 'must survive'
        (Get-Acl (Join-Path $planted.Decoy 'system-file.txt')).Sddl | Should -Be $decoyAcl
        Test-DataDirTrusted | Should -BeTrue
    }

    It 'moves aside a data folder it is not allowed to read, instead of stopping' {
        if (-not (Test-IsAdmin)) { Set-ItResult -Skipped -Because 'it needs administrator rights'; return }
        . $Script
        $DataDir = Join-Path $TestDrive 'Unreadable'
        $BackupDir = Join-Path $DataDir 'backup'
        $CurrentDir = Join-Path $DataDir 'current'
        New-Item -ItemType Directory -Path $DataDir | Out-Null
        $deny = @{ Next = $true }   # first ACL read fails, like a folder locked against admins
        Mock Get-Acl {
            if ($deny.Next) { $deny.Next = $false; throw 'Access is denied' }
            # Then the real ACL (Get-Acl itself would hit this mock again).
            $dir = [string]@($LiteralPath)[0]
            if ($PSVersionTable.PSEdition -eq 'Core') { [IO.FileSystemAclExtensions]::GetAccessControl([IO.DirectoryInfo]$dir) }
            else { [IO.Directory]::GetAccessControl($dir) }
        }
        Initialize-DataDir 6>$null
        @(Get-ChildItem $TestDrive -Directory -Filter 'Unreadable.untrusted-*').Count | Should -Be 1
        Test-DataDirTrusted | Should -BeTrue
    }

    It 'never trusts a data folder someone else can still change, even if Administrators own it' {
        if (-not (Test-IsAdmin)) { Set-ItResult -Skipped -Because 'it needs administrator rights'; return }
        . $Script
        $DataDir = Join-Path $TestDrive 'Raced'
        $BackupDir = Join-Path $DataDir 'backup'
        $CurrentDir = Join-Path $DataDir 'current'
        $me = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        function New-RivalFolder {
            # Owned by Administrators, but with an ACE letting the user write.
            New-Item -ItemType Directory -Path $DataDir | Out-Null
            & icacls.exe $DataDir /setowner '*S-1-5-32-544' /Q | Out-Null
            & icacls.exe $DataDir /grant "*${me}:(OI)(CI)M" /Q | Out-Null
        }
        New-RivalFolder
        Test-DataDirTrusted | Should -BeFalse

        # Folder re-created right after the tool renames it aside: the tool must stop.
        # (.NET calls in the mocks; the cmdlets would hit the mocks again.)
        Mock Rename-Item { [IO.Directory]::Move($LiteralPath, (Join-Path (Split-Path $LiteralPath) $NewName)); New-RivalFolder }
        { Initialize-DataDir 6>$null } | Should -Throw '*already exists*'
        Should -Invoke Rename-Item -Times 1
        $BackupDir | Should -Not -Exist

    }

    It 'moves aside a folder that had something put in it while being made, so it is never trusted later' {
        if (-not (Test-IsAdmin)) { Set-ItResult -Skipped -Because 'it needs administrator rights'; return }
        . $Script
        $DataDir = Join-Path $TestDrive 'Planted'
        $BackupDir = Join-Path $DataDir 'backup'
        $CurrentDir = Join-Path $DataDir 'current'
        $StateFile = Join-Path $DataDir 'state.json'
        # The folder is created via .NET, not New-Item. Plant a file at that point, as a race would.
        $script:RealProtected = ${function:New-ProtectedDirectory}
        $script:PlantOnce = $true
        $script:PlantDir = $DataDir
        Mock New-ProtectedDirectory {
            & $script:RealProtected $Path
            if ($script:PlantOnce -and $Path -eq $script:PlantDir) {
                $script:PlantOnce = $false
                [IO.File]::WriteAllText((Join-Path $Path 'state.json'), '{"InstallDir":"C:\\Windows"}')
            }
        }
        { Initialize-DataDir 6>$null } | Should -Throw '*moved aside*'
        $DataDir | Should -Not -Exist
        @(Get-ChildItem $TestDrive -Directory -Filter 'Planted.untrusted-*').Count | Should -Be 1
        Initialize-DataDir 6>$null   # next run: fresh folder
        $StateFile | Should -Not -Exist
        Test-DataDirTrusted | Should -BeTrue
    }

    It 'renames aside a link at the data folder, and never trusts a linked record' {
        if (-not (Test-IsAdmin)) { Set-ItResult -Skipped -Because 'it needs administrator rights'; return }
        . $Script
        $DataDir = Join-Path $TestDrive 'Linked'
        $BackupDir = Join-Path $DataDir 'backup'
        $CurrentDir = Join-Path $DataDir 'current'
        $StateFile = Join-Path $DataDir 'state.json'
        $target = Join-Path $TestDrive 'LinkTarget'
        New-Item -ItemType Directory -Path $target | Out-Null
        New-Item -ItemType Junction -Path $DataDir -Target $target | Out-Null
        Initialize-DataDir 6>$null
        @(Get-ChildItem $target -Force).Count | Should -Be 0
        @(Get-ChildItem $TestDrive -Directory -Filter 'Linked.untrusted-*').Count | Should -Be 1
        Test-DataDirTrusted | Should -BeTrue
        $hosts = Join-Path $TestDrive 'stand-in-for-hosts.txt'
        Set-Content $hosts 'x'
        New-Item -ItemType SymbolicLink -Path $StateFile -Target $hosts | Out-Null
        Test-DataDirTrusted | Should -BeFalse
    }

    It 'refuses to Restore from a data folder this tool did not make, and deletes nothing' {
        . $Script
        function Get-InstallDir { Join-Path $TestDrive 'NoSuchBetterbird' }
        $planted = New-PlantedDataDir 'PlantedB'
        $DataDir = $planted.Dir
        $BackupDir = Join-Path $DataDir 'backup'
        $CurrentDir = Join-Path $DataDir 'current'
        $StateFile = Join-Path $DataDir 'state.json'
        { Restore-Originals 6>$null } | Should -Throw '*not made by this tool*'
        Get-Content (Join-Path $planted.Decoy 'system-file.txt') | Should -Be 'must survive'
        $StateFile | Should -Exist
    }

    It 'only deletes its own files when removing the data folder' {
        $DataDir = Join-Path $TestDrive 'OwnData'
        $BackupDir = Join-Path $DataDir 'backup'
        $CurrentDir = Join-Path $DataDir 'current'
        $StateFile = Join-Path $DataDir 'state.json'
        New-Item -ItemType Directory -Path $BackupDir, $CurrentDir -Force | Out-Null
        Set-Content (Join-Path $CurrentDir 'messengerWindow.ico') 'x'
        Set-Content $StateFile '{}'
        Set-Content (Join-Path $DataDir 'someone-else.txt') 'keep me'
        Remove-DataDir 6>$null
        Join-Path $DataDir 'someone-else.txt' | Should -Exist
        $StateFile | Should -Not -Exist
        $CurrentDir | Should -Not -Exist
        Remove-Item (Join-Path $DataDir 'someone-else.txt')
        Remove-DataDir 6>$null
        $DataDir | Should -Not -Exist
    }
}

Describe 'What runs where' {
    BeforeEach {
        $Mode = 'system'
        Mock Invoke-Elevated { }
        Mock Install-Icon { }
        Mock Restore-Originals { }
        Mock Set-StartPage { }
        Mock Remove-OldReapplyTask { }
        # Don't read a real state.json from ProgramData here.
        $StateFile = Join-Path $TestDrive 'never-exists.json'
    }

    It 'without administrator rights: only the icon goes to the administrator window, the start page is set here' {
        Invoke-Tool @{ Icon = 'blue'; StartPage = 'C:\x.html' }
        Should -Invoke Invoke-Elevated -Times 1 -ParameterFilter { $Options.Icon -eq 'blue' -and -not $Options.ContainsKey('StartPage') }
        Should -Invoke Set-StartPage -Times 1 -ParameterFilter { $Value -eq 'C:\x.html' }
        Should -Invoke Install-Icon -Times 0
    }

    It 'without administrator rights: an icon change alone does nothing here' {
        Invoke-Tool @{ Icon = 'blue'; Restore = $true }
        Should -Invoke Invoke-Elevated -Times 1
        Should -Invoke Set-StartPage -Times 0
        Should -Invoke Install-Icon -Times 0
        Should -Invoke Restore-Originals -Times 0
    }

    It 'with administrator rights: changes the icon itself, but refuses a start page before changing anything' {
        function Test-Admin { $true }
        Invoke-Tool @{ Icon = 'blue' }
        Should -Invoke Install-Icon -Times 1
        Should -Invoke Invoke-Elevated -Times 0
        { Invoke-Tool @{ Restore = $true; Icon = 'blue'; StartPage = 'C:\x.html' } } | Should -Throw '*never as administrator*'
        Should -Invoke Restore-Originals -Times 0
        Should -Invoke Install-Icon -Times 1   # only the first call
        Should -Invoke Set-StartPage -Times 0
    }

    It 'without administrator rights: the mail popup goes to the administrator window' {
        Mock Set-MailPopup { }
        Invoke-Tool @{ MailPopup = 'yours' }
        Should -Invoke Invoke-Elevated -Times 1 -ParameterFilter { $Options.MailPopup -eq 'yours' }
        Should -Invoke Set-MailPopup -Times 0
    }

    It 'with administrator rights: changes the mail popup here' {
        function Test-Admin { $true }
        Mock Set-MailPopup { }
        Invoke-Tool @{ MailPopup = 'factory' }
        Should -Invoke Set-MailPopup -Times 1 -ParameterFilter { $Name -eq 'factory' }
        Should -Invoke Invoke-Elevated -Times 0
    }

    It 'asks for an icon when only a new-mail icon is given and none was set before' {
        function Test-Admin { $true }
        $DataDir = Join-Path $TestDrive 'NoDataYet'
        { Invoke-Tool @{ NewMail = 'none' } } | Should -Throw '*-Icon as well*'
    }
}

Describe 'Changing and restoring icons' {
    BeforeAll {
        $InstallDir = Join-Path $TestDrive 'Betterbird'
        function Get-InstallDir { $InstallDir }   # the real one only accepts Program Files
        $Target = Join-Path $InstallDir 'chrome\icons\default'
        New-Item -ItemType Directory -Path $Target -Force | Out-Null
        $Exe = Join-Path $InstallDir 'betterbird.exe'
        Set-Content $Exe '' -Encoding ASCII
        # Hand-made icon already in place: must be backed up and restored.
        $Original = Join-Path $Root 'icons\bb\messengerWindow.ico'
        Copy-Item $Original (Join-Path $Target 'messengerWindow.ico')

        $DataDir = Join-Path $TestDrive 'Data'
        $BackupDir = Join-Path $DataDir 'backup'
        $CurrentDir = Join-Path $DataDir 'current'
        $StateFile = Join-Path $DataDir 'state.json'

        $UserAppData = Join-Path $TestDrive 'AppData'
        $UserStartMenu = Join-Path $TestDrive 'StartMenu'
        # Non-ASCII path (char codes, so the file encoding can't change it) must survive the state file.
        $UserDesktop = Join-Path $TestDrive ('Desktop ' + [char]0xE4 + [char]0xE9)
        New-Item -ItemType Directory -Path $UserDesktop, $UserStartMenu -Force | Out-Null
        $Lnk = Join-Path $UserDesktop 'Betterbird.lnk'
        $shell = New-Object -ComObject WScript.Shell
        $s = $shell.CreateShortcut($Lnk); $s.TargetPath = $Exe; $s.Save()
        $OriginalLnkIcon = $shell.CreateShortcut($Lnk).IconLocation
        (Get-Item $Lnk).IsReadOnly = $true   # read-only shortcuts must still be updated
    }

    It 'installs a set with its new-mail icon and backs up the icon that was there' {
        Install-Icon 'blue' $null
        Get-Sha (Join-Path $Target 'messengerWindow.ico') | Should -Be (Get-Sha (Join-Path $Root 'icons\blue\messengerWindow.ico'))
        Get-Sha (Join-Path $Target 'newmail.ico') | Should -Be (Get-Sha (Join-Path $Root 'icons\blue\newmail.ico'))
        Get-Sha (Join-Path $BackupDir 'messengerWindow.ico') | Should -Be (Get-Sha $Original)
        Join-Path $BackupDir 'newmail.ico' | Should -Not -Exist
    }

    It 'points the shortcut at the icon, keeps it read-only, and records its path intact' {
        $shell = New-Object -ComObject WScript.Shell
        $shell.CreateShortcut($Lnk).IconLocation | Should -Be ((Join-Path $CurrentDir 'messengerWindow.ico') + ',0')
        (Get-Item $Lnk).IsReadOnly | Should -BeTrue
        (Read-State).Shortcuts | Should -Contain $Lnk
    }

    It 'installs green2 with its own new-mail icon' {
        Install-Icon 'green2' $null
        Get-Sha (Join-Path $Target 'messengerWindow.ico') | Should -Be (Get-Sha (Join-Path $Root 'icons\green2\messengerWindow.ico'))
        Get-Sha (Join-Path $Target 'newmail.ico') | Should -Be (Get-Sha (Join-Path $Root 'icons\green2\newmail.ico'))
        (Read-State).NewMail | Should -Be 'green2'
    }

    It 'removes the new-mail icon when asked for Betterbird''s own' {
        Install-Icon 'green2' 'none'
        Join-Path $Target 'newmail.ico' | Should -Not -Exist
        (Read-State).NewMail | Should -Be 'none'
    }

    It 'uses a different set''s new-mail icon with -NewMail' {
        Install-Icon 'green2' 'newmail-sm'
        Get-Sha (Join-Path $Target 'newmail.ico') | Should -Be (Get-Sha (Join-Path $Root 'icons\newmail-sm\newmail.ico'))
    }

    It 'replaces an icon file that the first version left read-only' {
        (Get-Item (Join-Path $Target 'messengerWindow.ico')).IsReadOnly = $true
        Install-Icon 'uk' $null
        Get-Sha (Join-Path $Target 'messengerWindow.ico') | Should -Be (Get-Sha (Join-Path $Root 'icons\uk\messengerWindow.ico'))
        (Get-Item (Join-Path $Target 'messengerWindow.ico')).IsReadOnly = $true
    }

    It 'restores the original icons and shortcut and removes its data' {
        Restore-Originals
        Get-Sha (Join-Path $Target 'messengerWindow.ico') | Should -Be (Get-Sha $Original)
        Join-Path $Target 'newmail.ico' | Should -Not -Exist
        (New-Object -ComObject WScript.Shell).CreateShortcut($Lnk).IconLocation | Should -Be $OriginalLnkIcon
        (Get-Item $Lnk).IsReadOnly | Should -BeTrue
        $DataDir | Should -Not -Exist
    }

    It 'refuses a set that only has a new-mail icon' {
        { Install-Icon 'newmail-sm' $null } | Should -Throw
    }
}

Describe 'A fresh install, which has no icon files' {
    BeforeAll {
        $InstallDir = Join-Path $TestDrive 'Fresh'
        function Get-InstallDir { $InstallDir }
        $Target = Join-Path $InstallDir 'chrome\icons\default'   # doesn't exist yet: the tool must create it
        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
        Set-Content (Join-Path $InstallDir 'betterbird.exe') '' -Encoding ASCII
        $DataDir = Join-Path $TestDrive 'FreshData'
        $BackupDir = Join-Path $DataDir 'backup'
        $CurrentDir = Join-Path $DataDir 'current'
        $StateFile = Join-Path $DataDir 'state.json'
        $UserAppData = Join-Path $TestDrive 'FreshAppData'
        $UserDesktop = Join-Path $TestDrive 'FreshDesktop'
        $UserStartMenu = Join-Path $TestDrive 'FreshStartMenu'
        New-Item -ItemType Directory -Path $UserDesktop | Out-Null
        Set-Content (Join-Path $UserDesktop 'broken.lnk') 'this is not a shortcut'   # must not stop anything
    }

    It 'creates the icon folder if it is missing, and is not stopped by a broken shortcut' {
        { Install-Icon 'green' $null 6>$null } | Should -Not -Throw
        Join-Path $Target 'messengerWindow.ico' | Should -Exist
        Restore-Originals 6>$null
    }

    It 'adds the icons, then Restore removes them so Betterbird uses its built-in icon' {
        Install-Icon 'blue' $null
        Join-Path $Target 'messengerWindow.ico' | Should -Exist
        Join-Path $Target 'newmail.ico' | Should -Exist
        @(Get-ChildItem $BackupDir).Count | Should -Be 0
        Restore-Originals
        @(Get-ChildItem $Target).Count | Should -Be 0
        $DataDir | Should -Not -Exist
    }

    It 'backs up a hand-made new-mail icon, and -NewMail none uses the built-in one' {
        $own = Join-Path $Root 'icons\bb-green\newmail.ico'
        Copy-Item $own (Join-Path $Target 'newmail.ico')
        Install-Icon 'uk' $null
        Get-Sha (Join-Path $Target 'newmail.ico') | Should -Be (Get-Sha (Join-Path $Root 'icons\uk\newmail.ico'))
        Get-Sha (Join-Path $BackupDir 'newmail.ico') | Should -Be (Get-Sha $own)
        Install-Icon 'blue' 'none'
        Join-Path $Target 'newmail.ico' | Should -Not -Exist
        (Read-State).NewMail | Should -Be 'none'
        Install-Icon 'green' $null   # set with a new-mail icon after -NewMail none: backup must survive
        Get-Sha (Join-Path $BackupDir 'newmail.ico') | Should -Be (Get-Sha $own)
        Restore-Originals
        Get-Sha (Join-Path $Target 'newmail.ico') | Should -Be (Get-Sha $own)
        Remove-Item (Join-Path $Target 'newmail.ico')
    }

    It 'records where the icons go before copying, so an interrupted run can be restored' {
        Copy-Item (Join-Path $Root 'icons\bb\messengerWindow.ico') (Join-Path $Target 'messengerWindow.ico')
        Mock Copy-CurrentToInstall { throw 'power cut' }
        { Install-Icon 'blue' $null } | Should -Throw 'power cut'
        (Read-State).InstallDir | Should -Be $InstallDir
        Restore-Originals
        Get-Sha (Join-Path $Target 'messengerWindow.ico') | Should -Be (Get-Sha (Join-Path $Root 'icons\bb\messengerWindow.ico'))
        $DataDir | Should -Not -Exist
        Remove-Item (Join-Path $Target 'messengerWindow.ico')
    }

    It 'never deletes the backup when the record is missing' {
        $own = Join-Path $Root 'icons\bb\messengerWindow.ico'
        Copy-Item $own (Join-Path $Target 'messengerWindow.ico')
        Install-Icon 'blue' $null
        Remove-Item $StateFile
        Restore-Originals 6>$null
        Get-Sha (Join-Path $BackupDir 'messengerWindow.ico') | Should -Be (Get-Sha $own)
        Set-Content $StateFile '{}'   # empty record: same
        Restore-Originals 6>$null
        Get-Sha (Join-Path $BackupDir 'messengerWindow.ico') | Should -Be (Get-Sha $own)
    }

    It 'keeps the backup when Betterbird''s folder has gone' {
        Install-Icon 'blue' $null   # backup from the previous test is still there
        Remove-Item $InstallDir -Recurse -Force
        Restore-Originals 6>$null
        Get-Sha (Join-Path $BackupDir 'messengerWindow.ico') | Should -Be (Get-Sha (Join-Path $Root 'icons\bb\messengerWindow.ico'))
        (Read-State).InstallDir | Should -Be $InstallDir   # kept so the backup can go back if the folder returns
        Join-Path $CurrentDir 'messengerWindow.ico' | Should -Exist   # kept too, to recognise our icons later

        # Folder comes back with our icons in it: a second Restore finishes the job.
        New-Item -ItemType Directory -Path $Target -Force | Out-Null
        Copy-Item (Join-Path $CurrentDir '*.ico') $Target
        Restore-Originals 6>$null
        Get-Sha (Join-Path $Target 'messengerWindow.ico') | Should -Be (Get-Sha (Join-Path $Root 'icons\bb\messengerWindow.ico'))
        Join-Path $Target 'newmail.ico' | Should -Not -Exist
        $DataDir | Should -Not -Exist
    }
}

Describe 'Shortcuts' {
    BeforeAll {
        $InstallDir = Join-Path $TestDrive 'Bird [old]'   # brackets must not act as a wildcard
        function Get-InstallDir { $InstallDir }
        New-Item -ItemType Directory -Path $InstallDir | Out-Null
        $Exe = Join-Path $InstallDir 'betterbird.exe'
        Set-Content -LiteralPath $Exe '' -Encoding ASCII
        $DataDir = Join-Path $TestDrive 'ShortcutData'
        $BackupDir = Join-Path $DataDir 'backup'
        $CurrentDir = Join-Path $DataDir 'current'
        $StateFile = Join-Path $DataDir 'state.json'
        $UserAppData = Join-Path $TestDrive 'ShortcutAppData'
        $UserStartMenu = Join-Path $TestDrive 'Start [menu]'
        $UserDesktop = Join-Path $TestDrive 'Desk [1]'
        New-Item -ItemType Directory -Path $UserDesktop, (Join-Path $UserStartMenu 'Programs') | Out-Null
        $shell = New-Object -ComObject WScript.Shell
        $Desk = Join-Path $UserDesktop 'Betterbird.lnk'
        $Menu = Join-Path $UserStartMenu 'Programs\Betterbird.lnk'
        foreach ($l in $Desk, $Menu) { $s = $shell.CreateShortcut($l); $s.TargetPath = $Exe; $s.Save() }
    }

    It 'finds shortcuts in folders with brackets in their names, and never follows a link to another folder' {
        $elsewhere = Join-Path $TestDrive 'Elsewhere'
        New-Item -ItemType Directory -Path $elsewhere | Out-Null
        $far = Join-Path $elsewhere 'Betterbird.lnk'
        $s = (New-Object -ComObject WScript.Shell).CreateShortcut($far); $s.TargetPath = $Exe; $s.Save()
        New-Item -ItemType Junction -Path (Join-Path $UserStartMenu 'Programs\Linked') -Target $elsewhere | Out-Null
        $found = @(Find-Shortcuts @($Exe))
        $found | Should -Contain $Desk
        $found | Should -Contain $Menu
        $found.Count | Should -Be 2
    }

    It 'Restore leaves alone a shortcut given another icon since' {
        Install-Icon 'blue' $null
        $shell = New-Object -ComObject WScript.Shell
        $s = $shell.CreateShortcut($Menu); $s.IconLocation = 'C:\Windows\System32\shell32.dll,3'; $s.Save()
        Restore-Originals
        $shell.CreateShortcut($Menu).IconLocation | Should -Be 'C:\Windows\System32\shell32.dll,3'
        $shell.CreateShortcut($Desk).IconLocation | Should -Not -Match 'ShortcutData'
    }
}

Describe 'Start page' {
    BeforeAll {
        $FakeInstall = 'C:\Program Files\Betterbird'
        function Get-InstallDir { $FakeInstall }
        $UserAppData = Join-Path $TestDrive 'AppData'
        $Tb = Join-Path $UserAppData 'Thunderbird'
        $ProfileA = Join-Path $Tb 'Profiles\a.default'
        $ProfileB = Join-Path $TestDrive 'Elsewhere\b.default'
        $ProfileT = Join-Path $Tb 'Profiles\t.thunderbird'   # used by Thunderbird
        $ProfileN = Join-Path $Tb 'Profiles\n.never-used'    # never opened: no compatibility.ini
        New-Item -ItemType Directory -Path $ProfileA, $ProfileB, $ProfileT, $ProfileN -Force | Out-Null
        Set-Content (Join-Path $Tb 'profiles.ini') @(
            '[Profile0]', 'Name=a', 'IsRelative=1', 'Path=Profiles/a.default', '',
            '[Profile1]', 'Name=b', 'IsRelative=0', "Path=$ProfileB", '',
            '[Profile2]', 'Name=t', 'IsRelative=1', 'Path=Profiles/t.thunderbird', '',
            '[Profile3]', 'Name=n', 'IsRelative=1', 'Path=Profiles/n.never-used', '',
            '[Profile4]', 'Name=a-again', 'IsRelative=0', "Path=$ProfileA", '',
            '[General]', 'StartWithLastProfile=1')
        foreach ($p in $ProfileA, $ProfileB) {
            Set-Content (Join-Path $p 'compatibility.ini') @('[Compatibility]', "LastAppDir=$FakeInstall")
        }
        Set-Content (Join-Path $ProfileT 'compatibility.ini') @('[Compatibility]', 'LastAppDir=C:\Program Files\Mozilla Thunderbird')
        $PrefsT = Join-Path $ProfileT 'prefs.js'
        $PrefsTOriginal = "user_pref(`"mailnews.start_page.url`", `"https://thunderbird.example`");`r`n"
        [IO.File]::WriteAllText($PrefsT, $PrefsTOriginal)

        $PrefsA = Join-Path $ProfileA 'prefs.js'
        $PrefsB = Join-Path $ProfileB 'prefs.js'
        $PrefsAOriginal = "// Mozilla User Preferences`r`n" +
            "user_pref(`"mail.example`", 1);`r`n" +
            "user_pref(`"mailnews.start_page.url`", `"https://example.org`");`r`n"
        [IO.File]::WriteAllText($PrefsA, $PrefsAOriginal)

        $Page = Join-Path $TestDrive 'My Manual\manual.html'
        New-Item -ItemType Directory -Path (Split-Path $Page) -Force | Out-Null
        Set-Content $Page '<p>manual</p>'
        $PageUrl = ([Uri]$Page).AbsoluteUri

        function Get-Prefs([string]$Path) { [IO.File]::ReadAllText($Path) }
        function Get-UrlLines([string]$Path) { @((Get-Prefs $Path) -split "`r?`n" | Where-Object { $_ -match 'start_page\.url' }) }
    }

    It 'finds only the profiles Betterbird has used, each once' {
        $found = @(Get-Profiles $FakeInstall)
        $found.Count | Should -Be 2
        $found | Should -Contain $ProfileA
        $found | Should -Contain $ProfileB
    }

    It 'never touches a Thunderbird profile or one that was never used' {
        Set-StartPage 'https://example.net/x'
        Get-Prefs $PrefsT | Should -Be $PrefsTOriginal
        Join-Path $ProfileT $SideFile | Should -Not -Exist
        Join-Path $ProfileN 'prefs.js' | Should -Not -Exist
        Set-StartPage 'Off'
    }

    It 'does not change anything while Betterbird is running and no one can be asked' {
        function Get-Betterbird { @([pscustomobject]@{ Name = 'betterbird' }) }
        $before = Get-Prefs $PrefsA
        { Set-StartPage 'https://example.net/y' } | Should -Throw '*Betterbird is open*'
        Get-Prefs $PrefsA | Should -Be $before
    }

    It 'warns when user.js would override the start page' {
        $userJs = Join-Path $ProfileA 'user.js'
        Set-Content $userJs 'user_pref("mailnews.start_page.url", "https://pinned.example");'
        (Set-StartPage 'https://example.net/z' 6>&1 | Out-String) | Should -Match 'user\.js'
        (Get-StartPageStatus $FakeInstall) -join "`n" | Should -Match 'overridden by user\.js'
        Remove-Item $userJs
        Set-StartPage 'Off'
    }

    It 'sets the page in every profile, keeping a backup and the previous page' {
        Set-StartPage $Page
        foreach ($p in $PrefsA, $PrefsB) {
            Get-UrlLines $p | Should -Be "user_pref(`"mailnews.start_page.url`", `"$PageUrl`");"
            Get-Prefs $p | Should -Match ([regex]::Escape('user_pref("mailnews.start_page.enabled", true);'))
        }
        Get-Prefs $PrefsA | Should -Match ([regex]::Escape('user_pref("mail.example", 1);'))
        Get-Prefs "$PrefsA.betterbird-icons.bak" | Should -Be $PrefsAOriginal
        Get-Prefs (Join-Path $ProfileA $SideFile) | Should -Match ([regex]::Escape('user_pref("mailnews.start_page.url", "https://example.org");'))
        Join-Path $ProfileA 'user.js' | Should -Not -Exist   # nothing that overrides Betterbird's own settings
    }

    It 'writes prefs.js without a byte-order mark, and leaves no temporary file' {
        ([IO.File]::ReadAllBytes($PrefsA)[0..2] -join ',') | Should -Not -Be '239,187,191'
        "$PrefsA.betterbird-icons.tmp" | Should -Not -Exist
    }

    It 'keeps the original previous page when set again' {
        Set-StartPage 'https://example.net/start'
        Get-UrlLines $PrefsA | Should -Be 'user_pref("mailnews.start_page.url", "https://example.net/start");'
        Get-Prefs (Join-Path $ProfileA $SideFile) | Should -Match ([regex]::Escape('"https://example.org"'))
    }

    It 'turns off: the previous page comes back exactly, other settings kept' {
        Set-StartPage 'Off'
        Get-UrlLines $PrefsA | Should -Be 'user_pref("mailnews.start_page.url", "https://example.org");'
        Get-Prefs $PrefsA | Should -Not -Match 'start_page\.enabled'
        Get-Prefs $PrefsA | Should -Match ([regex]::Escape('user_pref("mail.example", 1);'))
        @(Get-UrlLines $PrefsB).Count | Should -Be 0
        Join-Path $ProfileA $SideFile | Should -Not -Exist
        Join-Path $ProfileB $SideFile | Should -Not -Exist
    }

    It 'does nothing when turning off a page this script did not set' {
        $before = Get-Prefs $PrefsA
        Set-StartPage 'Off'
        Get-Prefs $PrefsA | Should -Be $before
    }

    It 'cannot be used to add other settings through the address' {
        foreach ($evil in "https://example.org/`"); user_pref(`"evil.pref`", 1); (`"",
                          "https://example.org/a`r`nuser_pref(`"evil.pref`", 1);") {
            try { Set-StartPage $evil } catch { $null = $_ }
            Get-Prefs $PrefsA | Should -Not -Match '(?m)^user_pref\("evil\.pref"'
        }
        Set-StartPage 'Off'
    }

    It 'rejects a missing file and a file that is not HTML' {
        { Set-StartPage (Join-Path $TestDrive 'missing.html') } | Should -Throw
        $txt = Join-Path $TestDrive 'notes.txt'; Set-Content $txt 'x'
        { Set-StartPage $txt } | Should -Throw
    }

    It 'never opens profiles with administrator rights' {
        function Test-Admin { $true }
        $DataDir = Join-Path $TestDrive 'NoData'   # Status must not read the real one
        Mock Get-Profiles { throw 'must not look at profiles' }
        $before = Get-Prefs $PrefsA
        { Set-StartPage $Page } | Should -Throw '*never as administrator*'
        { Set-StartPage 'Off' } | Should -Throw '*never as administrator*'
        { Set-StartPageEnabled -On $true } | Should -Throw '*never as administrator*'
        Get-Prefs $PrefsA | Should -Be $before
        (Show-Status 6>&1 | Out-String) | Should -Match 'without administrator rights to see it'
        Should -Invoke Get-Profiles -Times 0
    }

    It 'turns a file name with # or % into the right address' {
        $odd = Join-Path $TestDrive 'Odd\manual#1 100%.html'
        New-Item -ItemType Directory -Path (Split-Path $odd) -Force | Out-Null
        Set-Content -LiteralPath $odd '<p>odd</p>'
        Set-StartPage $odd
        Get-UrlLines $PrefsA | Should -Match ([regex]::Escape('manual%231%20100%25.html"'))
        (Get-StartPageStatus $FakeInstall) -join "`n" | Should -Not -Match 'FILE NOT FOUND'
        Set-StartPage 'Off'
    }

    It 'reports a start page file that no longer exists' {
        Set-StartPage $Page
        Remove-Item $Page
        (Get-StartPageStatus $FakeInstall) -join "`n" | Should -Match 'FILE NOT FOUND'
        Set-StartPage 'Off'
    }

    It 'turns the start page off and on without changing the address' {
        Set-StartPage 'https://example.net/keep'
        Set-StartPageEnabled -On $false
        foreach ($p in $PrefsA, $PrefsB) {
            Get-UrlLines $p | Should -Be 'user_pref("mailnews.start_page.url", "https://example.net/keep");'
            Get-Prefs $p | Should -Match ([regex]::Escape('user_pref("mailnews.start_page.enabled", false);'))
        }
        Get-Prefs (Join-Path $ProfileA $SideFile) | Should -Match ([regex]::Escape('"https://example.org"'))
        Get-StartPageMode | Should -Be 'off'
        (Get-StartPageStatus $FakeInstall) -join "`n" | Should -Match '\(off\)'
        Set-StartPageEnabled -On $true
        Get-Prefs $PrefsA | Should -Match ([regex]::Escape('user_pref("mailnews.start_page.enabled", true);'))
        Get-UrlLines $PrefsA | Should -Be 'user_pref("mailnews.start_page.url", "https://example.net/keep");'
        Get-StartPageMode | Should -Be 'on'
        Get-Prefs $PrefsT | Should -Be $PrefsTOriginal
        Set-StartPage 'Off'
        Get-UrlLines $PrefsA | Should -Be 'user_pref("mailnews.start_page.url", "https://example.org");'
        Join-Path $ProfileA $SideFile | Should -Not -Exist
    }

    It 'turns on a start page that was already switched off' {
        $off = "user_pref(`"mailnews.start_page.url`", `"https://example.org`");`r`n" +
            "user_pref(`"mailnews.start_page.enabled`", false);`r`n"
        [IO.File]::WriteAllText($PrefsA, "// Mozilla User Preferences`r`nuser_pref(`"mail.example`", 1);`r`n" + $off)
        [IO.File]::WriteAllText($PrefsB, $off)
        foreach ($dir in $ProfileA, $ProfileB) {
            $side = Join-Path $dir $SideFile
            if (Test-Path -LiteralPath $side) { Remove-Item -LiteralPath $side }
        }
        Get-StartPageMode | Should -Be 'off'
        Test-PreviousStartPageSaved | Should -BeFalse
        Set-StartPageEnabled -On $true
        Get-Prefs $PrefsA | Should -Match ([regex]::Escape('user_pref("mail.example", 1);'))
        Get-Prefs $PrefsA | Should -Match ([regex]::Escape('user_pref("mailnews.start_page.enabled", true);'))
        Get-UrlLines $PrefsA | Should -Be 'user_pref("mailnews.start_page.url", "https://example.org");'
        Test-PreviousStartPageSaved | Should -BeTrue
        Set-StartPage 'Off'
        Get-Prefs $PrefsA | Should -Match ([regex]::Escape('user_pref("mailnews.start_page.enabled", false);'))
        Join-Path $ProfileA $SideFile | Should -Not -Exist
    }

    It 'reports a mix when one profile is off' {
        [IO.File]::WriteAllText($PrefsA, "user_pref(`"mailnews.start_page.enabled`", true);`r`n")
        [IO.File]::WriteAllText($PrefsB, "user_pref(`"mailnews.start_page.enabled`", false);`r`n")
        Get-StartPageMode | Should -Be 'mixed'
    }
}

Describe 'A portable Betterbird, or one in your own folder' {
    BeforeAll {
        # The layout of the real portable zip: BetterbirdLauncher.exe, core\betterbird.exe, profile\.
        $Root = Split-Path $PSScriptRoot -Parent
        $PortableRoot = Join-Path $TestDrive 'BetterbirdPortable'
        New-Item -ItemType Directory -Path (Join-Path $PortableRoot 'core\chrome\icons\default'), (Join-Path $PortableRoot 'profile') -Force | Out-Null
        Set-Content (Join-Path $PortableRoot 'BetterbirdLauncher.exe') '' -Encoding ASCII
        Set-Content (Join-Path $PortableRoot 'core\betterbird.exe') '' -Encoding ASCII
        $OwnInstall = Join-Path $TestDrive 'MyBetterbird'
        New-Item -ItemType Directory -Path $OwnInstall | Out-Null
        Set-Content (Join-Path $OwnInstall 'betterbird.exe') '' -Encoding ASCII
    }

    It 'recognises the portable folder, its core folder, and a Betterbird installed in your own folder' {
        $p = Resolve-OwnFolder $PortableRoot
        $p.AppDir | Should -Be (Join-Path $PortableRoot 'core')
        $p.Launcher | Should -Be (Join-Path $PortableRoot 'BetterbirdLauncher.exe')
        $p.ProfileDir | Should -Be (Join-Path $PortableRoot 'profile')
        $p.DataDir | Should -Be (Join-Path $PortableRoot 'BetterbirdIcons')
        (Resolve-OwnFolder (Join-Path $PortableRoot 'core')).AppDir | Should -Be (Join-Path $PortableRoot 'core')
        $o = Resolve-OwnFolder $OwnInstall
        $o.AppDir | Should -Be $OwnInstall
        $o.Launcher | Should -BeNullOrEmpty
        $o.ProfileDir | Should -BeNullOrEmpty
    }

    It 'follows the profile location the launcher saved' {
        $elsewhere = Join-Path $TestDrive 'MovedProfile'
        New-Item -ItemType Directory -Path $elsewhere | Out-Null
        Set-Content (Join-Path $PortableRoot 'last-profile-location.txt') $elsewhere
        (Resolve-OwnFolder $PortableRoot).ProfileDir | Should -Be $elsewhere
        [IO.File]::WriteAllText((Join-Path $PortableRoot 'last-profile-location.txt'), "`"$elsewhere`"`r`n", [Text.Encoding]::Unicode)   # UTF-16, quoted
        (Resolve-OwnFolder $PortableRoot).ProfileDir | Should -Be $elsewhere
        Remove-Item (Join-Path $PortableRoot 'last-profile-location.txt')
    }

    It 'refuses a folder without Betterbird, and one installed for all users' {
        { Resolve-OwnFolder (Join-Path $TestDrive 'nothing-here') } | Should -Throw
        $empty = Join-Path $TestDrive 'Empty'; New-Item -ItemType Directory -Path $empty | Out-Null
        { Resolve-OwnFolder $empty } | Should -Throw '*no betterbird.exe*'
        function Test-SystemWideInstall { $true }
        { Resolve-OwnFolder $OwnInstall } | Should -Throw '*for all users*'
    }

    Context 'changing the icon and the start page' {
        BeforeAll {
            $Mode = 'own'
            $own = Resolve-OwnFolder $PortableRoot
            $AppDir = $own.AppDir; $Launcher = $own.Launcher; $ProfileDir = $own.ProfileDir
            $DataDir = $own.DataDir
            $BackupDir = Join-Path $DataDir 'backup'; $CurrentDir = Join-Path $DataDir 'current'; $StateFile = Join-Path $DataDir 'state.json'
            $Target = Join-Path $AppDir 'chrome\icons\default'
            $UserAppData = Join-Path $TestDrive 'PortableAppData'
            $UserStartMenu = Join-Path $TestDrive 'PortableStartMenu'
            $UserDesktop = Join-Path $TestDrive 'PortableDesktop'
            New-Item -ItemType Directory -Path $UserDesktop | Out-Null
            $Lnk = Join-Path $UserDesktop 'Betterbird Portable.lnk'   # shortcuts usually point at the launcher
            $s = (New-Object -ComObject WScript.Shell).CreateShortcut($Lnk); $s.TargetPath = $Launcher; $s.Save()
            [IO.File]::WriteAllText((Join-Path $ProfileDir 'prefs.js'), "user_pref(`"mailnews.start_page.url`", `"https://before.example`");`r`n")
        }

        It 'changes the icon in the portable folder, keeps its data there, and updates a launcher shortcut' {
            Get-InstallDir | Should -Be $AppDir
            Install-Icon 'blue' $null
            Get-Sha (Join-Path $Target 'messengerWindow.ico') | Should -Be (Get-Sha (Join-Path $Root 'icons\blue\messengerWindow.ico'))
            $StateFile | Should -Exist
            (New-Object -ComObject WScript.Shell).CreateShortcut($Lnk).IconLocation | Should -Be ((Join-Path $CurrentDir 'messengerWindow.ico') + ',0')
        }

        It 'restores the portable folder and shortcut' {
            Restore-Originals
            @(Get-ChildItem $Target).Count | Should -Be 0
            (New-Object -ComObject WScript.Shell).CreateShortcut($Lnk).IconLocation | Should -Not -Match 'BetterbirdIcons'
            $DataDir | Should -Not -Exist
        }

        It 'sets the start page in the portable profile only' {
            @(Get-Profiles $AppDir) | Should -Be @($ProfileDir)
            Set-StartPage 'https://after.example/'
            [IO.File]::ReadAllText((Join-Path $ProfileDir 'prefs.js')) | Should -Match 'https://after\.example/'
            Set-StartPage 'Off'
            [IO.File]::ReadAllText((Join-Path $ProfileDir 'prefs.js')) | Should -Match 'https://before\.example'
        }

        It 'keeps working after the portable folder has been moved' {
            New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
            Copy-Item (Join-Path $Root 'icons\bb\messengerWindow.ico') (Join-Path $BackupDir 'messengerWindow.ico')
            Set-Content $StateFile '{"Icon":"green","InstallDir":"D:\\Where It Was\\core"}'
            # State as the tool left it before the move: icon installed, and in the data folder.
            New-Item -ItemType Directory -Path $CurrentDir -Force | Out-Null
            Copy-Item (Join-Path $Root 'icons\green\messengerWindow.ico') $CurrentDir
            Copy-Item (Join-Path $Root 'icons\green\messengerWindow.ico') $Target
            Install-Icon 'blue' $null 6>$null
            Restore-Originals 6>$null
            Get-Sha (Join-Path $Target 'messengerWindow.ico') | Should -Be (Get-Sha (Join-Path $Root 'icons\bb\messengerWindow.ico'))
            Remove-Item (Join-Path $Target 'messengerWindow.ico')
            $DataDir | Should -Not -Exist
        }

        It 'never mixes up the backup of another Betterbird in your own folder, which share a data folder' {
            $Launcher = $null; $ProfileDir = $null; $AppDir = $OwnInstall   # per-user install, not portable
            New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
            Copy-Item (Join-Path $Root 'icons\bb\messengerWindow.ico') (Join-Path $BackupDir 'messengerWindow.ico')
            $other = Join-Path $TestDrive 'OtherBetterbird'   # still installed
            New-Item -ItemType Directory -Path $other | Out-Null
            Set-Content (Join-Path $other 'betterbird.exe') '' -Encoding ASCII
            Set-Content $StateFile (@{ Icon = 'green'; InstallDir = $other } | ConvertTo-Json)
            { Install-Icon 'blue' $null } | Should -Throw '*Restore that one first*'
            { Restore-Originals } | Should -Throw '*belongs to*'
            Join-Path $BackupDir 'messengerWindow.ico' | Should -Exist
            Join-Path $OwnInstall 'chrome' | Should -Not -Exist
            Remove-Item $DataDir -Recurse -Force
        }

        It 'carries on when the Betterbird recorded in the shared data folder has gone (moved or reinstalled)' {
            $Launcher = $null; $ProfileDir = $null; $AppDir = $OwnInstall
            New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
            Copy-Item (Join-Path $Root 'icons\bb\messengerWindow.ico') (Join-Path $BackupDir 'messengerWindow.ico')
            Set-Content $StateFile (@{ Icon = 'green'; InstallDir = (Join-Path $TestDrive 'No Longer Here') } | ConvertTo-Json)
            Install-Icon 'blue' $null 6>$null
            Restore-Originals 6>$null
            Get-Sha (Join-Path $OwnInstall 'chrome\icons\default\messengerWindow.ico') | Should -Be (Get-Sha (Join-Path $Root 'icons\bb\messengerWindow.ico'))
            Remove-Item (Join-Path $OwnInstall 'chrome') -Recurse -Force
            $DataDir | Should -Not -Exist
        }
    }

    It 'accepts a drive root as the folder' {
        { Resolve-OwnFolder ($env:SystemDrive + '\') } | Should -Throw "*in $env:SystemDrive\ (no*"
    }

    It 'without administrator rights, just carries on' {
        Confirm-StandardUser @{} | Should -BeTrue
    }

    It 'with administrator rights, asks: start again as a standard user, continue, or quit' {
        function Test-Admin { $true }
        { Confirm-StandardUser @{} 6>$null } | Should -Throw '*does not need*'   # no one to ask
        function Test-Interactive { $true }
        function Invoke-AsStandardUser { $script:relaunched = $true }
        Mock Read-Host { '2' }
        Confirm-StandardUser @{} 6>$null | Should -BeTrue
        Mock Read-Host { 'q' }
        Confirm-StandardUser @{} 6>$null | Should -BeFalse
        Mock Read-Host { '1' }
        $script:relaunched = $false
        Confirm-StandardUser @{} 6>$null | Should -BeFalse
        $script:relaunched | Should -BeTrue
        $Force = $true
        Mock Read-Host { throw 'must not ask' }
        Confirm-StandardUser @{} 6>$null | Should -BeTrue
    }

    It 'starts again as a standard user with the same options' {
        Mock Start-Process { }
        Invoke-AsStandardUser @{ Portable = 'D:\My Portable'; Icon = 'blue' } 6>$null
        Should -Invoke Start-Process -Times 1 -ParameterFilter {
            $FilePath -eq (Join-Path $env:SystemRoot 'System32\runas.exe') -and
            $ArgumentList -like '/trustlevel:0x20000 "\"*\WindowsPowerShell\v1.0\powershell.exe\" *' -and
            $ArgumentList -like '*-Portable \"D:\My Portable\"*' -and $ArgumentList -like '*-Icon \"blue\"*'
        }
        { Invoke-AsStandardUser @{ Icon = 'a"b' } } | Should -Throw '*quote*'
    }

    It 'keeps a folder ending in a backslash intact when starting again as a standard user' {
        Mock Start-Process { }
        Invoke-AsStandardUser @{ Portable = 'D:\' } 6>$null
        # D:\ becomes "D:\\" for PowerShell; runas's quoted argument escapes those backslashes and the quote again.
        Should -Invoke Start-Process -Times 1 -ParameterFilter { $ArgumentList -like '*-Portable \"D:\\\\\""' }
    }
}
