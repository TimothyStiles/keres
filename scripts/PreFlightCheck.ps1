# Keres Pre-flight Check Script
# Run as Administrator

Write-Host "Keres Pre-flight Check"

# 1. Check for WSL
$wslInstalled = Get-Command wsl -ErrorAction SilentlyContinue
if ($wslInstalled) {
    Write-Host "WSL is installed."
} else {
    Write-Warning "WSL is not installed."
    exit 1
}

# 2. Check for WSL2 and Ubuntu 24.04.3 LTS
$wslDistros = wsl -l -v
$found = $false
foreach ($line in $wslDistros) {
    if ($line -match "Ubuntu" -and $line -match "2") {
        $found = $true
        break
    }
}
if ($found) {
    Write-Host "WSL2 with Ubuntu: found."
} else {
    Write-Warning "WSL2 with Ubuntu: not found."
}

$ubuntuVersion = wsl -d Ubuntu cat /etc/os-release
if ($ubuntuVersion -match "24.04") {
    Write-Host "Ubuntu 24.04.x LTS detected in WSL2."
} else {
    Write-Warning "Ubuntu 24.04.x LTS not detected in WSL2."
}

# 3. Check that talos config exists in WSL
$talosConfig = wsl bash -c "test -f ~/.talos/config && echo exists"
if ($talosConfig -eq "exists") {
    Write-Host "Talos config: found in WSL2 Ubuntu."
} else {
    Write-Warning "Talos config: not found in WSL2 Ubuntu."
    Write-Warning "Talos config not found at ~/.talos/config in WSL2 Ubuntu. Please copy it from your control node or another machine with access."
    Write-Host "Example: scp <user>@<control_node_ip>:~/.talos/config ~/.talos/config"
    exit 1
}

# 4. Check for Keres config in Windows for mounting drives
$keresConfig = "$env:USERPROFILE\\.keres"
if (Test-Path $keresConfig) {
    Write-Host "Keres config: found at $keresConfig."
} else {
    Write-Warning "Keres config: not found at $keresConfig. Creating Default Keres Config at $keresConfig."
    . "$PSScriptRoot/KeresConfigTemplate.ps1"  # Import the template (adjust path if needed)
    $keresConfigTemplate | ConvertTo-Json | Set-Content "$env:USERPROFILE\.keres"
}


# 5. Check if Hyper-V is enabled
$hyperv = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V
if ($hyperv.State -eq "Enabled") {
    Write-Host "Hyper-V: enabled."
} else {
    Write-Warning "Hyper-V: not enabled. Run 'Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All' and reboot."
}

# TODO: add install and reboot prompt that creates a task to resume this script after reboot

if ($hyperv.State -ne "Enabled") {
    $installHyperV = Read-Host "Do you want to enable Hyper-V now? (Y/N)"
    if ($installHyperV -eq "Y") {
        Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All
        Write-Host "Hyper-V installation initiated. Please reboot your system."
    }
}

# 6. Get the network name and create a hyper-v managed switch if it doesn't exist or use an already existing one with the Ethernet adapter.

$networkName = $keresConfigTemplate.network.name
$existingSwitch = Get-VMSwitch -Name $networkName -ErrorAction SilentlyContinue

if ($existingSwitch) {
    Write-Host "Found Hyper-V switch with keres network name '$networkName'."
} else {
    # If not found, search for a switch using the Ethernet adapter
    $ethernetSwitch = Get-VMSwitch | Where-Object { $_.NetAdapterInterfaceDescription -match "Ethernet" -and $_.AllowManagementOS }
    if ($ethernetSwitch) {
        $networkName = $ethernetSwitch.Name
        Write-Host "No keres-named switch found. Found existing Hyper-V switch '$networkName' using Ethernet and AllowManagementOS. Updating config."
        $keresConfigTemplate.network.name = $networkName
        $keresConfigTemplate | ConvertTo-Json | Set-Content "$env:USERPROFILE\.keres"
        $existingSwitch = $ethernetSwitch
    } else {
        Write-Warning "No existing Hyper-V switch uses Ethernet with AllowManagementOS. Creating new switch '$networkName'."
        New-VMSwitch -Name $networkName -NetAdapterName Ethernet -AllowManagementOS
        Write-Host "Hyper-V switch '$networkName' created."
        $existingSwitch = Get-VMSwitch -Name $networkName -ErrorAction SilentlyContinue
    }
}

# Get-Disk and prompt user if they want to install any bare drives as ext4 and to specify the numbers. Warn that this is potentially destructive if the drive isn't already wiped and partition free

# List all physical disks

$disks = Get-Disk | Where-Object { $_.PartitionStyle -eq 'RAW' -and $_.OperationalStatus -eq 'Online' }
if ($disks) {
    Write-Host "The following bare drives (no partitions) are detected:"
    $disks | Select-Object Number, FriendlyName, Size | Format-Table
    Write-Warning "NOTE: These drives are currently uninitialized and have no partitions. Recording selected disk numbers in config for later use. No changes will be made to the disks at this time."
    Write-Host "Press Enter without input to skip attaching or configuring any drives. This is the default action."
    $diskNumbers = Read-Host "Enter the disk numbers to record in config for later (comma separated, e.g. 1,2):"
    $selected = $diskNumbers -split ',' | ForEach-Object { $_.Trim() }
    $keresConfigTemplate.bareDisks = $selected
    $keresConfigTemplate | ConvertTo-Json | Set-Content "$env:USERPROFILE\.keres"
    Write-Host "Selected disk numbers recorded in config."
} else {
    Write-Host "No bare drives detected to record in config."
}

# TODO check if DockerDesktop is installed as "Docker Desktop or DockerDesktop" and make sure it is installed as "DockerDesktop"


Write-Host "Pre-flight check complete."