# Call preflight scripts
& "$PSScriptRoot\PreFlightCheck.ps1"

# Get config
$configPath = "$HOME/.keres/config"
$configJson = Get-Content $configPath -Raw | ConvertFrom-Jsono

# Compile custom kernel then set WSL2 to use it and custom virtual switch we created in pre-flight check
wsl bash "$PSScriptRoot/setup-wsl.sh"

# Install dependencies and clis 
wsl bash "$PSScriptRoot/install-clis.sh"

# Join cluster
wsl bash "$PSScriptRoot/join-cluster.sh"

# Mount WSL disks
wsl bash "$PSScriptRoot/mount-wsl-disks.sh"