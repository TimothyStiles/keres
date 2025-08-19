# Teardown script for mount-wsl-disks.ps1

# Get script path and config path
$scriptPath = $MyInvocation.MyCommand.Path
$driveConfigPath = [System.IO.Path]::Combine((Split-Path $scriptPath), "wsl-drives.config")

# Scheduled task name
$taskName = "wsl mount disks"

# Remove the scheduled task if it exists
$taskExists = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($taskExists) {
    Write-Host "Removing scheduled task '$taskName'..."
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
} else {
    Write-Host "Scheduled task '$taskName' does not exist."
}

# Unmount disks listed in config file
if (Test-Path $driveConfigPath) {
    $driveList = Get-Content $driveConfigPath | Out-String
    $drives = $driveList -split '\s+' | Where-Object { $_ -match '^\d+$' }
    foreach ($drive in $drives) {
        Write-Host "Unmounting \\.\PhysicalDrive$drive from WSL..."
        wsl --unmount "\\.\PhysicalDrive$drive"
    }
    # Remove config file
    Remove-Item $driveConfigPath -Force
    Write-Host "Removed drive config file: $driveConfigPath"
} else {
    Write-Host "Drive config file not found: $driveConfigPath"
}