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
    function Send-ShellNotify { }
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
        Get-DotColourName (Join-Path $Root 'icons\green2\newmail.ico') | Should -Be 'Red'
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

    It 'offers every window set and Betterbird''s own for the mail popup' {
        @(Get-PopupMenuChoices) | Should -Be (@(Get-MenuIconSets 'window') + 'factory')
        foreach ($name in Get-PopupMenuChoices) {
            $files = Get-PopupBytes -Name $name
            Test-PopupPng -Bytes $files['chrome/messenger/content/branding/icon64.png'] -Size 64 | Should -BeTrue -Because $name
            Test-PopupPng -Bytes $files['chrome/messenger/content/branding/icon128.png'] -Size 128 | Should -BeTrue -Because $name
        }
        Resolve-PopupName 'yours' | Should -Be 'blue'
        { Set-MailPopup -Name 'green' } | Should -Throw '*no mail popup*'
        { Set-MailPopup -Name 'newmail-sm' } | Should -Throw '*no mail popup*'
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
        Get-MailPopupName | Should -Be 'blue'
        Get-AceText $omni | Should -Be $beforeAcl
        # Betterbird's own pictures are kept inside omni.ja, once.
        [Text.Encoding]::ASCII.GetString((Read-JarBytes $omni ('chrome/messenger/content/branding/icon64.png' + $PopupSaved))) | Should -Be 'old-64'
        Set-MailPopup -Name 'yours'
        [Text.Encoding]::ASCII.GetString((Read-JarBytes $omni ('chrome/messenger/content/branding/icon128.png' + $PopupSaved))) | Should -Be 'old-128'
        # factory puts back exactly what this build had, not the copy that comes with the tool.
        Set-MailPopup -Name 'factory'
        [Text.Encoding]::ASCII.GetString((Read-JarBytes $omni 'chrome/messenger/content/branding/icon64.png')) | Should -Be 'old-64'
        [Text.Encoding]::ASCII.GetString((Read-JarBytes $omni 'chrome/messenger/content/branding/icon128.png')) | Should -Be 'old-128'
        [Text.Encoding]::ASCII.GetString((Read-JarBytes $omni 'chrome/keep.txt')) | Should -Be 'keep-me'
        $check = [IO.Compression.ZipFile]::OpenRead($omni)
        try {
            @($check.Entries | Where-Object { $_.FullName -like "*$PopupSaved" }).Count | Should -Be 0
            $check.Entries.Count | Should -Be 4
        }
        finally { $check.Dispose() }
        Get-MailPopupName | Should -BeNullOrEmpty   # not a picture this tool ships
        $stamp = (Get-Item -LiteralPath $omni).LastWriteTimeUtc
        Set-MailPopup -Name 'factory'
        (Get-Item -LiteralPath $omni).LastWriteTimeUtc | Should -Be $stamp
    }

    It 'uses the factory copy that comes with the tool when an older version kept no original' {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $dir = Join-Path $TestDrive 'PopupOld'
        New-Item -ItemType Directory -Path $dir | Out-Null
        $omni = Join-Path $dir 'omni.ja'
        $yours = Get-PopupBytes -Name 'yours'
        $zip = [IO.Compression.ZipFile]::Open($omni, 'Create')
        try {
            foreach ($name in $yours.Keys) {
                $out = $zip.CreateEntry($name).Open()
                try { $out.Write($yours[$name], 0, $yours[$name].Length) } finally { $out.Dispose() }
            }
        }
        finally { $zip.Dispose() }
        $Mode = 'own'
        $AppDir = $dir
        Get-MailPopupName | Should -Be 'blue'
        Mock Write-Warn { }
        Set-MailPopup -Name 'factory' 6>$null
        Get-MailPopupName | Should -Be 'factory'
        Should -Invoke Write-Warn -Times 1 -ParameterFilter { $Text -like '*copy that comes with this tool*' }
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
            Get-MailPopupName | Should -Be 'blue'
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

    It 'without administrator rights: Factory reset goes to the administrator window, the start page is done here' {
        Mock Invoke-Elevated { $true }
        Mock Reset-Factory { }
        Mock Reset-StartPageToPrevious { }
        Mock Remove-OldDotFile { }
        Invoke-Tool @{ FactoryReset = $true }
        Should -Invoke Invoke-Elevated -Times 1 -ParameterFilter { $Options.FactoryReset }
        Should -Invoke Reset-Factory -Times 0
        Should -Invoke Reset-StartPageToPrevious -Times 1
        Should -Invoke Remove-OldDotFile -Times 1
    }

    It 'Factory reset leaves the start page alone when the administrator window failed' {
        Mock Invoke-Elevated { $false }
        Mock Reset-StartPageToPrevious { }
        Invoke-Tool @{ FactoryReset = $true } 6>$null
        Should -Invoke Reset-StartPageToPrevious -Times 0
    }

    It 'started again as administrator: does the factory reset but leaves the start page to the first window' {
        function Test-Admin { $true }
        $Relaunched = $true
        Mock Reset-Factory { }
        Mock Reset-StartPageToPrevious { }
        Mock Remove-OldDotFile { }
        Invoke-Tool @{ FactoryReset = $true }
        Should -Invoke Reset-Factory -Times 1
        Should -Invoke Reset-StartPageToPrevious -Times 0
        Should -Invoke Remove-OldDotFile -Times 0
        Should -Invoke Invoke-Elevated -Times 0
    }

    It 'passes Factory reset on to the administrator window' {
        $pass = Get-RelaunchArgs @{ FactoryReset = [switch]$true }
        $pass | Should -Contain '-FactoryReset'
    }

    It 'changes only the new-mail icon when no icon is given, with nothing chosen before' {
        function Test-Admin { $true }
        $DataDir = Join-Path $TestDrive 'NoDataYet'
        Invoke-Tool @{ NewMail = 'none' } 6>$null
        Should -Invoke Install-Icon -Times 1 -ParameterFilter { -not $Value -and $NewMailValue -eq 'none' }
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
        $location = $shell.CreateShortcut($Lnk).IconLocation
        $location | Should -Match '\\current\\shortcut-[0-9A-F]{12}\.ico,0$'
        Test-OurShortcutIcon $location | Should -BeTrue
        ($location -replace ',0$', '') | Should -Exist
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

    It 'tells you to restart Betterbird if it is open, and says nothing if it is not' {
        $script:Notes = @()
        Install-Icon 'bb' $null 6>$null
        @($script:Notes | Where-Object { $_.Kind -eq 'W' }).Count | Should -Be 0
        function Get-Betterbird { @([pscustomobject]@{ Id = 1 }) }
        Install-Icon 'uk' $null 6>$null
        @($script:Notes | Where-Object { $_.Kind -eq 'W' -and $_.Text -eq 'Restart Betterbird to see the new window, taskbar and tray icon.' }).Count | Should -Be 1
        $script:Notes = @()
        Restore-Originals 6>$null
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
        { Install-Icon 'green2' $null 6>$null } | Should -Not -Throw
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
        Install-Icon 'green2' $null   # set with a new-mail icon after -NewMail none: backup must survive
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

    It 'still restores when the record is missing or empty, using the Betterbird found now' {
        $own = Join-Path $Root 'icons\bb\messengerWindow.ico'
        Copy-Item $own (Join-Path $Target 'messengerWindow.ico')
        foreach ($record in $null, '{}') {
            Install-Icon 'blue' $null
            if ($record) { Set-Content $StateFile $record } else { Remove-Item $StateFile }
            Restore-Originals 6>$null
            Get-Sha (Join-Path $Target 'messengerWindow.ico') | Should -Be (Get-Sha $own)
            Join-Path $Target 'newmail.ico' | Should -Not -Exist
            $DataDir | Should -Not -Exist
        }
    }

    It 'never uses the backup without a record when a Betterbird in your own folder shares the data folder' {
        $Mode = 'own'; $Launcher = $null
        $own = Join-Path $Root 'icons\bb\messengerWindow.ico'
        Install-Icon 'blue' $null   # the previous test left the hand-made icon in place
        Remove-Item $StateFile
        Restore-Originals 6>$null
        Get-Sha (Join-Path $BackupDir 'messengerWindow.ico') | Should -Be (Get-Sha $own)
        Get-Sha (Join-Path $Target 'messengerWindow.ico') | Should -Be (Get-Sha (Join-Path $Root 'icons\blue\messengerWindow.ico'))
        # Put things back as the next test expects: blue installed by this tool, backup kept.
        Set-Content $StateFile (@{ Icon = 'blue'; InstallDir = $InstallDir } | ConvertTo-Json)
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

Describe 'Restore when things changed since, and Factory reset' {
    BeforeEach {
        $InstallDir = Join-Path $TestDrive "Reset-$([guid]::NewGuid().ToString('n').Substring(0, 6))"
        function Get-InstallDir { $InstallDir }
        $Target = Join-Path $InstallDir 'chrome\icons\default'
        New-Item -ItemType Directory -Path $Target -Force | Out-Null
        $Exe = Join-Path $InstallDir 'betterbird.exe'
        Set-Content $Exe '' -Encoding ASCII
        $DataDir = Join-Path $InstallDir 'Data'   # unique per test too
        $BackupDir = Join-Path $DataDir 'backup'
        $CurrentDir = Join-Path $DataDir 'current'
        $StateFile = Join-Path $DataDir 'state.json'
        $UserAppData = Join-Path $InstallDir 'AppData'
        $UserStartMenu = Join-Path $InstallDir 'StartMenu'
        $UserDesktop = Join-Path $InstallDir 'Desktop'
        New-Item -ItemType Directory -Path $UserDesktop, $UserStartMenu | Out-Null
        $Lnk = Join-Path $UserDesktop 'Betterbird.lnk'
        $shell = New-Object -ComObject WScript.Shell
        $s = $shell.CreateShortcut($Lnk); $s.TargetPath = $Exe; $s.Save()
        $HandMade = Join-Path $Root 'icons\bb\messengerWindow.ico'
        $Ours = (Join-Path $CurrentDir 'messengerWindow.ico') + ',0'
        Mock Set-MailPopup { }
    }

    It 'Restore leaves an icon changed by hand since alone and keeps the earlier one' {
        Copy-Item $HandMade (Join-Path $Target 'messengerWindow.ico')
        Install-Icon 'blue' $null
        $later = Join-Path $Root 'icons\uk\messengerWindow.ico'
        Copy-Item $later (Join-Path $Target 'messengerWindow.ico') -Force   # changed by hand
        Restore-Originals 6>$null
        Get-Sha (Join-Path $Target 'messengerWindow.ico') | Should -Be (Get-Sha $later)
        Get-Sha (Join-Path $BackupDir 'messengerWindow.ico') | Should -Be (Get-Sha $HandMade)
        Join-Path $Target 'newmail.ico' | Should -Not -Exist   # still ours: removed
        $shell.CreateShortcut($Lnk).IconLocation | Should -Not -Be $Ours
    }

    It 'Restore keeps the icon a shortcut uses when that shortcut could not be put back' {
        Install-Icon 'blue' $null
        Mock Save-ShortcutIcon { $false }
        Restore-Originals 6>$null
        Join-Path $CurrentDir 'messengerWindow.ico' | Should -Exist
        $location = $shell.CreateShortcut($Lnk).IconLocation
        Test-OurShortcutIcon $location | Should -BeTrue
        ($location -replace ',0$', '') | Should -Exist   # the file that shortcut uses is kept
        Join-Path $Target 'messengerWindow.ico' | Should -Not -Exist   # the icon folder is still restored
    }

    It 'Restore gives Betterbird''s own icon to a shortcut using ours that the record does not list' {
        Install-Icon 'blue' $null
        Set-Content $StateFile (@{ Icon = 'blue'; InstallDir = $InstallDir } | ConvertTo-Json)   # shortcuts forgotten
        Restore-Originals 6>$null
        $shell.CreateShortcut($Lnk).IconLocation | Should -Be ',0'
        $DataDir | Should -Not -Exist
    }

    It 'Restore without a data folder removes our icons by their stamp and resets the shortcut' {
        Install-Icon 'blue' $null
        Remove-Item $DataDir -Recurse -Force
        Restore-Originals 6>$null
        Join-Path $Target 'messengerWindow.ico' | Should -Not -Exist
        Join-Path $Target $IconStamp | Should -Not -Exist
        $shell.CreateShortcut($Lnk).IconLocation | Should -Be ',0'
    }

    It 'Factory reset removes every icon, keeps a copy of the hand-made ones, and resets the shortcuts' {
        Copy-Item $HandMade (Join-Path $Target 'messengerWindow.ico')
        $handMail = Join-Path $Root 'icons\bb-green\newmail.ico'
        Copy-Item $handMail (Join-Path $Target 'newmail.ico')
        Install-Icon 'green2' 'none'   # backs up both, then removes the new-mail icon
        Copy-Item $handMail (Join-Path $Target 'newmail.ico')   # and one put there by hand since
        $menu = Join-Path $UserStartMenu 'Betterbird.lnk'
        $s = $shell.CreateShortcut($menu); $s.TargetPath = $Exe; $s.IconLocation = 'C:\Somewhere\own.ico,0'; $s.Save()
        (Get-Item $menu).IsReadOnly = $true
        Set-Content (Join-Path $InstallDir 'omni.ja') 'x'

        Reset-Factory 6>$null

        @(Get-ChildItem $Target).Count | Should -Be 0
        $shell.CreateShortcut($Lnk).IconLocation | Should -Be ',0'
        $shell.CreateShortcut($menu).IconLocation | Should -Be ',0'
        (Get-Item $menu).IsReadOnly | Should -BeTrue
        Should -Invoke Set-MailPopup -Times 1 -ParameterFilter { $Name -eq 'factory' }
        $saved = @(Get-ChildItem $DataDir -Directory -Filter 'saved-*')
        $saved.Count | Should -Be 1
        $files = @{}
        Get-ChildItem $saved[0].FullName | ForEach-Object { $files[$_.Name] = Get-Sha $_.FullName }
        $files.Keys | Sort-Object | Should -Be @('messengerWindow (before this tool).ico', 'newmail.ico')
        $files['messengerWindow (before this tool).ico'] | Should -Be (Get-Sha $HandMade)
        $files['newmail.ico'] | Should -Be (Get-Sha $handMail)   # same as its backup: kept once
        @(Get-ChildItem $DataDir -Force | Where-Object { $_.Name -notlike 'saved-*' }).Count | Should -Be 0
    }

    It 'keeps the tray icon exactly as it is with -NewMail keep, even Betterbird''s own after none' {
        $handMail = Join-Path $Root 'icons\bb-green\newmail.ico'
        Copy-Item $handMail (Join-Path $Target 'newmail.ico')
        Install-Icon 'blue' $null           # backs up the hand-made tray icon
        Install-Icon '' 'none'              # Betterbird's own tray icon
        Join-Path $Target 'newmail.ico' | Should -Not -Exist
        Install-Icon 'uk' 'keep'            # window icon only
        Join-Path $Target 'newmail.ico' | Should -Not -Exist
        Get-Sha (Join-Path $Target 'messengerWindow.ico') | Should -Be (Get-Sha (Join-Path $Root 'icons\uk\messengerWindow.ico'))
        Install-Icon '' 'green2'
        Install-Icon 'blue' 'keep'
        Get-Sha (Join-Path $Target 'newmail.ico') | Should -Be (Get-Sha (Join-Path $Root 'icons\green2\newmail.ico'))
    }

    It 'Factory reset with nothing changed leaves no data behind' {
        Reset-Factory 6>$null
        $DataDir | Should -Not -Exist
        $shell.CreateShortcut($Lnk).IconLocation | Should -Be ',0'
        Should -Invoke Set-MailPopup -Times 0   # no omni.ja here
    }

    It 'Factory reset saves an icon nobody recorded, as on a PC where it was put there by hand' {
        Copy-Item $HandMade (Join-Path $Target 'messengerWindow.ico')
        Reset-Factory 6>$null
        Join-Path $Target 'messengerWindow.ico' | Should -Not -Exist
        $saved = @(Get-ChildItem $DataDir -Directory -Filter 'saved-*')
        Get-Sha (Join-Path $saved[0].FullName 'messengerWindow.ico') | Should -Be (Get-Sha $HandMade)
    }

    It 'Factory reset does not remove anything when the copy cannot be saved' {
        Copy-Item $HandMade (Join-Path $Target 'messengerWindow.ico')
        Mock Copy-Item { }
        { Reset-Factory 6>$null } | Should -Throw '*nothing was removed*'
        Join-Path $Target 'messengerWindow.ico' | Should -Exist
    }

    It 'Status tells Betterbird''s own icon, ours, and one put there by hand apart' {
        (Get-InstalledIcon $InstallDir).Kind | Should -Be 'builtin'
        Install-Icon 'blue' $null
        $icon = Get-InstalledIcon $InstallDir
        $icon.Kind | Should -Be 'ours'; $icon.Set | Should -Be 'blue'
        Copy-Item (Join-Path $Root 'icons\uk\messengerWindow.ico') (Join-Path $Target 'messengerWindow.ico') -Force
        $icon = Get-InstalledIcon $InstallDir
        $icon.Kind | Should -Be 'other'; $icon.Set | Should -Be 'uk'
        $out = Show-Status 6>&1 | Out-String
        $out | Should -Match 'not put there by this tool'
        $out | Should -Match 'is not what is installed'
    }
}

Describe 'Factory reset start page and the dot file' {
    It 'puts back only a start page this tool changed, and never as administrator' {
        $UserAppData = Join-Path $TestDrive 'NoProfiles'
        function Get-InstallDir { 'C:\Program Files\Betterbird' }
        Mock Set-StartPage { }
        Reset-StartPageToPrevious 6>$null
        Should -Invoke Set-StartPage -Times 0
        $ProfileDir = Join-Path $TestDrive 'PortableProfile'
        New-Item -ItemType Directory -Path $ProfileDir | Out-Null
        Set-Content (Join-Path $ProfileDir $SideFile) 'user_pref("mailnews.start_page.url", "https://x.example");'
        Reset-StartPageToPrevious 6>$null
        Should -Invoke Set-StartPage -Times 1 -ParameterFilter { $Value -eq 'Off' }
        function Test-Admin { $true }
        Reset-StartPageToPrevious 6>$null
        Should -Invoke Set-StartPage -Times 1   # not again
    }

    It 'labels a dot icon by its colour and removes the old leftover dot file' {
        $dot = Join-Path $TestDrive 'betterbird-icons-dot-abc.ico'
        Add-IconDot -Source (Join-Path $Root 'icons\blue\messengerWindow.ico') -Dest $dot -Hex $DotColours['Gold']
        Get-NewMailLabel $dot | Should -Be 'Gold dot'
        $other = Join-Path $TestDrive 'mine.ico'
        Copy-Item $dot $other
        Get-NewMailLabel $other | Should -Be 'your own file (mine.ico)'
        Get-NewMailLabel 'blue' | Should -Be 'blue'
        Get-WindowIconPath $other | Should -Be $other

        $saved = $env:LOCALAPPDATA
        try {
            $env:LOCALAPPDATA = Join-Path $TestDrive 'Local'
            $folder = Join-Path $env:LOCALAPPDATA 'BetterbirdIcons'
            New-Item -ItemType Directory -Path $folder | Out-Null
            Copy-Item $dot (Join-Path $folder 'dot-newmail.ico')
            Remove-OldDotFile
            $folder | Should -Not -Exist
            New-Item -ItemType Directory -Path $folder | Out-Null
            Copy-Item $dot (Join-Path $folder 'dot-newmail.ico')
            Set-Content (Join-Path $folder 'state.json') '{}'   # a per-user install's data: stays
            Remove-OldDotFile
            Join-Path $folder 'dot-newmail.ico' | Should -Not -Exist
            Join-Path $folder 'state.json' | Should -Exist
        }
        finally { $env:LOCALAPPDATA = $saved }
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
            $location = (New-Object -ComObject WScript.Shell).CreateShortcut($Lnk).IconLocation
            Test-OurShortcutIcon $location | Should -BeTrue
            $location | Should -Match 'BetterbirdIcons\\current\\shortcut-[0-9A-F]{12}\.ico,0$'
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
            Copy-Item (Join-Path $Root 'icons\green2\messengerWindow.ico') $CurrentDir
            Copy-Item (Join-Path $Root 'icons\green2\messengerWindow.ico') $Target
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

Describe 'The main menu' {
    BeforeAll {
        function Invoke-MenuWith([string[]]$Answers) {
            foreach ($a in $Answers) { $script:menuAnswers.Enqueue($a) }
            $script:menuAnswers.Enqueue('Q')
            Show-Menu 6>&1 | Out-String
        }
    }

    BeforeEach {
        $Mode = 'system'
        $Launcher = $null
        $AppDir = Join-Path $TestDrive 'MenuApp'
        $script:menuAnswers = New-Object 'System.Collections.Generic.Queue[string]'
        Mock Read-Host { $script:menuAnswers.Dequeue() }
        Mock Clear-Host { }
        Mock Invoke-Elevated { $true }
        Mock Install-Icon { }
        Mock Set-MailPopup { }
        Mock Reset-Factory { }
        Mock Reset-StartPageToPrevious { }
        Mock Remove-OldDotFile { }
        Mock Open-IconPage { }
        Mock Show-Status { }
        Mock Show-Manual { }
        Mock Show-Working { }
        $script:BetterbirdClosed = $false
        $script:MenuNotice = $null
        $script:Notes = @()
    }

    It 'lists the items as designed, and marks the ones that ask for administrator permission' {
        $text = Invoke-MenuWith @()
        $wanted = @(
            '1) Change all at once (2, 3 and 5)', '2) Change the standard icon (Windows app icon)',
            '3) Change the system tray icon', '4) Change the system tray dot colour',
            '5) Change the "new mail" popup icon', '6) Show the icons for selection',
            '7) Show manual instructions', '8) Change the start page', '9) Show the current setup',
            'D) Debug issues: close Betterbird and restart Windows Explorer', 'R) Revert to Betterbird defaults', 'S) Select a different Betterbird folder (such as a portable one)', 'Q) Quit')
        $lines = @($text -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^([1-9DRSQ])\) ' })
        $lines.Count | Should -Be 13
        for ($i = 0; $i -lt 13; $i++) { $lines[$i] | Should -BeLike "$($wanted[$i])*" }
        @($lines | Where-Object { $_ -like '*(asks for administrator permission)' }).Count | Should -Be 6
        @($lines | Where-Object { $_ -like '[12345R]) *(asks for administrator permission)' }).Count | Should -Be 6
        $text | Should -Not -Match 'Restore original icons|Factory reset|Restore what I had'
        $Mode = 'own'
        (Invoke-MenuWith @()) | Should -Not -Match 'asks for administrator permission'
    }

    It '1 without administrator rights: one administrator prompt for the icon, the tray icon and the popup' {
        Invoke-MenuWith @('1', '1') | Out-Null
        Should -Invoke Invoke-Elevated -Times 1 -Exactly
        Should -Invoke Invoke-Elevated -Times 1 -ParameterFilter { $Options.Icon -eq 'blue' -and $Options.MailPopup -eq 'blue' -and -not $Options.ContainsKey('NewMail') }
        Should -Invoke Install-Icon -Times 0
        Should -Invoke Set-MailPopup -Times 0
    }

    It '1 in your own folder: changes the icon with its own tray icon, and the popup, here' {
        $Mode = 'own'
        Invoke-MenuWith @('1', '2') | Out-Null
        $second = @(Get-MenuIconSets 'window')[1]
        Should -Invoke Install-Icon -Times 1 -Exactly -ParameterFilter { $Value -eq $second -and -not $NewMailValue }
        Should -Invoke Set-MailPopup -Times 1 -Exactly -ParameterFilter { $Name -eq $second }
        Should -Invoke Invoke-Elevated -Times 0
    }

    It '1 accepts the path to your own .ico file for the icon and the popup' {
        $Mode = 'own'
        $mine = Join-Path $TestDrive 'menu-mine.ico'
        Copy-Item (Join-Path $Root 'icons\uk\messengerWindow.ico') $mine
        Invoke-MenuWith @('1', "`"$mine`"") | Out-Null
        Should -Invoke Install-Icon -Times 1 -Exactly -ParameterFilter { $Value -eq $mine }
        Should -Invoke Set-MailPopup -Times 1 -Exactly -ParameterFilter { $Name -eq $mine }
    }

    It '2 changes only the standard icon and keeps the tray icon' {
        Invoke-MenuWith @('2', 'uk') | Out-Null
        Should -Invoke Invoke-Elevated -Times 1 -Exactly -ParameterFilter { $Options.Icon -eq 'uk' -and $Options.NewMail -eq 'keep' -and -not $Options.ContainsKey('MailPopup') }
        $Mode = 'own'
        Invoke-MenuWith @('2', '1') | Out-Null
        Should -Invoke Install-Icon -Times 1 -Exactly -ParameterFilter { $Value -eq 'blue' -and $NewMailValue -eq 'keep' }
        Should -Invoke Set-MailPopup -Times 0
    }

    It '3 changes only the tray icon, without a window icon chosen first, and offers none' {
        Invoke-MenuWith @('3', 'none') | Out-Null
        Should -Invoke Invoke-Elevated -Times 1 -Exactly -ParameterFilter { $Options.NewMail -eq 'none' -and -not $Options.ContainsKey('Icon') }
        $Mode = 'own'
        $first = @(Get-MenuIconSets 'newmail')[0]
        Invoke-MenuWith @('3', '1') | Out-Null
        Should -Invoke Install-Icon -Times 1 -Exactly -ParameterFilter { -not $Value -and $NewMailValue -eq $first }
    }

    It '4 changes only the dot colour, without option 1 or 2 first' {
        $base = Join-Path $Root 'icons\bb\messengerWindow.ico'
        Mock Get-DotBasePath { $base }
        Mock Get-CurrentNewMailPath { $null }
        Mock Add-IconDot { }
        Invoke-MenuWith @('4', '2') | Out-Null
        Should -Invoke Add-IconDot -Times 1 -Exactly -ParameterFilter { $Source -eq $base -and $Hex -eq $DotColours['Gold'] }
        Should -Invoke Invoke-Elevated -Times 1 -Exactly -ParameterFilter { $Options.NewMail -like '*betterbird-icons-dot-*.ico' -and -not $Options.ContainsKey('Icon') }
        $Mode = 'own'
        Invoke-MenuWith @('4', '1') | Out-Null
        Should -Invoke Install-Icon -Times 1 -Exactly -ParameterFilter { -not $Value -and $NewMailValue -like '*betterbird-icons-dot-*.ico' }
    }

    It '5 offers every set and Betterbird''s own, and changes only the popup' {
        $names = @(Get-MenuIconSets 'window')
        $uk = [array]::IndexOf($names, 'uk') + 1
        $text = Invoke-MenuWith @('5', "$uk")
        $text | Should -Match 'Betterbird\s+Betterbird''s own'
        foreach ($n in $names) { $text | Should -Match $n }
        Should -Invoke Invoke-Elevated -Times 1 -Exactly -ParameterFilter { $Options.MailPopup -eq 'uk' -and @($Options.Keys).Count -eq 1 }
        $Mode = 'own'
        Invoke-MenuWith @('5', "$($names.Count + 1)") | Out-Null
        Should -Invoke Set-MailPopup -Times 1 -Exactly -ParameterFilter { $Name -eq 'factory' }
        Should -Invoke Install-Icon -Times 0
    }

    It '6, 7, 8 and 9 open the page, the manual, the start page and the setup' {
        Mock Get-StartPageMode { 'on' }
        Mock Test-PreviousStartPageSaved { $false }
        Mock Set-StartPage { }
        Invoke-MenuWith @('6', '7', '', '8', '1', 'C:\x.html', '', '9', '') | Out-Null
        Should -Invoke Open-IconPage -Times 1 -Exactly
        Should -Invoke Show-Manual -Times 1 -Exactly
        Should -Invoke Set-StartPage -Times 1 -Exactly -ParameterFilter { $Value -eq 'C:\x.html' }
        Should -Invoke Show-Status -Times 1 -Exactly
        Should -Invoke Invoke-Elevated -Times 0
    }

    It 'R goes through the confirmation and resets; N changes nothing' {
        Invoke-MenuWith @('R', 'N') | Out-Null
        Should -Invoke Invoke-Elevated -Times 0
        Invoke-MenuWith @('r', 'Y') | Out-Null
        Should -Invoke Invoke-Elevated -Times 1 -Exactly -ParameterFilter { $Options.FactoryReset }
        Should -Invoke Reset-StartPageToPrevious -Times 1 -Exactly
        Should -Invoke Remove-OldDotFile -Times 1
        $Mode = 'own'
        Invoke-MenuWith @('R', 'Y') | Out-Null
        Should -Invoke Reset-Factory -Times 1 -Exactly
    }

    It 'S switches to a Betterbird in another folder' {
        Mock Enter-OwnFolderMode { }
        Mock Confirm-StandardUser { $true }
        Invoke-MenuWith @('S', 'D:\Portable') | Out-Null
        Should -Invoke Enter-OwnFolderMode -Times 1 -Exactly -ParameterFilter { $Folder -eq 'D:\Portable' }
    }

    Context 'with Betterbird open' {
        BeforeAll {
            $script:BbDir = Join-Path $TestDrive 'OpenApp'
            New-Item -ItemType Directory -Path $script:BbDir -Force | Out-Null
            Set-Content (Join-Path $script:BbDir 'betterbird.exe') '' -Encoding ASCII
            $script:BbExe = Join-Path $script:BbDir 'betterbird.exe'
            function New-RunningBetterbird {
                # A Betterbird that closes when asked (or not, as if minimised to the tray), and logs what happens.
                $bb = @{ Running = $true; CloseWorks = $true; Events = (New-Object System.Collections.ArrayList) }
                $fake = [pscustomobject]@{ Id = 4242 }
                $fake | Add-Member -MemberType ScriptMethod -Name CloseMainWindow -Value ({
                        if ($bb.CloseWorks) { $bb.Running = $false; [void]$bb.Events.Add('close') }
                        $bb.CloseWorks }.GetNewClosure())
                $bb.Fake = $fake
                $bb
            }
        }

        BeforeEach {
            $script:bb = New-RunningBetterbird
            $AppDir = $script:BbDir
            Mock Get-InstallDir { $script:BbDir }
            Mock Get-Betterbird { if ($script:bb.Running) { @($script:bb.Fake) } else { @() } }
            Mock Start-Sleep { }
            Mock Start-Process { [void]$script:bb.Events.Add("start:$FilePath") }
            Mock Stop-Process { $script:bb.Running = $false; [void]$script:bb.Events.Add('force') }
            Mock Invoke-Elevated { [void]$script:bb.Events.Add('elevate'); $true }
            Mock Install-Icon { [void]$script:bb.Events.Add('install') }
            Mock Set-MailPopup { [void]$script:bb.Events.Add('popup') }
            Mock Reset-Factory { [void]$script:bb.Events.Add('reset') }
            Mock Reset-StartPageToPrevious { [void]$script:bb.Events.Add('startpage') }
            Mock Restart-Explorer { [void]$script:bb.Events.Add('explorer'); $true }
        }

        It '2 asks before the administrator prompt, closes Betterbird in this window, and starts it again after the change' {
            $text = Invoke-MenuWith @('2', 'uk', 'Y')
            $text | Should -Match 'Betterbird is open\. Its window, taskbar button and system tray icon keep the old picture until it restarts\.'
            Should -Invoke Read-Host -Times 1 -Exactly -ParameterFilter { $Prompt -like '*Close Betterbird now and start it again when the change is done? (Y/N)' }
            $script:bb.Events -join ',' | Should -Be "close,elevate,start:$script:BbExe"
            $text | Should -Match 'Started Betterbird again\.'
        }

        It 'asks nothing when Betterbird is not open' {
            $script:bb.Running = $false
            Invoke-MenuWith @('2', 'uk') | Out-Null
            Should -Invoke Read-Host -Times 3 -Exactly   # the item, the icon, Q
            $script:bb.Events -join ',' | Should -Be 'elevate'
        }

        It 'starts it again from this window in your own folder too, and the portable launcher if there is one' {
            $Mode = 'own'
            Invoke-MenuWith @('2', 'uk', 'Y') | Out-Null
            $script:bb.Events -join ',' | Should -Be "close,install,start:$script:BbExe"
            $script:bb = New-RunningBetterbird
            $launcher = Join-Path $TestDrive 'BetterbirdLauncher.exe'
            Set-Content $launcher '' -Encoding ASCII
            $Launcher = $launcher
            Invoke-MenuWith @('2', 'uk', 'Y') | Out-Null
            $script:bb.Events -join ',' | Should -Be "close,install,start:$launcher"
        }

        It 'N carries on with 2; 3 and 4 never ask; Betterbird stays open and is not started' {
            Mock Get-DotBasePath { Join-Path $Root 'icons\bb\messengerWindow.ico' }
            Mock Get-CurrentNewMailPath { $null }
            Mock Add-IconDot { }
            Invoke-MenuWith @('2', 'uk', 'N', '3', 'none', '4', '2') | Out-Null
            Should -Invoke Invoke-Elevated -Times 3 -Exactly
            $script:bb.Events -join ',' | Should -Be 'elevate,elevate,elevate'
            $script:bb.Running | Should -BeTrue
        }

        It 'N stops 1 before anything changes, with the popup message' {
            $text = Invoke-MenuWith @('1', '1', 'N', '')
            Should -Invoke Invoke-Elevated -Times 0
            Should -Invoke Install-Icon -Times 0
            Should -Invoke Set-MailPopup -Times 0
            ([regex]::Matches($text, 'Betterbird is using that picture\. Quit it completely, including the tray icon, then try again\.')).Count | Should -Be 1
            $script:bb.Running | Should -BeTrue
            $Mode = 'own'
            Invoke-MenuWith @('1', '1', 'N', '') | Out-Null
            Should -Invoke Install-Icon -Times 0
        }

        It 'Y closes it for 1 as well, and starts it again after' {
            Invoke-MenuWith @('1', '1', 'Y') | Out-Null
            $events = $script:bb.Events -join ','
            $events | Should -Match '^close,elevate'
            $events | Should -Match 'start:.*betterbird\.exe$'
        }

        It 'only 1 and 2 ask to close Betterbird: 3, 4, 5 and R never do, and never start it' {
            Mock Get-DotBasePath { Join-Path $Root 'icons\bb\messengerWindow.ico' }
            Mock Get-CurrentNewMailPath { $null }
            Mock Add-IconDot { }
            Invoke-MenuWith @('3', 'none', '4', '2', '5', '1', 'R', 'Y') | Out-Null
            Should -Invoke Read-Host -Times 0 -ParameterFilter { $Prompt -like '*Close Betterbird now*' }
            Should -Invoke Invoke-Elevated -Times 4 -Exactly
            $script:bb.Events -join ',' | Should -Not -Match 'close|start:'
        }

        It 'a Betterbird that does not close (minimised to the tray) gets the force question; N leaves it running and carries on' {
            function Test-Interactive { $true }
            $script:bb.CloseWorks = $false
            Invoke-MenuWith @('2', 'uk', 'Y', 'N') | Out-Null
            Should -Invoke Read-Host -Times 1 -Exactly -ParameterFilter { $Prompt -like '*Betterbird did not close. Force it closed? Anything unsaved, such as a message being written, will be lost. (Y/N)' }
            Should -Invoke Stop-Process -Times 0
            $script:bb.Running | Should -BeTrue
            $script:bb.Events -join ',' | Should -Be 'elevate'
        }

        It 'a Betterbird that does not close is stopped when you agree to force it, then started again' {
            function Test-Interactive { $true }
            $script:bb.CloseWorks = $false
            Invoke-MenuWith @('2', 'uk', 'Y', 'Y') | Out-Null
            Should -Invoke Stop-Process -Times 1 -Exactly -ParameterFilter { $Id -eq 4242 }
            $script:bb.Events -join ',' | Should -Be "force,elevate,start:$script:BbExe"
        }

        It 'a Betterbird that does not close stops 1 when you will not force it' {
            function Test-Interactive { $true }
            $script:bb.CloseWorks = $false
            Invoke-MenuWith @('1', '1', 'Y', 'N', '') | Out-Null
            Should -Invoke Invoke-Elevated -Times 0
            Should -Invoke Stop-Process -Times 0
        }

        It 'starts Betterbird again even when the change failed' {
            $Mode = 'own'
            Mock Install-Icon { throw 'boom' }
            $text = Invoke-MenuWith @('2', 'uk', 'Y', '')
            $text | Should -Match 'boom'
            Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter { $FilePath -eq $script:BbExe }
        }

        It 'run as administrator: closes it, but does not start it from here' {
            function Test-Admin { $true }
            $Mode = 'own'
            $text = Invoke-MenuWith @('2', 'uk', 'Y')
            Should -Invoke Start-Process -Times 0
            $text | Should -Match 'Betterbird was not started again: this window runs as administrator'
        }

        It 'D asks first; N changes nothing' {
            Invoke-MenuWith @('D', 'N', '') | Out-Null
            Should -Invoke Restart-Explorer -Times 0
            $script:bb.Events.Count | Should -Be 0
            $script:bb.Running | Should -BeTrue
        }

        It 'D explains itself, closes Betterbird and restarts Explorer, and does not start Betterbird again' {
            $text = Invoke-MenuWith @('D', 'Y', '')
            $text | Should -Match 'Closes Betterbird if it is open, and restarts Windows Explorer \(File Explorer windows close\)\.'
            $script:bb.Events -join ',' | Should -Be 'close,explorer'
            $text | Should -Match 'Closed Betterbird\.'
        }

        It 'D leaves a Betterbird that will not close open, and still restarts Explorer' {
            function Test-Interactive { $true }
            $script:bb.CloseWorks = $false
            $text = Invoke-MenuWith @('D', 'Y', 'N', '')
            $script:bb.Events -join ',' | Should -Be 'explorer'
            $text | Should -Match 'Betterbird is still open, so it was left as it is\.'
        }

        It 'D never runs as administrator, never elevates, and says why' {
            function Test-Admin { $true }
            $text = Invoke-MenuWith @('D', '')
            $script:bb.Events.Count | Should -Be 0
            Should -Invoke Restart-Explorer -Times 0
            Should -Invoke Invoke-Elevated -Times 0
            $text | Should -Match 'This window runs as administrator'
            Should -Invoke Read-Host -Times 3 -Exactly   # D, Enter, Q: no Go ahead question
        }
    }
}

Describe 'Restarting Explorer' {
    BeforeEach {
        $script:session = [Diagnostics.Process]::GetCurrentProcess().SessionId
        $script:stopped = $false
        Mock Start-Sleep { }
        Mock Start-Process { }
        Mock Stop-Process { $script:stopped = $true }
        Mock Write-Host { }
    }

    It 'stops only this session''s Explorer, and leaves it to Windows when it comes back by itself' {
        Mock Get-Process {
            $list = @([pscustomobject]@{ Id = 10; SessionId = $script:session }, [pscustomobject]@{ Id = 11; SessionId = $script:session + 50 })
            if ($script:stopped) { $list += [pscustomobject]@{ Id = 12; SessionId = $script:session } }
            $list | Where-Object { $true }
        }
        Restart-Explorer | Should -BeTrue
        Should -Invoke Stop-Process -Times 1 -Exactly -ParameterFilter { @($Id).Count -eq 1 -and $Id[0] -eq 10 }
        Should -Invoke Start-Process -Times 0
    }

    It 'starts explorer.exe from the Windows folder when it has not come back' {
        Mock Get-Process { @([pscustomobject]@{ Id = 10; SessionId = $script:session }) | Where-Object { -not $script:stopped } }
        Restart-Explorer | Should -BeTrue
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter { $FilePath -eq (Join-Path $WindowsDir 'explorer.exe') }
    }

    It 'never restarts it as administrator, and says why' {
        function Test-Admin { $true }
        Mock Get-Process { throw 'must not look' }
        Mock Write-Warn { }
        Restart-Explorer | Should -BeFalse
        Should -Invoke Stop-Process -Times 0
        Should -Invoke Start-Process -Times 0
        Should -Invoke Write-Warn -Times 1 -Exactly -ParameterFilter { $Text -like '*runs as administrator*' }
    }
}

Describe 'Explorer on the command line' {
    BeforeEach {
        $Mode = 'system'
        $Relaunched = $false
        $StateFile = Join-Path $TestDrive 'never-exists.json'
        Mock Install-Icon { }
        Mock Set-MailPopup { }
        Mock Restore-Originals { }
        Mock Remove-OldReapplyTask { }
        Mock Invoke-Elevated { $true }
        Mock Restart-Explorer { $true }
        $script:said = @()
        Mock Write-Host { $script:said += "$Object" }
    }

    It 'restarts nothing and prints no Explorer note after an icon change without -RestartExplorer' {
        Invoke-Tool @{ Icon = 'blue' }
        Should -Invoke Restart-Explorer -Times 0
        @($script:said | Where-Object { $_ -like '*Explorer*' }).Count | Should -Be 0
    }

    It 'restarts Explorer here, in the normal window, after the administrator window finished' {
        Invoke-Tool @{ Icon = 'blue'; RestartExplorer = [switch]$true }
        Should -Invoke Invoke-Elevated -Times 1 -Exactly -ParameterFilter { -not $Options.ContainsKey('RestartExplorer') -and $Options.Icon -eq 'blue' }
        Should -Invoke Restart-Explorer -Times 1 -Exactly
        Should -Invoke Install-Icon -Times 0
    }

    It 'does not restart Explorer when the administrator window failed' {
        Mock Invoke-Elevated { $false }
        Invoke-Tool @{ Icon = 'blue'; RestartExplorer = [switch]$true }
        Should -Invoke Restart-Explorer -Times 0
    }

    It 'with administrator rights, hands the decision to Restart-Explorer, which refuses' {
        function Test-Admin { $true }
        Invoke-Tool @{ Icon = 'blue'; RestartExplorer = [switch]$true }
        Should -Invoke Install-Icon -Times 1 -Exactly
        Should -Invoke Restart-Explorer -Times 1 -Exactly
    }

    It 'the administrator window itself never touches Explorer' {
        function Test-Admin { $true }
        $Relaunched = $true
        Invoke-Tool @{ Icon = 'blue'; RestartExplorer = [switch]$true }
        Should -Invoke Restart-Explorer -Times 0
    }

    It 'a popup change alone does not restart Explorer; -RestartExplorer alone does' {
        Invoke-Tool @{ MailPopup = 'uk' }
        Should -Invoke Restart-Explorer -Times 0
        Invoke-Tool @{ RestartExplorer = [switch]$true }
        Should -Invoke Restart-Explorer -Times 1 -Exactly
    }

    It 'restarts Explorer when asked, whatever was changed, and otherwise never' {
        Mock Remove-OldDotFile { }
        Mock Reset-StartPageToPrevious { }
        foreach ($o in @{ NewMail = 'none' }, @{ Restore = [switch]$true }, @{ FactoryReset = [switch]$true }) {
            Invoke-Tool $o
        }
        Should -Invoke Restart-Explorer -Times 0
        Invoke-Tool @{ NewMail = 'none'; RestartExplorer = [switch]$true }
        Should -Invoke Restart-Explorer -Times 1 -Exactly
        @($script:said | Where-Object { $_ -like '*until Explorer restarts*' }).Count | Should -Be 0
    }

    It 'changes the popup before the icon, so a running Betterbird stops it before anything changes' {
        function Test-Admin { $true }
        Mock Set-MailPopup { throw 'Betterbird is using that picture.' }
        { Invoke-Tool @{ Icon = 'uk'; MailPopup = 'uk' } } | Should -Throw '*using that picture*'
        Should -Invoke Install-Icon -Times 0
    }

    It 'changes the icon and the popup together in one administrator prompt' {
        Invoke-Tool @{ Icon = 'green2'; MailPopup = 'green2' }
        Should -Invoke Invoke-Elevated -Times 1 -Exactly -ParameterFilter { $Options.Icon -eq 'green2' -and $Options.MailPopup -eq 'green2' }
        function Test-Admin { $true }
        Invoke-Tool @{ Icon = 'green2'; MailPopup = 'green2' }
        Should -Invoke Install-Icon -Times 1 -Exactly -ParameterFilter { $Value -eq 'green2' }
        Should -Invoke Set-MailPopup -Times 1 -Exactly -ParameterFilter { $Name -eq 'green2' }
    }

    It 'passes the new values to the administrator window, and no Explorer or Betterbird restart' {
        $pass = Get-RelaunchArgs @{ NewMail = 'keep'; Icon = 'blue'; MailPopup = 'uk' }
        $pass | Should -Contain '"keep"'
        $pass | Should -Contain '"uk"'
        $elevated = Get-ElevatedOptions @{ Icon = 'blue'; RestartExplorer = $true; RestartBetterbird = $true }
        $elevated.Keys | Should -Not -Contain 'RestartExplorer'
        $elevated.Keys | Should -Not -Contain 'RestartBetterbird'
        $ico = Join-Path $TestDrive 'popup-mine.ico'
        Copy-Item (Join-Path $Root 'icons\uk\messengerWindow.ico') $ico
        Get-RelaunchArgs @{ MailPopup = $ico } | Should -Contain (Format-Arg $ico)
        # A folder called blue in the current folder must not turn the set name into a path.
        New-Item -ItemType Directory -Path (Join-Path $TestDrive 'blue') | Out-Null
        Push-Location $TestDrive
        try { $args2 = Get-RelaunchArgs @{ Icon = 'blue'; MailPopup = 'blue' } }
        finally { Pop-Location }
        $args2 | Should -Contain '"blue"'
        @($args2 | Where-Object { $_ -like '*TestDrive*' -and $_ -like '*blue*' }).Count | Should -Be 0
    }
}

Describe 'Closing and starting Betterbird' {
    BeforeAll {
        $script:BbDir = Join-Path $TestDrive 'CliApp'
        New-Item -ItemType Directory -Path $script:BbDir -Force | Out-Null
        Set-Content (Join-Path $script:BbDir 'betterbird.exe') '' -Encoding ASCII
        $script:BbExe = Join-Path $script:BbDir 'betterbird.exe'
        function New-RunningBetterbird {
            $bb = @{ Running = $true; CloseWorks = $true; Events = (New-Object System.Collections.ArrayList) }
            $fake = [pscustomobject]@{ Id = 4242 }
            $fake | Add-Member -MemberType ScriptMethod -Name CloseMainWindow -Value ({
                    if ($bb.CloseWorks) { $bb.Running = $false; [void]$bb.Events.Add('close') }
                    $bb.CloseWorks }.GetNewClosure())
            $bb.Fake = $fake
            $bb
        }
    }

    BeforeEach {
        $script:bb = New-RunningBetterbird
        $script:BetterbirdClosed = $false
        $Mode = 'system'
        $Launcher = $null
        $Force = $false
        $Relaunched = $false
        $StateFile = Join-Path $TestDrive 'never-exists.json'
        Mock Get-InstallDir { $script:BbDir }
        Mock Get-Betterbird { if ($script:bb.Running) { @($script:bb.Fake) } else { @() } }
        Mock Start-Sleep { }
        Mock Start-Process { [void]$script:bb.Events.Add("start:$FilePath") }
        Mock Stop-Process { $script:bb.Running = $false; [void]$script:bb.Events.Add('force') }
        Mock Read-Host { throw "must not ask: $Prompt" }
        Mock Invoke-Elevated { [void]$script:bb.Events.Add('elevate'); $true }
        Mock Install-Icon { [void]$script:bb.Events.Add('install') }
        Mock Set-MailPopup { }
        Mock Reset-Factory { [void]$script:bb.Events.Add('reset') }
        Mock Reset-StartPageToPrevious { }
        Mock Remove-OldDotFile { }
        Mock Remove-OldReapplyTask { }
        Mock Restart-Explorer { [void]$script:bb.Events.Add('explorer'); $true }
        Mock Write-Host { }
    }

    It 'closes the normal way and does not ask about forcing' {
        Stop-Betterbird | Should -BeTrue
        $script:bb.Events -join ',' | Should -Be 'close'
        Should -Invoke Stop-Process -Times 0
    }

    It 'a Betterbird that does not close is left running when nobody can be asked' {
        $script:bb.CloseWorks = $false
        Stop-Betterbird | Should -BeFalse
        Should -Invoke Stop-Process -Times 0
    }

    It 'a Betterbird that does not close is stopped only on Y' {
        function Test-Interactive { $true }
        $script:bb.CloseWorks = $false
        Mock Read-Host { 'n' }
        Stop-Betterbird | Should -BeFalse
        Should -Invoke Stop-Process -Times 0
        Mock Read-Host { 'y' }
        Stop-Betterbird | Should -BeTrue
        Should -Invoke Stop-Process -Times 1 -Exactly -ParameterFilter { $Id -eq 4242 }
    }

    It 'Close-Betterbird still asks, refuses without an answer, and says it was closed' {
        { Close-Betterbird 'for a test' } | Should -Throw '*Betterbird is open. Close it for a test, or pass -Force*'
        function Test-Interactive { $true }
        Mock Read-Host { 'N' }
        { Close-Betterbird 'for a test' } | Should -Throw '*Close Betterbird and run this again*'
        $script:BetterbirdClosed | Should -BeFalse
        Mock Read-Host { 'Y' }
        Close-Betterbird 'for a test'
        $script:BetterbirdClosed | Should -BeTrue
        $script:bb.Events -join ',' | Should -Be 'close'
    }

    It 'Close-Betterbird with -Force closes at once, but a Betterbird that will not close is an error' {
        $Force = $true
        Close-Betterbird 'for a test'
        $script:BetterbirdClosed | Should -BeTrue
        $script:bb = New-RunningBetterbird
        $script:bb.CloseWorks = $false
        $script:BetterbirdClosed = $false
        { Close-Betterbird 'for a test' } | Should -Throw '*Betterbird did not close*'
        $script:BetterbirdClosed | Should -BeFalse
        Should -Invoke Stop-Process -Times 0
    }

    It 'Close-Betterbird asks nothing when Betterbird is not open' {
        $script:bb.Running = $false
        Close-Betterbird 'for a test'
        $script:BetterbirdClosed | Should -BeFalse
    }

    It 'starts the installed betterbird.exe, or the portable launcher' {
        Start-Betterbird | Should -BeTrue
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter { $FilePath -eq $script:BbExe }
        $launcher = Join-Path $TestDrive 'BetterbirdLauncher.exe'
        Set-Content $launcher '' -Encoding ASCII
        $Launcher = $launcher
        Start-Betterbird | Should -BeTrue
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter { $FilePath -eq $launcher }
    }

    It 'never starts it as administrator, and says so' {
        function Test-Admin { $true }
        Start-Betterbird | Should -BeFalse
        Should -Invoke Start-Process -Times 0
    }

    It 'says so when there is nothing to start' {
        $Launcher = Join-Path $TestDrive 'NoSuchLauncher.exe'
        Mock Write-Warn { }
        Start-Betterbird | Should -BeFalse
        Should -Invoke Start-Process -Times 0
        Should -Invoke Write-Warn -Times 1 -Exactly -ParameterFilter { $Text -like "Couldn't find*Start it yourself." }
    }

    It '-Icon alone closes and starts nothing, whatever is running' {
        $Force = $true
        Invoke-Tool @{ Icon = 'blue' }
        $script:bb.Events -join ',' | Should -Be 'elevate'
        $script:bb.Running | Should -BeTrue
    }

    It '-Icon -RestartBetterbird closes it here before the administrator prompt, then starts it again here after Explorer' {
        $Force = $true
        Invoke-Tool @{ Icon = 'blue'; RestartExplorer = [switch]$true; RestartBetterbird = [switch]$true }
        $script:bb.Events -join ',' | Should -Be "close,elevate,explorer,start:$script:BbExe"
        Should -Invoke Invoke-Elevated -Times 1 -Exactly -ParameterFilter { -not $Options.ContainsKey('RestartBetterbird') }
    }

    It '-RestartBetterbird in your own folder or as administrator: the same, in this window' {
        $Mode = 'own'
        $Force = $true
        Invoke-Tool @{ MailPopup = 'uk'; RestartBetterbird = [switch]$true }
        $script:bb.Events -join ',' | Should -Be "close,start:$script:BbExe"
        $script:bb = New-RunningBetterbird
        $Mode = 'system'
        function Test-Admin { $true }
        Invoke-Tool @{ Icon = 'blue'; RestartBetterbird = [switch]$true }
        $script:bb.Events -join ',' | Should -Be 'close,install'   # no start: this window is administrator
        Should -Invoke Start-Process -Times 1 -Exactly
    }

    It '-RestartBetterbird without -Force asks, and in a script it refuses before anything changes' {
        { Invoke-Tool @{ Icon = 'blue'; RestartBetterbird = [switch]$true } } | Should -Throw '*Betterbird is open*-Force*'
        Should -Invoke Invoke-Elevated -Times 0
        function Test-Interactive { $true }
        Mock Read-Host { 'Y' }
        Invoke-Tool @{ Icon = 'blue'; RestartBetterbird = [switch]$true }
        $script:bb.Events -join ',' | Should -Be "close,elevate,start:$script:BbExe"
    }

    It '-RestartBetterbird starts it again even when the change failed, and not when this run did not close it' {
        $Force = $true
        $Mode = 'own'
        Mock Install-Icon { throw 'boom' }
        { Invoke-Tool @{ Icon = 'blue'; RestartBetterbird = [switch]$true } } | Should -Throw 'boom'
        Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter { $FilePath -eq $script:BbExe }
        $script:bb = New-RunningBetterbird
        $script:bb.Running = $false
        Invoke-Tool @{ RestartBetterbird = [switch]$true }
        Should -Invoke Start-Process -Times 1 -Exactly
    }

    It '-RestartBetterbird alone restarts Betterbird' {
        $Force = $true
        Invoke-Tool @{ RestartBetterbird = [switch]$true }
        $script:bb.Events -join ',' | Should -Be "close,start:$script:BbExe"
        Should -Invoke Invoke-Elevated -Times 0
    }

    It '-FactoryReset closes Betterbird here, before the administrator prompt, so that window has nothing to ask' {
        $Force = $true
        Invoke-Tool @{ FactoryReset = [switch]$true }
        $script:bb.Events -join ',' | Should -Be 'close,elevate'
        Should -Invoke Start-Process -Times 0   # not asked to start it again
        $script:bb = New-RunningBetterbird
        Invoke-Tool @{ FactoryReset = [switch]$true; RestartBetterbird = [switch]$true }
        $script:bb.Events -join ',' | Should -Be "close,elevate,start:$script:BbExe"
    }

    It 'the administrator window never closes or starts Betterbird for -RestartBetterbird' {
        function Test-Admin { $true }
        $Relaunched = $true
        $Force = $true
        Invoke-Tool @{ Icon = 'blue'; RestartBetterbird = [switch]$true }
        $script:bb.Events -join ',' | Should -Be 'install'
        Should -Invoke Start-Process -Times 0
    }
}

Describe 'Window icon, tray icon and shortcut icons' {
    BeforeAll {
        function Get-ShortcutIconNames { @(Get-ChildItem $CurrentDir -Filter 'shortcut-*.ico' -ErrorAction SilentlyContinue | ForEach-Object Name) }
    }

    BeforeEach {
        $InstallDir = Join-Path $TestDrive "Tray-$([guid]::NewGuid().ToString('n').Substring(0, 6))"
        function Get-InstallDir { $InstallDir }
        $Target = Join-Path $InstallDir 'chrome\icons\default'
        New-Item -ItemType Directory -Path $Target -Force | Out-Null
        $Exe = Join-Path $InstallDir 'betterbird.exe'
        Set-Content $Exe '' -Encoding ASCII
        $DataDir = Join-Path $InstallDir 'Data'
        $BackupDir = Join-Path $DataDir 'backup'
        $CurrentDir = Join-Path $DataDir 'current'
        $StateFile = Join-Path $DataDir 'state.json'
        $UserAppData = Join-Path $InstallDir 'AppData'
        $UserStartMenu = Join-Path $InstallDir 'StartMenu'
        $UserDesktop = Join-Path $InstallDir 'Desktop'
        New-Item -ItemType Directory -Path $UserDesktop, $UserStartMenu | Out-Null
        $Lnk = Join-Path $UserDesktop 'Betterbird.lnk'
        $shell = New-Object -ComObject WScript.Shell
        $s = $shell.CreateShortcut($Lnk); $s.TargetPath = $Exe; $s.Save()
        $HandMade = Join-Path $Root 'icons\bb\messengerWindow.ico'
        $HandMail = Join-Path $Root 'icons\bb-green\newmail.ico'
        Mock Set-MailPopup { }
        $Mode = 'system'
    }

    It 'keeps the tray icon when asked to (menu 2): only the window icon changes' {
        Install-Icon 'uk' $null
        Install-Icon 'blue' 'keep'
        Get-Sha (Join-Path $Target 'messengerWindow.ico') | Should -Be (Get-Sha (Join-Path $Root 'icons\blue\messengerWindow.ico'))
        Get-Sha (Join-Path $Target 'newmail.ico') | Should -Be (Get-Sha (Join-Path $Root 'icons\uk\newmail.ico'))
        Get-Sha (Join-Path $CurrentDir 'newmail.ico') | Should -Be (Get-Sha (Join-Path $Root 'icons\uk\newmail.ico'))
        (Read-State).NewMail | Should -Be 'uk'
        (Read-State).Icon | Should -Be 'blue'
    }

    It 'keeps a tray icon you made yourself, and Restore still gives it back' {
        Copy-Item $HandMail (Join-Path $Target 'newmail.ico')
        Install-Icon 'blue' 'keep'
        Get-Sha (Join-Path $Target 'newmail.ico') | Should -Be (Get-Sha $HandMail)
        Get-Sha (Join-Path $BackupDir 'newmail.ico') | Should -Be (Get-Sha $HandMail)
        Restore-Originals 6>$null
        Get-Sha (Join-Path $Target 'newmail.ico') | Should -Be (Get-Sha $HandMail)
        Join-Path $Target 'messengerWindow.ico' | Should -Not -Exist
    }

    It 'keeps Betterbird''s own tray icon when there is none' {
        Install-Icon 'blue' 'keep'
        Join-Path $Target 'newmail.ico' | Should -Not -Exist
        Get-Sha (Join-Path $Target 'messengerWindow.ico') | Should -Be (Get-Sha (Join-Path $Root 'icons\blue\messengerWindow.ico'))
    }

    It 'keeps the tray icon this tool installed even when its copy in the data folder was lost' {
        Install-Icon 'uk' $null
        Remove-Item (Join-Path $CurrentDir 'newmail.ico')
        Install-Icon 'blue' 'keep'
        Get-Sha (Join-Path $Target 'newmail.ico') | Should -Be (Get-Sha (Join-Path $Root 'icons\uk\newmail.ico'))
    }

    It 'changes only the tray icon with no window icon chosen before (menu 3)' {
        $before = $shell.CreateShortcut($Lnk).IconLocation
        Install-Icon '' 'green2' 6>$null
        Get-Sha (Join-Path $Target 'newmail.ico') | Should -Be (Get-Sha (Join-Path $Root 'icons\green2\newmail.ico'))
        Join-Path $Target 'messengerWindow.ico' | Should -Not -Exist
        Join-Path $CurrentDir 'messengerWindow.ico' | Should -Not -Exist
        $shell.CreateShortcut($Lnk).IconLocation | Should -Be $before   # shortcuts untouched
        Get-ShortcutIconNames | Should -BeNullOrEmpty
        $state = Read-State
        $state.NewMail | Should -Be 'green2'
        $state.Icon | Should -BeNullOrEmpty
        $out = Show-Status 6>&1 | Out-String
        $out | Should -Match "Icon:\s+Betterbird's own"
        $out | Should -Match 'Tray icon:\s+green2'
    }

    It 'tray icon only: Restore removes it and the data, and the factory reset does too' {
        Install-Icon '' 'green2' 6>$null
        Restore-Originals 6>$null
        Join-Path $Target 'newmail.ico' | Should -Not -Exist
        $DataDir | Should -Not -Exist
        Install-Icon '' 'uk' 6>$null
        Reset-Factory 6>$null
        @(Get-ChildItem $Target).Count | Should -Be 0
        $DataDir | Should -Not -Exist
    }

    It 'tray icon only: the window icon stays, whether this tool or you put it there' {
        Install-Icon 'blue' $null
        Install-Icon '' 'none' 6>$null
        Get-Sha (Join-Path $Target 'messengerWindow.ico') | Should -Be (Get-Sha (Join-Path $Root 'icons\blue\messengerWindow.ico'))
        Join-Path $Target 'newmail.ico' | Should -Not -Exist
        (Read-State).Icon | Should -Be 'blue'
        (Read-State).NewMail | Should -Be 'none'
        Restore-Originals 6>$null
        $DataDir | Should -Not -Exist

        Copy-Item $HandMade (Join-Path $Target 'messengerWindow.ico')
        Install-Icon '' 'uk' 6>$null
        Get-Sha (Join-Path $Target 'messengerWindow.ico') | Should -Be (Get-Sha $HandMade)
        Get-Sha (Join-Path $BackupDir 'messengerWindow.ico') | Should -Be (Get-Sha $HandMade)
        Get-Sha (Join-Path $Target 'newmail.ico') | Should -Be (Get-Sha (Join-Path $Root 'icons\uk\newmail.ico'))
        Restore-Originals 6>$null
        Get-Sha (Join-Path $Target 'messengerWindow.ico') | Should -Be (Get-Sha $HandMade)
        Join-Path $Target 'newmail.ico' | Should -Not -Exist
    }

    It 'tray icon only: keeps a window icon this tool installed when its copy in the data folder was lost' {
        Install-Icon 'blue' $null
        Remove-Item (Join-Path $CurrentDir 'messengerWindow.ico')
        Install-Icon '' 'none' 6>$null
        Get-Sha (Join-Path $Target 'messengerWindow.ico') | Should -Be (Get-Sha (Join-Path $Root 'icons\blue\messengerWindow.ico'))
    }

    It 'refuses a call that changes nothing' {
        { Install-Icon '' '' } | Should -Throw '*Nothing to change*'
        { Install-Icon '' 'keep' } | Should -Throw '*Nothing to change*'
        { Install-Icon $null $null } | Should -Throw '*Nothing to change*'
    }

    It 'puts a dot on the tray icon without any window icon chosen first' {
        $base = Get-DotBasePath
        $base | Should -Be (Join-Path $Root 'icons\bb\messengerWindow.ico')   # Betterbird's own design
        $dot = Join-Path $TestDrive 'betterbird-icons-dot-menu4.ico'
        Add-IconDot -Source $base -Dest $dot -Hex $DotColours['Gold']
        Install-Icon '' $dot 6>$null
        Get-Sha (Join-Path $Target 'newmail.ico') | Should -Be (Get-Sha $dot)
        (Read-State).NewMail | Should -Be 'Gold dot'
        Join-Path $Target 'messengerWindow.ico' | Should -Not -Exist
        Get-DotColourName (Get-CurrentNewMailPath) | Should -Be 'Gold'
    }

    It 'draws the dot on the window icon this tool installed, else Betterbird''s own design' {
        Install-Icon 'uk' $null
        Get-DotBasePath | Should -Be (Join-Path $Target 'messengerWindow.ico')
        Remove-Item (Join-Path $Target 'messengerWindow.ico')
        Get-DotBasePath | Should -Be (Join-Path $Root 'icons\uk\messengerWindow.ico')   # the record names uk
        Remove-Item $DataDir -Recurse -Force
        Get-DotBasePath | Should -Be (Join-Path $Root 'icons\bb\messengerWindow.ico')
    }

    It 'gives the shortcuts a different icon file each time the picture changes, and rewrites the .lnk' {
        Install-Icon 'uk' $null
        $first = $shell.CreateShortcut($Lnk).IconLocation
        $first | Should -Match 'shortcut-[0-9A-F]{12}\.ico,0$'
        (Get-Item $Lnk).LastWriteTime = [datetime]'2001-01-01'
        Install-Icon 'blue' $null
        $second = $shell.CreateShortcut($Lnk).IconLocation
        $second | Should -Match 'shortcut-[0-9A-F]{12}\.ico,0$'
        $second | Should -Not -Be $first
        (Get-Item $Lnk).LastWriteTime | Should -BeGreaterThan ([datetime]'2001-01-02')
        ($second -replace ',0$', '') | Should -Exist
        ($first -replace ',0$', '') | Should -Not -Exist   # the older file goes once the shortcut moved
        @(Get-ShortcutIconNames).Count | Should -Be 1
        Join-Path $CurrentDir 'messengerWindow.ico' | Should -Exist   # the backup logic still compares against it
        Get-Sha ($second -replace ',0$', '') | Should -Be (Get-Sha (Join-Path $CurrentDir 'messengerWindow.ico'))
    }

    It 'names the shortcut icon after its contents, so the same picture keeps the same file' {
        Install-Icon 'uk' $null
        $first = $shell.CreateShortcut($Lnk).IconLocation
        Install-Icon 'uk' 'none' 6>$null
        $shell.CreateShortcut($Lnk).IconLocation | Should -Be $first
        $first | Should -Match (Get-Sha (Join-Path $CurrentDir 'messengerWindow.ico')).Substring(0, 12)
    }

    It 'tells Explorer about each changed shortcut, and about the icon change once' {
        $script:notified = @()
        Mock Send-ShellNotify { $script:notified += $Path }
        Install-Icon 'uk' $null
        $script:notified | Should -Be @($Lnk)
    }

    It 'sets the file time of every icon file it installs to now' {
        $old = Join-Path $TestDrive 'old-times.ico'
        Copy-Item (Join-Path $Root 'icons\uk\messengerWindow.ico') $old
        (Get-Item $old).LastWriteTime = [datetime]'2001-01-01'
        $oldMail = Join-Path $TestDrive 'old-mail.ico'
        Copy-Item (Join-Path $Root 'icons\uk\newmail.ico') $oldMail
        (Get-Item $oldMail).LastWriteTime = [datetime]'2001-01-01'
        Install-Icon $old $oldMail
        $recent = (Get-Date).AddMinutes(-5)
        foreach ($f in (Join-Path $Target 'messengerWindow.ico'), (Join-Path $Target 'newmail.ico'),
                       (Join-Path $CurrentDir 'messengerWindow.ico'), (Join-Path $CurrentDir 'newmail.ico')) {
            (Get-Item $f).LastWriteTime | Should -BeGreaterThan $recent -Because $f
        }
        foreach ($name in Get-ShortcutIconNames) { (Get-Item (Join-Path $CurrentDir $name)).LastWriteTime | Should -BeGreaterThan $recent }
    }

    It 'keeps the older shortcut icon file while a shortcut that could not be changed still uses it' {
        Install-Icon 'uk' $null
        $old = Get-ShortcutIconNames
        Mock Save-ShortcutIcon { $false }
        Install-Icon 'blue' $null 6>$null
        @(Get-ShortcutIconNames).Count | Should -Be 2
        $old | ForEach-Object { Join-Path $CurrentDir $_ | Should -Exist }
    }

    It 'moves a shortcut that still has the old fixed icon path onto a shortcut file' {
        Install-Icon 'uk' $null
        $s = $shell.CreateShortcut($Lnk); $s.IconLocation = (Join-Path $CurrentDir 'messengerWindow.ico') + ',0'; $s.Save()
        Install-Icon 'uk' 'none' 6>$null
        $shell.CreateShortcut($Lnk).IconLocation | Should -Match 'shortcut-[0-9A-F]{12}\.ico,0$'
    }

    It 'Restore puts back a shortcut that uses the old fixed path or a shortcut file' {
        Install-Icon 'blue' $null
        $recorded = $shell.CreateShortcut($Lnk).IconLocation
        $recorded | Should -Match 'shortcut-'
        Restore-Originals 6>$null
        $shell.CreateShortcut($Lnk).IconLocation | Should -Not -Match 'Data'
        $DataDir | Should -Not -Exist

        Install-Icon 'blue' $null
        $s = $shell.CreateShortcut($Lnk); $s.IconLocation = (Join-Path $CurrentDir 'messengerWindow.ico') + ',0'; $s.Save()
        Restore-Originals 6>$null
        $shell.CreateShortcut($Lnk).IconLocation | Should -Not -Match 'Data'
    }

    It 'Restore and the factory reset also reset a shortcut the record does not list' {
        Install-Icon 'blue' $null
        Set-Content $StateFile (@{ Icon = 'blue'; InstallDir = $InstallDir } | ConvertTo-Json)   # shortcuts forgotten
        Restore-Originals 6>$null
        $shell.CreateShortcut($Lnk).IconLocation | Should -Be ',0'

        Install-Icon 'blue' $null
        Reset-Factory 6>$null
        $shell.CreateShortcut($Lnk).IconLocation | Should -Be ',0'
        $DataDir | Should -Not -Exist
    }

    It 'Remove-DataDir removes the shortcut icon files and nothing else of that name' {
        Install-Icon 'blue' $null
        @(Get-ShortcutIconNames).Count | Should -Be 1
        Set-Content (Join-Path $CurrentDir 'shortcut-notmine.ico') 'x'
        Remove-DataDir 6>$null
        Get-ChildItem $CurrentDir -Filter 'shortcut-[0-9A-F]*.ico' | Should -BeNullOrEmpty
        Join-Path $CurrentDir 'shortcut-notmine.ico' | Should -Exist   # not one of ours: stays
    }

    It 'Remove-DataDir does not delete through a link at current' {
        $elsewhere = Join-Path $TestDrive 'ShortcutDecoy'
        New-Item -ItemType Directory -Path $elsewhere, $DataDir, $BackupDir | Out-Null
        Set-Content (Join-Path $elsewhere 'shortcut-0123456789AB.ico') 'must survive'
        New-Item -ItemType Junction -Path $CurrentDir -Target $elsewhere | Out-Null
        Remove-DataDir 6>$null 3>$null
        Join-Path $elsewhere 'shortcut-0123456789AB.ico' | Should -Exist
        [IO.Directory]::Delete($CurrentDir)   # the junction only, not what it points at
    }

    It 'recognises only this tool''s shortcut icons' {
        Test-OurShortcutIcon ((Join-Path $CurrentDir 'messengerWindow.ico') + ',0') | Should -BeTrue
        Test-OurShortcutIcon ((Join-Path $CurrentDir 'shortcut-0123456789ab.ico') + ',0') | Should -BeTrue
        Test-OurShortcutIcon ((Join-Path $CurrentDir 'shortcut-0123456789ab.ico')) | Should -BeTrue
        Test-OurShortcutIcon ((Join-Path $CurrentDir 'other.ico') + ',0') | Should -BeFalse
        Test-OurShortcutIcon ((Join-Path $CurrentDir 'shortcut-xyz.ico') + ',0') | Should -BeFalse
        Test-OurShortcutIcon ((Join-Path $DataDir 'shortcut-0123456789ab.ico') + ',0') | Should -BeFalse
        Test-OurShortcutIcon 'C:\Windows\System32\shell32.dll,3' | Should -BeFalse
        Test-OurShortcutIcon ',0' | Should -BeFalse
        Test-OurShortcutIcon '' | Should -BeFalse
    }

    It 'does not trust a data folder where a shortcut icon file is a link' {
        . $Script   # the real trust check, not the stub above; this also resets the folders below
        $Mode = 'own'
        $DataDir = Join-Path $InstallDir 'Data'
        $BackupDir = Join-Path $DataDir 'backup'
        $CurrentDir = Join-Path $DataDir 'current'
        $StateFile = Join-Path $DataDir 'state.json'
        New-Item -ItemType Directory -Path $BackupDir, $CurrentDir -Force | Out-Null
        Set-Content $StateFile '{}'
        Set-Content (Join-Path $CurrentDir 'shortcut-0123456789AB.ico') 'x'
        Test-DataDirTrusted | Should -BeTrue
        Mock Test-ReparsePoint { $Path -like '*shortcut-0123456789AB.ico' }
        Test-DataDirTrusted | Should -BeFalse
    }

    It 'tells the shell about the change: compiles, and the real cache refresh sends it' {
        . $Script
        Initialize-ShellNotify
        [BetterbirdIcons.ShellNotify].GetMethod('UpdateItem') | Should -Not -BeNullOrEmpty
        [BetterbirdIcons.ShellNotify].GetMethod('AssocChanged') | Should -Not -BeNullOrEmpty
        Mock Send-ShellNotify { }
        Mock Test-Path { $false } -ParameterFilter { $LiteralPath -like '*ie4uinit.exe' }
        Update-IconCache
        Should -Invoke Send-ShellNotify -Times 1 -Exactly -ParameterFilter { -not $Path }
    }
}

Describe 'Mail popup for any icon set' {
    BeforeAll {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        function New-FakeOmni([string]$Dir) {
            New-Item -ItemType Directory -Path $Dir | Out-Null
            $omni = Join-Path $Dir 'omni.ja'
            $zip = [IO.Compression.ZipFile]::Open($omni, 'Create')
            try {
                foreach ($pair in @(
                        @{ Name = 'chrome/messenger/content/branding/icon64.png'; Text = 'old-64' },
                        @{ Name = 'chrome/messenger/content/branding/icon128.png'; Text = 'old-128' },
                        @{ Name = 'chrome/keep.txt'; Text = 'keep-me' })) {
                    $out = $zip.CreateEntry($pair.Name).Open()
                    try { $bytes = [Text.Encoding]::ASCII.GetBytes($pair.Text); $out.Write($bytes, 0, $bytes.Length) }
                    finally { $out.Dispose() }
                }
            }
            finally { $zip.Dispose() }
            $omni
        }
        function Read-Entry([string]$Path, [string]$EntryName) {
            $read = [IO.Compression.ZipFile]::OpenRead($Path)
            try {
                $entry = $read.GetEntry($EntryName)
                if (-not $entry) { return $null }
                $stream = $entry.Open()
                try { $memory = New-Object IO.MemoryStream; $stream.CopyTo($memory); return ,$memory.ToArray() }
                finally { $stream.Dispose() }
            }
            finally { $read.Dispose() }
        }
    }

    It 'draws 64 and 128 pixel pictures from a set that has no ready-made popup, round with a clear background' {
        foreach ($set in 'bb', 'uk', 'green2', 'lightgrey', 'bb-green') {
            $files = Get-PopupBytes -Name $set
            foreach ($jar in $PopupFiles.Keys) {
                $size = $PopupFiles[$jar].Size
                Test-PopupPng -Bytes $files[$jar] -Size $size | Should -BeTrue -Because "$set $size"
                $png = New-Object IO.MemoryStream (,$files[$jar])
                $bmp = New-Object System.Drawing.Bitmap $png
                try {
                    $bmp.GetPixel(0, 0).A | Should -Be 0 -Because "$set corner"
                    $solid = 0
                    for ($y = 0; $y -lt $size; $y += 4) { for ($x = 0; $x -lt $size; $x += 4) { if ($bmp.GetPixel($x, $y).A -gt 200) { $solid++ } } }
                    $solid | Should -BeGreaterThan 10 -Because "$set has a picture"
                }
                finally { $bmp.Dispose(); $png.Dispose() }
            }
        }
    }

    It 'uses the ready-made picture for blue, and makes one from your own .ico' {
        $blue = Get-PopupBytes -Name 'blue'
        Get-BytesHash -Bytes $blue['chrome/messenger/content/branding/icon64.png'] |
            Should -Be (Get-BytesHash -Bytes ([IO.File]::ReadAllBytes((Join-Path $Root 'icons\popup\yours\icon64.png'))))
        (Get-PopupBytes -Name 'yours')['chrome/messenger/content/branding/icon128.png'].Length | Should -Be $blue['chrome/messenger/content/branding/icon128.png'].Length
        $mine = Join-Path $TestDrive 'popup-source.ico'
        Copy-Item (Join-Path $Root 'icons\lightgrey\messengerWindow.ico') $mine
        $custom = Get-PopupBytes -Name $mine
        Test-PopupPng -Bytes $custom['chrome/messenger/content/branding/icon128.png'] -Size 128 | Should -BeTrue
        { Get-PopupBytes -Name (Join-Path $Root 'README.md') } | Should -Throw
    }

    It 'changes the popup to a set, remembers which one, and Betterbird''s own puts the saved originals back' {
        $dir = Join-Path $TestDrive 'PopupSets'
        $omni = New-FakeOmni $dir
        $Mode = 'own'; $AppDir = $dir
        $jar64 = 'chrome/messenger/content/branding/icon64.png'
        Get-MailPopupName | Should -BeNullOrEmpty

        Set-MailPopup -Name 'uk' 6>$null
        Get-MailPopupName | Should -Be 'uk'
        Get-BytesHash -Bytes (Read-Entry $omni $jar64) | Should -Be (Get-BytesHash -Bytes (Get-PopupBytes -Name 'uk')[$jar64])
        [Text.Encoding]::ASCII.GetString((Read-Entry $omni ($jar64 + $PopupSaved))) | Should -Be 'old-64'
        Set-MailPopup -Name 'uk' 6>$null   # already there: nothing happens

        Set-MailPopup -Name 'green2' 6>$null
        Get-MailPopupName | Should -Be 'green2'
        # The saved original is still Betterbird's own, not the uk picture.
        [Text.Encoding]::ASCII.GetString((Read-Entry $omni ($jar64 + $PopupSaved))) | Should -Be 'old-64'

        Set-MailPopup -Name 'yours' 6>$null
        Get-MailPopupName | Should -Be 'blue'

        Set-MailPopup -Name 'factory' 6>$null
        [Text.Encoding]::ASCII.GetString((Read-Entry $omni $jar64)) | Should -Be 'old-64'
        [Text.Encoding]::ASCII.GetString((Read-Entry $omni 'chrome/messenger/content/branding/icon128.png')) | Should -Be 'old-128'
        [Text.Encoding]::ASCII.GetString((Read-Entry $omni 'chrome/keep.txt')) | Should -Be 'keep-me'
        $check = [IO.Compression.ZipFile]::OpenRead($omni)
        try { $check.Entries.Count | Should -Be 3 } finally { $check.Dispose() }   # saved copies and marker are gone
        Get-MailPopupName | Should -BeNullOrEmpty
    }

    It 'accepts your own .ico, and names it custom' {
        $dir = Join-Path $TestDrive 'PopupCustom'
        $omni = New-FakeOmni $dir
        $Mode = 'own'; $AppDir = $dir
        $mine = Join-Path $TestDrive 'popup-custom.ico'
        Copy-Item (Join-Path $Root 'icons\bb-green\messengerWindow.ico') $mine
        Set-MailPopup -Name $mine 6>$null
        Get-MailPopupName | Should -Be 'custom'
        Get-PopupLabel 'custom' | Should -Be 'your own picture'
    }

    It 'does not believe the marker when the pictures have been replaced since' {
        $dir = Join-Path $TestDrive 'PopupStale'
        $omni = New-FakeOmni $dir
        $Mode = 'own'; $AppDir = $dir
        Set-MailPopup -Name 'uk' 6>$null
        $found = Read-PopupEntries $omni
        Get-PopupMarkerSet $found | Should -Be 'uk'
        $found['chrome/messenger/content/branding/icon64.png'] = [byte[]](1, 2, 3)
        Get-PopupMarkerSet $found | Should -BeNullOrEmpty
        $found = Read-PopupEntries $omni
        $found[$PopupMarker] = [Text.Encoding]::UTF8.GetBytes("set=../../evil`r`n")
        Get-PopupMarkerSet $found | Should -BeNullOrEmpty
    }

    It 'keeps the original saved when moving from blue made by an older version to another set' {
        $dir = Join-Path $TestDrive 'PopupFromOldBlue'
        $omni = New-FakeOmni $dir
        $Mode = 'own'; $AppDir = $dir
        # An older version left blue behind with no saved original and no marker.
        $blue = Get-PopupBytes -Name 'blue'
        $tmp = Join-Path $dir 'omni.new'
        Initialize-StoredJar
        [BetterbirdIcons.StoredJar]::Write($omni, $tmp, $blue)
        Move-Item $tmp $omni -Force
        Get-MailPopupName | Should -Be 'blue'
        Set-MailPopup -Name 'uk' 6>$null
        Get-MailPopupName | Should -Be 'uk'
        Read-Entry $omni ('chrome/messenger/content/branding/icon64.png' + $PopupSaved) | Should -BeNullOrEmpty   # blue is not Betterbird's own
        Mock Write-Warn { }
        Set-MailPopup -Name 'factory' 6>$null
        Should -Invoke Write-Warn -Times 1 -ParameterFilter { $Text -like '*copy that comes with this tool*' }
        Get-MailPopupName | Should -Be 'factory'
    }

    It 'says which tray icon and popup are in place in Status' {
        $InstallDir = Join-Path $TestDrive 'StatusApp'
        function Get-InstallDir { $InstallDir }
        New-Item -ItemType Directory -Path (Join-Path $InstallDir 'chrome\icons\default') -Force | Out-Null
        Set-Content (Join-Path $InstallDir 'betterbird.exe') '' -Encoding ASCII
        $DataDir = Join-Path $InstallDir 'Data'; $BackupDir = Join-Path $DataDir 'backup'
        $CurrentDir = Join-Path $DataDir 'current'; $StateFile = Join-Path $DataDir 'state.json'
        $UserAppData = Join-Path $InstallDir 'AppData'; $UserStartMenu = Join-Path $InstallDir 'SM'; $UserDesktop = Join-Path $InstallDir 'D'
        New-Item -ItemType Directory -Path $UserDesktop, $UserStartMenu | Out-Null
        $out = Show-Status 6>&1 | Out-String
        $out | Should -Match "Tray icon:\s+Betterbird's own"
        $out | Should -Match 'Mail popup:\s+not changed by this tool'
        Install-Icon 'uk' $null 6>$null
        Copy-Item (Join-Path $Root 'icons\bb-green\newmail.ico') (Join-Path $InstallDir 'chrome\icons\default\newmail.ico') -Force
        $out = Show-Status 6>&1 | Out-String
        $out | Should -Match 'Tray icon:\s+a custom icon not put there by this tool'
        $omni = New-FakeOmni (Join-Path $InstallDir 'omnidir')
        Move-Item $omni (Join-Path $InstallDir 'omni.ja')
        Set-MailPopup -Name 'green2' 6>$null
        $out = Show-Status 6>&1 | Out-String
        $out | Should -Match 'Mail popup:\s+green2'
        Install-Icon '' 'uk' 6>$null
        (Show-Status 6>&1 | Out-String) | Should -Match 'Tray icon:\s+uk'
    }
}

Describe 'The preview page' {
    It 'is built from the same lists as the menu, so the numbers match' {
        $html = Get-IconPageHtml
        $window = @(Get-MenuIconSets 'window')
        $tray = @(Get-MenuIconSets 'newmail')
        foreach ($name in Get-MenuIconSets 'all') {
            $row = [regex]::Match($html, "(?m)^\s*<tr><td[^>]*>$([regex]::Escape($name))</td>(.*)</tr>\s*$").Groups[1].Value
            $row | Should -Not -BeNullOrEmpty -Because $name
            $w = [array]::IndexOf($window, $name) + 1
            $t = [array]::IndexOf($tray, $name) + 1
            if ($w) { $row | Should -Match "<td class=`"num`">$w</td><td><img src=`"\.\./icons/$name/messengerWindow\.ico`"" }
            else { $row | Should -Not -Match 'messengerWindow' }
            if ($t) { $row | Should -Match "<td class=`"num`">$t</td><td><img src=`"\.\./icons/$name/newmail\.ico`"" }
            if ($w) { $row | Should -Match "<td class=`"num`">$w</td><td><img src=`"data:image/png;base64," }
        }
        $html | Should -Match "<td class=`"num`">$($window.Count + 1)</td><td><img src=`"data:image/png;base64,"
    }

    It 'matches the printed page in images, apart from the embedded pictures' {
        $normal = { param($t) ($t -replace 'data:image/png;base64,[A-Za-z0-9+/=]+', 'data:') -replace "`r`n", "`n" }
        (& $normal (Get-IconPageHtml)).Trim() | Should -Be (& $normal ([IO.File]::ReadAllText((Join-Path $Root 'images\choose.html')))).Trim()
    }

    It 'points at this download folder when asked' {
        $html = Get-IconPageHtml -Absolute
        $html | Should -Match 'src="file:///[^"]*/icons/blue/messengerWindow\.ico"'
    }
}
