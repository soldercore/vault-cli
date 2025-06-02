# SecureVault (PowerShell GUI Password Manager)

**SecureVault** is an offline password manager for Windows, with a user-friendly graphical interface. All passwords are stored locally, encrypted using AES-256 with PBKDF2 key derivation, and protected by your master password. No files or data ever leave your computer.

## 🚀 How to run

Just paste this command into PowerShell (**no installation needed**):

```powershell
irm https://raw.githubusercontent.com/soldercore/vault-cli/main/vault.ps1 | iex
