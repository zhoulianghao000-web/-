param([Parameter(Mandatory=$true)][string]$DeliveryRoot)
$ErrorActionPreference='Stop'
$taskRoot=(Resolve-Path -LiteralPath $DeliveryRoot).Path
$entry=Join-Path $taskRoot 'scripts/launch-desktop.ps1';if(-not(Test-Path -LiteralPath $entry)){throw 'Extract the complete delivery first.'}
$desktop=[Environment]::GetFolderPath('DesktopDirectory')
$icon=Join-Path $taskRoot 'desktop/pawday-hd.ico'
if(-not(Test-Path -LiteralPath $icon)){$icon=Join-Path $taskRoot 'desktop/pawday.ico'}
if(-not(Test-Path -LiteralPath $icon)){
Add-Type -AssemblyName System.Drawing
$bitmap=New-Object Drawing.Bitmap(128,128);$graphics=[Drawing.Graphics]::FromImage($bitmap)
$graphics.SmoothingMode=[Drawing.Drawing2D.SmoothingMode]::AntiAlias
$graphics.Clear([Drawing.ColorTranslator]::FromHtml('#294e40'));$brush=New-Object Drawing.SolidBrush([Drawing.ColorTranslator]::FromHtml('#eceddc'))
foreach($ellipse in @(@(20,30,22,30),@(47,17,22,30),@(74,21,22,30),@(94,40,20,28),@(37,59,59,48))){$graphics.FillEllipse($brush,[int]$ellipse[0],[int]$ellipse[1],[int]$ellipse[2],[int]$ellipse[3])}
$memory=New-Object IO.MemoryStream
try{
 $bitmap.Save($memory,[Drawing.Imaging.ImageFormat]::Png);$bytes=$memory.ToArray();$stream=[IO.File]::Create($icon);$writer=New-Object IO.BinaryWriter($stream)
 try{$writer.Write([uint16]0);$writer.Write([uint16]1);$writer.Write([uint16]1);$writer.Write([byte]128);$writer.Write([byte]128);$writer.Write([byte]0);$writer.Write([byte]0);$writer.Write([uint16]1);$writer.Write([uint16]32);$writer.Write([uint32]$bytes.Length);$writer.Write([uint32]22);$writer.Write($bytes)}finally{$writer.Dispose();$stream.Dispose()}
}finally{$memory.Dispose();$brush.Dispose();$graphics.Dispose();$bitmap.Dispose()}
}
$shell=New-Object -ComObject WScript.Shell
$linkPath=Join-Path $desktop 'PawdayV1.lnk'
if(Test-Path -LiteralPath $linkPath){
 $old=$shell.CreateShortcut($linkPath)
 if($old.WorkingDirectory -ne $taskRoot){$linkPath=Join-Path $desktop ('PawdayV1-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'.lnk')}
}
$link=$shell.CreateShortcut($linkPath)
$link.TargetPath=Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
$link.Arguments='-NoProfile -ExecutionPolicy Bypass -File "'+$entry+'"'
$link.WorkingDirectory=$taskRoot;$link.IconLocation=$icon+',0';$link.Description='PawdayV1 - local simulated engineering edition';$link.Save()
$verified=$shell.CreateShortcut($linkPath)
if($verified.WorkingDirectory -ne $taskRoot -or -not(Test-Path -LiteralPath $linkPath)){throw 'Shortcut verification failed'}
Write-Output $linkPath
