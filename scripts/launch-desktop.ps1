param([switch]$NoBrowser,[switch]$NoDialog)
$ErrorActionPreference='Stop'
$Host.UI.RawUI.WindowTitle='PawdayV1 - Starting local test environment'
Write-Host 'PawdayV1 is starting. The browser opens when services are ready.'
try{& (Join-Path $PSScriptRoot 'desktop.ps1') -Action Start -NoBrowser:$NoBrowser}
catch{
 $message='PawdayV1 could not start.'+[Environment]::NewLine+$_.Exception.Message+[Environment]::NewLine+'Private diagnostic logs: .pilot/desktop-*/backend.log and desktop-error.log.'
 Write-Host $message -ForegroundColor Red
 if(-not $NoDialog){Add-Type -AssemblyName System.Windows.Forms;[void][Windows.Forms.MessageBox]::Show($message,'PawdayV1',0,16)}
 exit 1
}
