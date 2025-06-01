# vault.ps1 - download and run the Vault CLI executable
$vaultUrl = "https://github.com/soldercore/vault-cli/releases/latest/download/vault-cli.exe"
$vaultPath = "$env:TEMP\vault-cli.exe"

Write-Host "🔐 Downloading ultra-secure Vault CLI..."
Invoke-WebRequest -Uri $vaultUrl -OutFile $vaultPath

Write-Host "✅ Download complete. Launching Vault..."
Start-Process -FilePath $vaultPath -Wait
