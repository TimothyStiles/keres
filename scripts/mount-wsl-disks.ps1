# Get current user info dynamically
$user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$scriptPath = $MyInvocation.MyCommand.Path

# Scheduled task name
$taskName = "wsl mount disks"

# Drive config file path (same directory as script)
$driveConfigPath = [System.IO.Path]::Combine((Split-Path $scriptPath), "wsl-drives.config")

# If config file doesn't exist, prompt user for input and create it
if (-not (Test-Path $driveConfigPath)) {
    $driveList = Read-Host "Enter PhysicalDrive numbers to mount (whitespace separated, e.g. 1 2 3)"
    Write-Host "Config will be saved to: $driveConfigPath"
    Set-Content -Path $driveConfigPath -Value $driveList
    Write-Host "Drive config saved to $driveConfigPath"
} else {
    $driveList = Get-Content $driveConfigPath | Out-String
}

# Convert input to array of integers
$drives = $driveList -split '\s+' | Where-Object { $_ -match '^\d+$' }

# Check if the scheduled task already exists
$taskExists = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

# If the task does not exist, create it
if ($null -eq $taskExists) {
    Write-Host "Scheduled task '$taskName' not found. Creating it now..."
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-File `"$scriptPath`""
    $trigger = New-ScheduledTaskTrigger -AtLogon
    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal
} else {
    # Log to console if it doesn't exist
    Write-Host "Scheduled task '$taskName' already exists. Skipping creation."
}

# Check if WSL is running by looking for VmmemWSL process
$wslRunning = Get-Process -Name "VmmemWSL" -ErrorAction SilentlyContinue

if (-not $wslRunning) {
    Write-Host "WSL is not running. Starting WSL..."
    wsl echo "WSL started"
} else {
    Write-Host "WSL is already running. Mounting Disks."
}

# Mount each specified disk
foreach ($drive in $drives) {
    Write-Host "Mounting \\.\PhysicalDrive$drive"
    wsl --mount "\\.\PhysicalDrive$drive" --type ext4
}