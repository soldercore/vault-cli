Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Security

# --- Design Colors (modern touch)
$color_bg = [System.Drawing.Color]::FromArgb(36,36,48)
$color_fg = [System.Drawing.Color]::FromArgb(240,240,240)
$color_btn = [System.Drawing.Color]::FromArgb(0,209,160)
$color_danger = [System.Drawing.Color]::FromArgb(220,38,38)

# --- Crypto functions
function Derive-Key($password, $salt) {
    $deriveBytes = New-Object System.Security.Cryptography.Rfc2898DeriveBytes($password, $salt, 200000)
    return $deriveBytes.GetBytes(32) # 256-bit key
}
function Encrypt-Data($plainText, $key, $iv) {
    $aes = [System.Security.Cryptography.Aes]::Create()
    $aes.Key = $key
    $aes.IV = $iv
    $encryptor = $aes.CreateEncryptor()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($plainText)
    $encrypted = $encryptor.TransformFinalBlock($bytes, 0, $bytes.Length)
    return [Convert]::ToBase64String($encrypted)
}
function Decrypt-Data($cipherText, $key, $iv) {
    $aes = [System.Security.Cryptography.Aes]::Create()
    $aes.Key = $key
    $aes.IV = $iv
    $decryptor = $aes.CreateDecryptor()
    $bytes = [Convert]::FromBase64String($cipherText)
    $decrypted = $decryptor.TransformFinalBlock($bytes, 0, $bytes.Length)
    return [System.Text.Encoding]::UTF8.GetString($decrypted)
}
function Generate-RandomFileName {
    $guid = [System.Guid]::NewGuid().ToString().Replace("-", "")
    return "$env:APPDATA\$guid.dat"
}
function Overwrite-And-DeleteFile($filePath) {
    if (Test-Path $filePath) {
        $bytes = [System.IO.File]::ReadAllBytes($filePath)
        $random = New-Object byte[] $bytes.Length
        [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($random)
        [System.IO.File]::WriteAllBytes($filePath, $random)
        Remove-Item $filePath -Force
    }
}

# --- Global state
$vaultFile = Generate-RandomFileName
$vault = @()
$salt = [byte[]]::new(16)
$iv = [byte[]]::new(16)
$master = $null
$unlocked = $false
$lastActivity = [datetime]::Now

# --- Main Window
$form = New-Object Windows.Forms.Form
$form.Text = "🔐 SecureVault"
$form.Size = New-Object Drawing.Size(440,500)
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.BackColor = $color_bg
$form.ForeColor = $color_fg
$form.StartPosition = "CenterScreen"
$form.Topmost = $true

# --- Helper for styling
function Style-Button($btn, $danger=$false) {
    $btn.FlatStyle = 'Flat'
    $btn.BackColor = $(if ($danger) { $color_danger } else { $color_btn })
    $btn.ForeColor = $color_fg
    $btn.Font = New-Object Drawing.Font('Segoe UI',10,[Drawing.FontStyle]::Bold)
    $btn.FlatAppearance.BorderSize = 0
}
function Style-Label($lbl, $large=$false) {
    $lbl.ForeColor = $color_fg
    if ($large) { $lbl.Font = New-Object Drawing.Font('Segoe UI',11,[Drawing.FontStyle]::Bold) }
}

# --- Welcome / Setup Step
function Show-Welcome {
    $f = New-Object Windows.Forms.Form
    $f.Text = "Welcome to SecureVault"
    $f.Size = New-Object Drawing.Size(370,220)
    $f.FormBorderStyle = 'FixedDialog'
    $f.StartPosition = "CenterScreen"
    $f.BackColor = $color_bg
    $lbl = New-Object Windows.Forms.Label
    $lbl.Text = "Welcome! Create your master password below."
    $lbl.Location = '15,20'
    $lbl.Size = '330,28'
    Style-Label $lbl $true
    $f.Controls.Add($lbl)
    $p1 = New-Object Windows.Forms.Label
    $p1.Text = "Master Password:"
    $p1.Location = '15,65'
    $p1.Size = '120,18'
    $f.Controls.Add($p1)
    $tb1 = New-Object Windows.Forms.TextBox
    $tb1.Location = '145,63'
    $tb1.Size = '190,22'
    $tb1.UseSystemPasswordChar = $true
    $f.Controls.Add($tb1)
    $p2 = New-Object Windows.Forms.Label
    $p2.Text = "Confirm Password:"
    $p2.Location = '15,95'
    $p2.Size = '120,18'
    $f.Controls.Add($p2)
    $tb2 = New-Object Windows.Forms.TextBox
    $tb2.Location = '145,93'
    $tb2.Size = '190,22'
    $tb2.UseSystemPasswordChar = $true
    $f.Controls.Add($tb2)
    $info = New-Object Windows.Forms.Label
    $info.Text = "Must be at least 12 characters. Write it down!"
    $info.Location = '15,123'
    $info.Size = '330,16'
    $info.ForeColor = 'Yellow'
    $f.Controls.Add($info)
    $okBtn = New-Object Windows.Forms.Button
    $okBtn.Text = "Set Master Password"
    $okBtn.Location = '80,150'
    $okBtn.Size = '180,30'
    Style-Button $okBtn
    $f.Controls.Add($okBtn)
    $error = New-Object Windows.Forms.Label
    $error.Location = '20,185'
    $error.Size = '310,16'
    $error.ForeColor = 'Red'
    $f.Controls.Add($error)
    $okBtn.Add_Click({
        if ($tb1.Text.Length -lt 12) {
            $error.Text = "Password too short!"
        } elseif ($tb1.Text -ne $tb2.Text) {
            $error.Text = "Passwords do not match!"
        } else {
            $master = $tb1.Text
            [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($salt)
            [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($iv)
            # Velg filplassering:
            $dlg = New-Object System.Windows.Forms.SaveFileDialog
            $dlg.Title = "Select location for your encrypted vault file"
            $dlg.Filter = "Data Files (*.dat)|*.dat|All Files (*.*)|*.*"
            $dlg.InitialDirectory = $env:APPDATA
            if ($dlg.ShowDialog() -eq "OK") {
                $global:vaultFile = $dlg.FileName
                $f.Close()
            } else {
                $error.Text = "You must select a file!"
            }
        }
    })
    $f.ShowDialog()
}

# --- Prompt for master password
function Prompt-Master {
    $f = New-Object Windows.Forms.Form
    $f.Text = "Unlock SecureVault"
    $f.Size = New-Object Drawing.Size(320,150)
    $f.FormBorderStyle = 'FixedDialog'
    $f.StartPosition = "CenterScreen"
    $f.BackColor = $color_bg
    $lbl = New-Object Windows.Forms.Label
    $lbl.Text = "Enter your master password to unlock:"
    $lbl.Location = '18,15'
    $lbl.Size = '270,18'
    Style-Label $lbl
    $f.Controls.Add($lbl)
    $tb = New-Object Windows.Forms.TextBox
    $tb.Location = '18,45'
    $tb.Size = '270,20'
    $tb.UseSystemPasswordChar = $true
    $f.Controls.Add($tb)
    $err = New-Object Windows.Forms.Label
    $err.Location = '18,75'
    $err.Size = '260,18'
    $err.ForeColor = 'Red'
    $f.Controls.Add($err)
    $okBtn = New-Object Windows.Forms.Button
    $okBtn.Text = "Unlock"
    $okBtn.Location = '95,100'
    $okBtn.Size = '100,28'
    Style-Button $okBtn
    $f.Controls.Add($okBtn)
    $success = $false
    $okBtn.Add_Click({
        $global:master = $tb.Text
        try {
            $fileBytes = [System.IO.File]::ReadAllBytes($global:vaultFile)
            $global:salt = $fileBytes[0..15]
            $global:iv = $fileBytes[16..31]
            $encrypted = $fileBytes[32..($fileBytes.Length-1)]
            $data = [System.Convert]::ToBase64String($encrypted)
            $key = Derive-Key $global:master $global:salt
            $json = Decrypt-Data $data $key $global:iv
            $global:vault = ConvertFrom-Json $json
            $success = $true
            $f.Close()
        } catch {
            $err.Text = "Wrong password or corrupted file!"
        }
    })
    $f.ShowDialog()
    return $success
}

# --- Main GUI elements
$vaultList = New-Object Windows.Forms.ListBox
$vaultList.Location = New-Object Drawing.Point(10,80)
$vaultList.Size = New-Object Drawing.Size(400,180)
$vaultList.Enabled = $false
$form.Controls.Add($vaultList)

$addBtn = New-Object Windows.Forms.Button
$addBtn.Text = "Add Entry"
$addBtn.Location = '10,270'
$addBtn.Size = '100,32'
Style-Button $addBtn
$addBtn.Enabled = $false
$form.Controls.Add($addBtn)

$editBtn = New-Object Windows.Forms.Button
$editBtn.Text = "Edit"
$editBtn.Location = '120,270'
$editBtn.Size = '70,32'
Style-Button $editBtn
$editBtn.Enabled = $false
$form.Controls.Add($editBtn)

$delBtn = New-Object Windows.Forms.Button
$delBtn.Text = "Delete"
$delBtn.Location = '200,270'
$delBtn.Size = '70,32'
Style-Button $delBtn $true
$delBtn.Enabled = $false
$form.Controls.Add($delBtn)

$showBtn = New-Object Windows.Forms.Button
$showBtn.Text = "Show Password"
$showBtn.Location = '280,270'
$showBtn.Size = '130,32'
Style-Button $showBtn
$showBtn.Enabled = $false
$form.Controls.Add($showBtn)

$clipBtn = New-Object Windows.Forms.Button
$clipBtn.Text = "Copy to Clipboard"
$clipBtn.Location = '10,310'
$clipBtn.Size = '200,32'
Style-Button $clipBtn
$clipBtn.Enabled = $false
$form.Controls.Add($clipBtn)

$lockBtn = New-Object Windows.Forms.Button
$lockBtn.Text = "Lock Vault"
$lockBtn.Location = '220,310'
$lockBtn.Size = '110,32'
Style-Button $lockBtn
$lockBtn.Enabled = $false
$form.Controls.Add($lockBtn)

$destroyBtn = New-Object Windows.Forms.Button
$destroyBtn.Text = "Destroy Vault"
$destroyBtn.Location = '340,310'
$destroyBtn.Size = '80,32'
Style-Button $destroyBtn $true
$form.Controls.Add($destroyBtn)

# --- Enable/Disable all vault features
function Set-Unlocked($value) {
    $vaultList.Enabled = $value
    $addBtn.Enabled = $value
    $editBtn.Enabled = $value
    $delBtn.Enabled = $value
    $showBtn.Enabled = $value
    $clipBtn.Enabled = $value
    $lockBtn.Enabled = $value
    if ($value) {
        $infoLabel.Text = "Vault is unlocked."
        $infoLabel.ForeColor = 'Green'
    } else {
        $infoLabel.Text = "Vault is locked."
        $infoLabel.ForeColor = 'Red'
    }
    $global:unlocked = $value
}

# --- Vault Save
function Save-Vault {
    $json = $global:vault | ConvertTo-Json -Compress
    $key = Derive-Key $global:master $global:salt
    $encrypted = Encrypt-Data $json $key $global:iv
    $vaultData = $global:salt + $global:iv + [System.Convert]::FromBase64String($encrypted)
    [System.IO.File]::WriteAllBytes($global:vaultFile, $vaultData)
}

# --- Add entry
$addBtn.Add_Click({
    $f = New-Object Windows.Forms.Form
    $f.Text = "Add Entry"
    $f.Size = '310,220'
    $f.FormBorderStyle = 'FixedDialog'
    $f.StartPosition = "CenterScreen"
    $lblA = New-Object Windows.Forms.Label; $lblA.Text="Account:"; $lblA.Location="18,15"; $lblA.Size="80,18"; $f.Controls.Add($lblA)
    $tbA = New-Object Windows.Forms.TextBox; $tbA.Location="110,13"; $tbA.Size="160,22"; $f.Controls.Add($tbA)
    $lblP = New-Object Windows.Forms.Label; $lblP.Text="Password:"; $lblP.Location="18,45"; $lblP.Size="80,18"; $f.Controls.Add($lblP)
    $tbP = New-Object Windows.Forms.TextBox; $tbP.Location="110,43"; $tbP.Size="160,22"; $tbP.UseSystemPasswordChar=$true; $f.Controls.Add($tbP)
    $ok = New-Object Windows.Forms.Button; $ok.Text="OK"; $ok.Location="100,110"; $ok.Size="100,28"; Style-Button $ok; $f.Controls.Add($ok)
    $msg = New-Object Windows.Forms.Label; $msg.Location="18,85"; $msg.Size="250,18"; $msg.ForeColor="Red"; $f.Controls.Add($msg)
    $ok.Add_Click({
        if ([string]::IsNullOrWhiteSpace($tbA.Text) -or [string]::IsNullOrWhiteSpace($tbP.Text)) {
            $msg.Text = "Account and password required!"
        } else {
            $global:vault += @{account=$tbA.Text; password=$tbP.Text}
            Save-Vault
            $f.Close()
            $vaultList.Items.Add("$($tbA.Text) - ******")
        }
        $tbP.Text = ""; $tbA.Text = ""
    })
    $f.ShowDialog()
})

# --- Edit entry
$editBtn.Add_Click({
    if ($vaultList.SelectedIndex -ge 0) {
        $entry = $global:vault[$vaultList.SelectedIndex]
        $f = New-Object Windows.Forms.Form
        $f.Text = "Edit Entry"
        $f.Size = '310,220'
        $f.FormBorderStyle = 'FixedDialog'
        $f.StartPosition = "CenterScreen"
        $lblA = New-Object Windows.Forms.Label; $lblA.Text="Account:"; $lblA.Location="18,15"; $lblA.Size="80,18"; $f.Controls.Add($lblA)
        $tbA = New-Object Windows.Forms.TextBox; $tbA.Location="110,13"; $tbA.Size="160,22"; $tbA.Text=$entry.account; $f.Controls.Add($tbA)
        $lblP = New-Object Windows.Forms.Label; $lblP.Text="Password:"; $lblP.Location="18,45"; $lblP.Size="80,18"; $f.Controls.Add($lblP)
        $tbP = New-Object Windows.Forms.TextBox; $tbP.Location="110,43"; $tbP.Size="160,22"; $tbP.Text=$entry.password; $tbP.UseSystemPasswordChar=$true; $f.Controls.Add($tbP)
        $ok = New-Object Windows.Forms.Button; $ok.Text="OK"; $ok.Location="100,110"; $ok.Size="100,28"; Style-Button $ok; $f.Controls.Add($ok)
        $msg = New-Object Windows.Forms.Label; $msg.Location="18,85"; $msg.Size="250,18"; $msg.ForeColor="Red"; $f.Controls.Add($msg)
        $ok.Add_Click({
            if ([string]::IsNullOrWhiteSpace($tbA.Text) -or [string]::IsNullOrWhiteSpace($tbP.Text)) {
                $msg.Text = "Account and password required!"
            } else {
                $global:vault[$vaultList.SelectedIndex] = @{account=$tbA.Text; password=$tbP.Text}
                Save-Vault
                $f.Close()
                $vaultList.Items[$vaultList.SelectedIndex] = "$($tbA.Text) - ******"
            }
            $tbP.Text = ""; $tbA.Text = ""
        })
        $f.ShowDialog()
    }
})

# --- Delete entry
$delBtn.Add_Click({
    if ($vaultList.SelectedIndex -ge 0) {
        if ([System.Windows.Forms.MessageBox]::Show("Delete this entry?","Confirm",[System.Windows.Forms.MessageBoxButtons]::YesNo) -eq "Yes") {
            $global:vault = $global:vault | Where-Object { $_ -ne $global:vault[$vaultList.SelectedIndex] }
            Save-Vault
            $vaultList.Items.RemoveAt($vaultList.SelectedIndex)
        }
    }
})

# --- Show password (require master password)
$showBtn.Add_Click({
    if ($vaultList.SelectedIndex -ge 0) {
        $f = New-Object Windows.Forms.Form
        $f.Text = "Show Password"
        $f.Size = '290,130'
        $f.FormBorderStyle = 'FixedDialog'
        $f.StartPosition = "CenterScreen"
        $lbl = New-Object Windows.Forms.Label
        $lbl.Text = "Re-enter master password:"
        $lbl.Location = "15,15"
        $lbl.Size = "200,20"
        $f.Controls.Add($lbl)
        $tb = New-Object Windows.Forms.TextBox
        $tb.Location = "15,45"
        $tb.Size = "230,22"
        $tb.UseSystemPasswordChar = $true
        $f.Controls.Add($tb)
        $okBtn = New-Object Windows.Forms.Button
        $okBtn.Text = "OK"
        $okBtn.Location = "70,80"
        $okBtn.Size = "70,28"
        Style-Button $okBtn
        $f.Controls.Add($okBtn)
        $err = New-Object Windows.Forms.Label
        $err.Location = "15,70"
        $err.Size = "200,20"
        $err.ForeColor = "Red"
        $f.Controls.Add($err)
        $okBtn.Add_Click({
            if ($tb.Text -eq $global:master) {
                $entry = $global:vault[$vaultList.SelectedIndex]
                [System.Windows.Forms.MessageBox]::Show("Password: $($entry.password)")
                $tb.Text = ""
                $f.Close()
            } else {
                $err.Text = "Wrong master password."
            }
        })
        $f.ShowDialog()
    }
})

# --- Copy to clipboard (require master password)
$clipBtn.Add_Click({
    if ($vaultList.SelectedIndex -ge 0) {
        $f = New-Object Windows.Forms.Form
        $f.Text = "Copy Password"
        $f.Size = '290,130'
        $f.FormBorderStyle = 'FixedDialog'
        $f.StartPosition = "CenterScreen"
        $lbl = New-Object Windows.Forms.Label
        $lbl.Text = "Re-enter master password:"
        $lbl.Location = "15,15"
        $lbl.Size = "200,20"
        $f.Controls.Add($lbl)
        $tb = New-Object Windows.Forms.TextBox
        $tb.Location = "15,45"
        $tb.Size = "230,22"
        $tb.UseSystemPasswordChar = $true
        $f.Controls.Add($tb)
        $okBtn = New-Object Windows.Forms.Button
        $okBtn.Text = "OK"
        $okBtn.Location = "70,80"
        $okBtn.Size = "70,28"
        Style-Button $okBtn
        $f.Controls.Add($okBtn)
        $err = New-Object Windows.Forms.Label
        $err.Location = "15,70"
        $err.Size = "200,20"
        $err.ForeColor = "Red"
        $f.Controls.Add($err)
        $okBtn.Add_Click({
            if ($tb.Text -eq $global:master) {
                $entry = $global:vault[$vaultList.SelectedIndex]
                [System.Windows.Forms.Clipboard]::SetText($entry.password)
                [System.Windows.Forms.MessageBox]::Show("Password copied. Will be cleared from clipboard in 20 seconds.")
                Start-Sleep -Seconds 20
                if ([System.Windows.Forms.Clipboard]::GetText() -eq $entry.password) {
                    [System.Windows.Forms.Clipboard]::Clear()
                }
                $tb.Text = ""
                $f.Close()
            } else {
                $err.Text = "Wrong master password."
            }
        })
        $f.ShowDialog()
    }
})

# --- Lock Vault
$lockBtn.Add_Click({
    Set-Unlocked $false
    $vaultList.Items.Clear()
    $global:master = $null
    $lastActivity = [datetime]::Now
})

# --- Destroy Vault
$destroyBtn.Add_Click({
    if ([System.Windows.Forms.MessageBox]::Show("Destroy vault? This cannot be undone!", "Danger", [System.Windows.Forms.MessageBoxButtons]::YesNo) -eq "Yes") {
        Overwrite-And-DeleteFile $global:vaultFile
        $vaultList.Items.Clear()
        $vault = @()
        Set-Unlocked $false
        $global:master = $null
        [System.Windows.Forms.MessageBox]::Show("Vault securely deleted.")
    }
})

# --- Selection enables edit/delete/show/copy
$vaultList.Add_SelectedIndexChanged({
    $sel = ($vaultList.SelectedIndex -ge 0)
    $editBtn.Enabled = $sel
    $delBtn.Enabled = $sel
    $showBtn.Enabled = $sel
    $clipBtn.Enabled = $sel
})

# --- Auto lock after 2 minutes of inactivity
$timer = New-Object Windows.Forms.Timer
$timer.Interval = 20000
$timer.Add_Tick({
    if ($global:unlocked -and ([datetime]::Now - $lastActivity).TotalMinutes -gt 2) {
        Set-Unlocked $false
        $vaultList.Items.Clear()
        $global:master = $null
        [System.Windows.Forms.MessageBox]::Show("Vault auto-locked after inactivity.")
    }
})
$timer.Start()

$form.Add_MouseMove({ $global:lastActivity = [datetime]::Now })
$form.Add_KeyPress({ $global:lastActivity = [datetime]::Now })

# --- First launch logic
if (-Not (Test-Path $vaultFile)) {
    Show-Welcome
    Save-Vault
}
else {
    if (-not (Prompt-Master)) {
        [System.Windows.Forms.MessageBox]::Show("Could not unlock vault. Exiting.")
        $form.Close()
        exit
    }
    $vaultList.Items.Clear()
    foreach ($entry in $vault) {
        $vaultList.Items.Add("$($entry.account) - ******")
    }
    Set-Unlocked $true
}

[void]$form.ShowDialog()
