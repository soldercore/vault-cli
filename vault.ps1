Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Security

function Derive-Key($password, $salt) {
    $deriveBytes = New-Object System.Security.Cryptography.Rfc2898DeriveBytes($password, $salt, 100000)
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

# GUI Setup
$form = New-Object Windows.Forms.Form
$form.Text = "🔐 Secure Vault"
$form.Size = New-Object Drawing.Size(400,400)
$form.StartPosition = "CenterScreen"

$label = New-Object Windows.Forms.Label
$label.Text = "Enter Master Password:"
$label.Location = New-Object Drawing.Point(10,20)
$label.Size = New-Object Drawing.Size(200,20)
$form.Controls.Add($label)

$infoLabel = New-Object Windows.Forms.Label
$infoLabel.Text = "Vault is locked."
$infoLabel.Location = New-Object Drawing.Point(220,20)
$infoLabel.Size = New-Object Drawing.Size(160,20)
$infoLabel.ForeColor = 'Red'
$form.Controls.Add($infoLabel)

$masterBox = New-Object Windows.Forms.TextBox
$masterBox.Location = New-Object Drawing.Point(10,45)
$masterBox.Size = New-Object Drawing.Size(360,20)
$masterBox.UseSystemPasswordChar = $true
$form.Controls.Add($masterBox)

$loginButton = New-Object Windows.Forms.Button
$loginButton.Text = "Unlock Vault"
$loginButton.Location = New-Object Drawing.Point(10,75)
$form.Controls.Add($loginButton)

$vaultList = New-Object Windows.Forms.ListBox
$vaultList.Location = New-Object Drawing.Point(10,110)
$vaultList.Size = New-Object Drawing.Size(360,150)
$vaultList.Enabled = $false
$form.Controls.Add($vaultList)

$accountBox = New-Object Windows.Forms.TextBox
$accountBox.PlaceholderText = "Account"
$accountBox.Location = New-Object Drawing.Point(10,270)
$accountBox.Size = New-Object Drawing.Size(170,20)
$accountBox.Enabled = $false
$form.Controls.Add($accountBox)

$passwordBox = New-Object Windows.Forms.TextBox
$passwordBox.PlaceholderText = "Password"
$passwordBox.Location = New-Object Drawing.Point(200,270)
$passwordBox.Size = New-Object Drawing.Size(170,20)
$passwordBox.UseSystemPasswordChar = $true
$passwordBox.Enabled = $false
$form.Controls.Add($passwordBox)

$addButton = New-Object Windows.Forms.Button
$addButton.Text = "Add Entry"
$addButton.Location = New-Object Drawing.Point(10,300)
$addButton.Enabled = $false
$form.Controls.Add($addButton)

$changeButton = New-Object Windows.Forms.Button
$changeButton.Text = "Change Master Password"
$changeButton.Location = New-Object Drawing.Point(200,300)
$changeButton.Enabled = $false
$form.Controls.Add($changeButton)

$showButton = New-Object Windows.Forms.Button
$showButton.Text = "Show Password"
$showButton.Location = New-Object Drawing.Point(10,330)
$showButton.Enabled = $false
$form.Controls.Add($showButton)

$resetButton = New-Object Windows.Forms.Button
$resetButton.Text = "Reset Vault"
$resetButton.Location = New-Object Drawing.Point(200,330)
$form.Controls.Add($resetButton)

# Vault logic
$vaultFile = "$env:APPDATA\SecureVault\vault.dat"
$vault = @()
$salt = [byte[]]::new(16)
$iv = [byte[]]::new(16)

function Enable-VaultUI($state) {
    $vaultList.Enabled = $state
    $accountBox.Enabled = $state
    $passwordBox.Enabled = $state
    $addButton.Enabled = $state
    $changeButton.Enabled = $state
    $showButton.Enabled = $state
    if ($state) {
        $infoLabel.Text = "Vault is unlocked."
        $infoLabel.ForeColor = 'Green'
    } else {
        $infoLabel.Text = "Vault is locked."
        $infoLabel.ForeColor = 'Red'
    }
}

if (-not (Test-Path "$env:APPDATA\SecureVault")) {
    New-Item -ItemType Directory -Path "$env:APPDATA\SecureVault" | Out-Null
}

if (-Not (Test-Path $vaultFile)) {
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($salt)
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($iv)
} else {
    try {
        $fileBytes = [System.IO.File]::ReadAllBytes($vaultFile)
        $salt = $fileBytes[0..15]
        $iv = $fileBytes[16..31]
        $encrypted = $fileBytes[32..($fileBytes.Length-1)]
        $data = [System.Convert]::ToBase64String($encrypted)
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Error reading vault file.")
    }
}

$loginButton.Add_Click({
    $key = Derive-Key $masterBox.Text $salt
    if (Test-Path $vaultFile) {
        try {
            $fileBytes = [System.IO.File]::ReadAllBytes($vaultFile)
            $salt = $fileBytes[0..15]
            $iv = $fileBytes[16..31]
            $encrypted = $fileBytes[32..($fileBytes.Length-1)]
            $data = [System.Convert]::ToBase64String($encrypted)
            $json = Decrypt-Data $data $key $iv
            $vault = ConvertFrom-Json $json
            $vaultList.Items.Clear()
            foreach ($entry in $vault) {
                $vaultList.Items.Add("$($entry.account) - ******")
            }
            Enable-VaultUI $true
            $masterBox.Text = ""
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Wrong password or corrupted file.")
            Enable-VaultUI $false
            $vaultList.Items.Clear()
            $masterBox.Text = ""
        }
    } else {
        # Ny vault
        $vault = @()
        Enable-VaultUI $true
        $masterBox.Text = ""
    }
})

$addButton.Add_Click({
    if (-not [string]::IsNullOrWhiteSpace($accountBox.Text) -and -not [string]::IsNullOrWhiteSpace($passwordBox.Text)) {
        $entry = @{
            account = $accountBox.Text
            password = $passwordBox.Text
        }
        $vault += $entry
        $vaultList.Items.Add("$($entry.account) - ******")
        $json = $vault | ConvertTo-Json -Compress
        $key = Derive-Key $masterBox.Text $salt
        $encrypted = Encrypt-Data $json $key $iv
        $vaultData = $salt + $iv + [System.Convert]::FromBase64String($encrypted)
        try {
            [System.IO.File]::WriteAllBytes($vaultFile, $vaultData)
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Error writing to vault file.")
        }
        $accountBox.Text = ""
        $passwordBox.Text = ""
    } else {
        [System.Windows.Forms.MessageBox]::Show("Account and Password cannot be empty.")
    }
})

$changeButton.Add_Click({
    $form2 = New-Object Windows.Forms.Form
    $form2.Text = "Change Master Password"
    $form2.Size = New-Object Drawing.Size(250,120)
    $form2.StartPosition = "CenterScreen"
    $box = New-Object Windows.Forms.TextBox
    $box.Location = New-Object Drawing.Point(10,10)
    $box.Size = New-Object Drawing.Size(210,20)
    $box.UseSystemPasswordChar = $true
    $form2.Controls.Add($box)
    $okBtn = New-Object Windows.Forms.Button
    $okBtn.Text = "OK"
    $okBtn.Location = New-Object Drawing.Point(70,40)
    $form2.Controls.Add($okBtn)
    $okBtn.Add_Click({
        $newMaster = $box.Text
        if (-not [string]::IsNullOrWhiteSpace($newMaster)) {
            $key = Derive-Key $newMaster $salt
            $json = $vault | ConvertTo-Json -Compress
            $encrypted = Encrypt-Data $json $key $iv
            $vaultData = $salt + $iv + [System.Convert]::FromBase64String($encrypted)
            try {
                [System.IO.File]::WriteAllBytes($vaultFile, $vaultData)
                [System.Windows.Forms.MessageBox]::Show("Master password changed successfully.")
                $form2.Close()
            } catch {
                [System.Windows.Forms.MessageBox]::Show("Error writing to vault file.")
            }
        }
        $box.Text = ""
    })
    [void]$form2.ShowDialog()
})

$showButton.Add_Click({
    if ($vaultList.SelectedIndex -ge 0) {
        $entry = $vault[$vaultList.SelectedIndex]
        [System.Windows.Forms.MessageBox]::Show("Password: $($entry.password)")
        $entry.password = $null
    } else {
        [System.Windows.Forms.MessageBox]::Show("Select an entry to show the password.")
    }
})

$resetButton.Add_Click({
    if ([System.Windows.Forms.MessageBox]::Show("Are you sure you want to reset the vault?", "Confirm", [System.Windows.Forms.MessageBoxButtons]::YesNo) -eq [System.Windows.Forms.DialogResult]::Yes) {
        try {
            Remove-Item $vaultFile -ErrorAction SilentlyContinue
            $vault = @()
            [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($salt)
            [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($iv)
            $vaultList.Items.Clear()
            Enable-VaultUI $false
            [System.Windows.Forms.MessageBox]::Show("Vault reset successfully.")
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Error resetting vault.")
        }
    }
})

$form.Topmost = $true
$form.Add_Shown({ $form.Activate() })
[void]$form.ShowDialog()
