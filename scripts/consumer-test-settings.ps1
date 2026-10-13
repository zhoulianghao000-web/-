function Get-PawdayConsumerTestCredential {
 $taskSettings=Join-Path $env:LOCALAPPDATA 'PawdayV1/consumer-test-login.clixml'
 if(Test-Path -LiteralPath $taskSettings){return Import-Clixml -LiteralPath $taskSettings}
 Add-Type -AssemblyName System.Windows.Forms
 $taskForm=New-Object Windows.Forms.Form;$taskForm.Text='Pawday - Configure single LOCAL test account';$taskForm.Width=420;$taskForm.Height=240;$taskForm.StartPosition='CenterScreen'
 $taskNameLabel=New-Object Windows.Forms.Label;$taskNameLabel.Text='Test account';$taskNameLabel.SetBounds(20,20,350,22)
 $taskName=New-Object Windows.Forms.TextBox;$taskName.SetBounds(20,45,350,25)
 $taskPasswordLabel=New-Object Windows.Forms.Label;$taskPasswordLabel.Text='Test password (LOCAL simulated environment only)';$taskPasswordLabel.SetBounds(20,80,350,22)
 $taskPassword=New-Object Windows.Forms.TextBox;$taskPassword.UseSystemPasswordChar=$true;$taskPassword.SetBounds(20,105,350,25)
 $taskSave=New-Object Windows.Forms.Button;$taskSave.Text='Save';$taskSave.SetBounds(270,150,100,32);$taskSave.DialogResult=[Windows.Forms.DialogResult]::OK
 $taskForm.Controls.AddRange(@($taskNameLabel,$taskName,$taskPasswordLabel,$taskPassword,$taskSave));$taskForm.AcceptButton=$taskSave
 try{if($taskForm.ShowDialog() -ne [Windows.Forms.DialogResult]::OK -or [string]::IsNullOrWhiteSpace($taskName.Text) -or [string]::IsNullOrWhiteSpace($taskPassword.Text)){throw 'A single test account and password must be configured before starting this local pilot.'};$taskCredential=New-Object Management.Automation.PSCredential($taskName.Text,(ConvertTo-SecureString $taskPassword.Text -AsPlainText -Force));[void][IO.Directory]::CreateDirectory((Split-Path -Parent $taskSettings));$taskCredential | Export-Clixml -LiteralPath $taskSettings;return $taskCredential}finally{$taskPassword.Clear();$taskForm.Dispose()}
}
