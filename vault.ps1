# Simple PowerShell Password Vault (step 1)
function Menu {
    Clear-Host
    Write-Host "🔐 SIMPLE VAULT - PowerShell Edition"
    Write-Host "[1] Add Entry"
    Write-Host "[2] Show Entries"
    Write-Host "[3] Exit"
}

# Prompt for a master password (not used for anything yet)
do {
    $master = Read-Host "Set a master password"
    if ([string]::IsNullOrWhiteSpace($master)) {
        Write-Host "Master password cannot be empty. Try again."
    }
} while ([string]::IsNullOrWhiteSpace($master))

$vault = @()

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
                Write-Host "No entries saved yet."
            } else {
                $i = 1
                foreach ($entry in $vault) {
                    Write-Host "[$i] $($entry.account) - $($entry.password)"
                    $i++
                }
            }
        }
    }
} while ($choice -ne "3")

Write-Host ""
Read-Host "Press ENTER to exit"
