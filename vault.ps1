# PowerShell Vault CLI - Secure password manager (v0.1)
$vaultFile = "$PSScriptRoot\vault.secure"

function Derive-Key($password, $salt) {
    $pbkdf2 = New-Object System.Security.Cryptography.Rfc2898DeriveBytes($password, $salt, 200000)
    return $pbkdf2.GetBytes(32)
}

function Encrypt-Vault($vault, $key) {
    $json = ConvertTo-Json $vault -Depth 5
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)

    $aes = [System.Security.Cryptography.Aes]::Create()
    $aes.KeySize = 256
    $aes.Mode = "CBC"
    $aes.Padding = "PKCS7"
    $aes.Key = $key
    $aes.GenerateIV()

    $encryptor = $aes.CreateEncryptor()
    $cipher = $encryptor.TransformFinalBlock($bytes, 0, $bytes.Length)

    return [byte[]]::Concat($aes.IV, $cipher)
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

# Initialize
$vault = @()
$salt = [byte[]]::new(16); [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($salt)
$master = Prompt-MasterPassword
$key = Derive-Key $master $salt

if (Test-Path $vaultFile) {
    try {
        $data = [System.IO.File]::ReadAllBytes($vaultFile)
        $vault = Decrypt-Vault $data $key
    } catch {
        Write-Error "❌ Wrong password or corrupted vault."
        exit
    }
}

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
            $i = 1
            foreach ($entry in $vault) {
                Write-Host "[$i] $($entry.account) - $($entry.password)"
                $i++
            }
        }
        "3" {
            $index = Read-Host "Entry number to delete"
            $vault = $vault | Where-Object { $_ -ne $vault[$index - 1] }
        }
    }
} while ($choice -ne "4")

# Save vault
$data = Encrypt-Vault $vault $key
[System.IO.File]::WriteAllBytes($vaultFile, $data)
Write-Host "🔒 Vault saved and locked."
