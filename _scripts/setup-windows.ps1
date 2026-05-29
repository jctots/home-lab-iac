# Setup script for 3etn-net-iac on Windows
# Installs: SOPS, age
# Run from an elevated PowerShell prompt if winget requires it

winget install --id Mozilla.SOPS --silent --accept-package-agreements --accept-source-agreements
winget install --id FiloSottile.age --silent --accept-package-agreements --accept-source-agreements

Write-Host ""
Write-Host "Installed: sops, age"
Write-Host "Next: generate an age key with 'age-keygen -o key.txt', store it securely."
