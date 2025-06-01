# Ultra-secure PowerShell Vault CLI v0.4
$vaultFile = "$PSScriptRoot\vault.secure"
$saltFile = "$PSScriptRoot\vault.salt"

function Derive-Key($password, $salt) {
    $pbkdf2 = New-Object System.Security.Cryptography.Rfc2898DeriveBytes($password, $salt, 200000)
    return $pbkdf2.GetBytes(32)
}

function Encrypt-Vault($vault, $key) {
    if ($null -eq $vault) {
        throw "Vault is null. Nothing to encrypt."
    }

    $json = ConvertTo-Json $vault -Depth 5
    if ([string]::IsNullOrWhiteSpace($json)) {
        throw "Vault JSON is empty or invalid."
    }

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)

    $aes = [System.Security.Cryptography.Aes]::Create()
    $aes.KeySize = 256
    $aes.Mode = "CBC"
    $aes.Padding = "PKCS7"
    $aes.Key = $key
    $aes.GenerateIV()

    $encryptor = $aes.CreateEncryptor()
    $cipher = $encryptor.TransformFinalBlock($bytes, 0, $bytes.Length)

    $combined = New-Object byte[] ($aes.IV.Length + $cipher.Length)
    [Array]::Copy($aes.IV, 0, $combined, 0, $aes.IV.Length)
    [Array]::Copy($cipher, 0, $combined, $aes.IV.Length, $cipher.Length)
    return $combined
}

function Decrypt-Vault($data, $key) {
    $iv = $data[0..15]
    $cipher = $data[16..($data.Length - 1)]

    $aes = [System.Security.Cryptography.Aes]::Create()
    $aes.KeySize = 256
    $aes.Mode = "CBC"
    $aes.Padding = "PKCS7"
    $aes.Key = $key
    $aes.IV = $iv

    $decryptor = $aes.CreateDecryptor()
    $plain = $decryptor.TransformFinalBlock($cipher, 0, $cipher.Length)

    $json = [System.Text.Encoding]::UTF8.GetString($plain)
    return ConvertFrom-Json $json
}

function Prompt-MasterPassword {
    Read-Host "Enter master password" -AsSecureString | ConvertFrom-SecureString -AsPlainText
}

function Menu {
    Clear-Host
    Write-Host "🔐 Vault CLI - PowerShell Edition"
    Write-Host "[1] Add Entry"
    Write-Host "[2] Show Entries"
    Write-Host "[3] Delete Entry"
    Write-Host "[4] Lock and Exit"
}

# Load or generate salt
if (-not (Test-Path $saltFile)) {
    $salt = New-Object byte[] 16
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($salt)
    [System.IO.File]::WriteAllBytes($saltFile, $salt)
} else {
    $salt = [System.IO.File]::ReadAllBytes($saltFile)
}

# Prompt for master password until it's not empty
do {
    $master = Prompt-MasterPassword
    if ([string]::IsNullOrWhiteSpace($master)) {
        Write-Host "Master password cannot be empty. Try again."
    }
} while ([string]::IsNullOrWhiteSpace($master))

# Derive key and check validity
$key = Derive-Key $master $salt
if ($null -eq $key -or $key.Length -ne 32) {
    Write-Error "❌ Failed to derive a valid encryption key. Exiting."
    exit
}

# Load vault
$vault = @()
if (Test-Path $vaultFile) {
    try {
        $data = [System.IO.File]::ReadAllBytes($vaultFile)
        $vault = Decrypt-Vault $data $key
    } catch {
        Write-Error "❌ Wrong password or corrupted vault."
        exit
    }
}

# Menu loop
do {
    Menu
    $choice = Read-Host "Select"

    switch ($choice) {
        "1" {
            $account = Read-Host "Account name"
            $password = Read-Host "Password"
            $vault += @{account = $account; password = $password}
        }
        "2" {
            if ($vault.Count -eq 0) {
                Write-Host "📭 Vault is empty."
            } else {
                $i = 1
                foreach ($entry in $vault) {
                    Write-Host "[$i] $($entry.account) - $($entry.password)"
                    $i++
                }
            }
        }
        "3" {
            if ($vault.Count -eq 0) {
                Write-Host "📭 Vault is empty. Nothing to delete."
            } else {
                $index = Read-Host "Entry number to delete"
                if ($index -match '^\d+$' -and $index -le $vault.Count) {
                    $vault.RemoveAt($index - 1)
                    Write-Host "🗑️ Entry deleted."
                } else {
                    Write-Host "❌ Invalid number."
                }
            }
        }
    }
} while ($choice -ne "4")

# Save vault
try {
    $data = Encrypt-Vault $vault $key
    [System.IO.File]::WriteAllBytes($vaultFile, $data)
    Write-Host "🔒 Vault saved and locked."
} catch {
    Write-Error "❌ Failed to save vault: $_"
}

Write-Host ""
Read-Host "Press ENTER to exit"
