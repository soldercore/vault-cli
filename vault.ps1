Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Security

# --- Fargevalg
$bgColor = [Drawing.Color]::FromArgb(36,36,48)
$fgColor = [Drawing.Color]::FromArgb(240,240,240)
$btnColor = [Drawing.Color]::FromArgb(0,209,160)
$dangerColor = [Drawing.Color]::FromArgb(220,38,38)

# --- Kryptering
function Derive-Key($password, $salt) {
    $deriveBytes = New-Object Security.Cryptography.Rfc2898DeriveBytes($password, $salt, 200000)
    return $deriveBytes.GetBytes(32)
}
function Encrypt-Data($plainText, $key, $iv) {
    if ([string]::IsNullOrWhiteSpace($plainText)) { return $null }
    $aes = [Security.Cryptography.Aes]::Create()
    $aes.Key = $key; $aes.IV = $iv
    $enc = $aes.CreateEncryptor()
    $bytes = [Text.Encoding]::UTF8.GetBytes($plainText)
    $enc.TransformFinalBlock($bytes, 0, $bytes.Length) | % {
        [Convert]::ToBase64String($_)
    }
}
function Decrypt-Data($cipherText, $key, $iv) {
    if ([string]::IsNullOrWhiteSpace($cipherText)) { return "[]" }
    $aes = [Security.Cryptography.Aes]::Create()
    $aes.Key = $key; $aes.IV = $iv
    $dec = $aes.CreateDecryptor()
    $bytes = [Convert]::FromBase64String($cipherText)
    [Text.Encoding]::UTF8.GetString($dec.TransformFinalBlock($bytes, 0, $bytes.Length))
}

# --- Stiler
function Style-Button($b, $danger=$false) {
    $b.FlatStyle = 'Flat'
    $b.BackColor = $danger ? $dangerColor : $btnColor
    $b.ForeColor = $fgColor
    $b.Font = New-Object Drawing.Font('Segoe UI',10,[Drawing.FontStyle]::Bold)
    $b.FlatAppearance.BorderSize = 0
}
function Style-Label($l) {
    $l.ForeColor = $fgColor
    $l.Font = New-Object Drawing.Font('Segoe UI',10)
}

# --- Setup Master Password (med styrke og vis/skjul)
function Show-Setup {
    $f = New-Object Windows.Forms.Form
    $f.Text = "Set Master Password"
    $f.Size = '360,220'
    $f.BackColor = $bgColor
    $f.StartPosition = 'CenterScreen'
    $f.FormBorderStyle = 'FixedDialog'

    $lbl = New-Object Windows.Forms.Label
    $lbl.Text = "Create a strong master password:"
    $lbl.Location = '15,15'; $lbl.Size = '300,20'
    Style-Label $lbl
    $f.Controls.Add($lbl)

    $tb1 = New-Object Windows.Forms.TextBox
    $tb1.Location = '15,45'; $tb1.Size = '300,22'
    $tb1.UseSystemPasswordChar = $true
    $f.Controls.Add($tb1)

    $tb2 = New-Object Windows.Forms.TextBox
    $tb2.Location = '15,75'; $tb2.Size = '300,22'
    $tb2.UseSystemPasswordChar = $true
    $f.Controls.Add($tb2)

    $strength = New-Object Windows.Forms.Label
    $strength.Location = '15,105'; $strength.Size = '300,20'
    $strength.ForeColor = 'Yellow'
    $f.Controls.Add($strength)

    $showCheck = New-Object Windows.Forms.CheckBox
    $showCheck.Text = "Show Password"
    $showCheck.Location = '15,130'; $showCheck.ForeColor = $fgColor
    $f.Controls.Add($showCheck)

    $okBtn = New-Object Windows.Forms.Button
    $okBtn.Text = "Continue"
    $okBtn.Location = '200,160'; $okBtn.Size = '100,30'
    Style-Button $okBtn
    $f.Controls.Add($okBtn)

    $error = New-Object Windows.Forms.Label
    $error.Location = '15,160'; $error.Size = '170,30'
    $error.ForeColor = 'Red'
    $f.Controls.Add($error)

    $showCheck.Add_CheckedChanged({
        $tb1.UseSystemPasswordChar = -not $showCheck.Checked
        $tb2.UseSystemPasswordChar = -not $showCheck.Checked
    })

    $tb1.Add_TextChanged({
        $pw = $tb1.Text
        $score = 0
        if ($pw.Length -ge 12) { $score++ }
        if ($pw -match "[A-Z]") { $score++ }
        if ($pw -match "[a-z]") { $score++ }
        if ($pw -match "\d") { $score++ }
        if ($pw -match "[^A-Za-z0-9]") { $score++ }
        $strength.Text = "Strength: " + @("Weak","Fair","Good","Strong","Excellent")[$score]
        $strength.ForeColor = @('Red','Orange','Gold','Lime','Green')[$score]
    })

    $success = $false
    $okBtn.Add_Click({
        if ($tb1.Text.Length -lt 12) {
            $error.Text = "Minimum 12 characters."
        } elseif ($tb1.Text -ne $tb2.Text) {
            $error.Text = "Passwords do not match."
        } else {
            $global:master = $tb1.Text
            [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes([ref]$global:salt = [byte[]]::new(16))
            [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes([ref]$global:iv = [byte[]]::new(16))
            $f.Close()
            $global:setupComplete = $true
        }
    })

    $f.ShowDialog()
}

# --- Eksempel på bruk
$global:vaultFile = "$env:APPDATA\SecureVault\vault.dat"
$global:master = $null
$global:salt = $null
$global:iv = $null
$global:setupComplete = $false

if (-not (Test-Path $vaultFile)) {
    Show-Setup
    if ($global:setupComplete) {
        $json = "[]" # tom vault
        $key = Derive-Key $global:master $global:salt
        $enc = Encrypt-Data $json $key $global:iv
        $bytes = $global:salt + $global:iv + [Convert]::FromBase64String($enc)
        [IO.File]::WriteAllBytes($vaultFile, $bytes)
        [System.Windows.Forms.MessageBox]::Show("Vault created and saved.")
    } else {
        [System.Windows.Forms.MessageBox]::Show("Setup cancelled.")
    }
} else {
    [System.Windows.Forms.MessageBox]::Show("Vault file already exists.")
}
