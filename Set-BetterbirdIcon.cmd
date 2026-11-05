@echo off
rem Double-click for the menu, or pass options, e.g.  Set-BetterbirdIcon.cmd -Icon blue
rem Full path, so a powershell.exe in this folder isn't picked up.
rem pwsh passes its module path down, which breaks Windows PowerShell.
set "PSModulePath=%ProgramFiles%\WindowsPowerShell\Modules;%SystemRoot%\System32\WindowsPowerShell\v1.0\Modules"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0Set-BetterbirdIcon.ps1" %*
