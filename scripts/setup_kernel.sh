#!/bin/bash

WIN_USER=$(powershell.exe '$env:USERNAME' | tr -d '\r')
echo "Windows username: $WIN_USER"

# Get absolute path to config files relative to script location
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_PATH="$SCRIPT_DIR/../configs/wsl2-kernel-config"
WSLCONFIG_PATH="$SCRIPT_DIR/../configs/.wslconfig"

echo "SCRIPT_DIR: $SCRIPT_DIR"
echo "CONFIG_PATH: $CONFIG_PATH"
echo "WSLCONFIG_PATH: $WSLCONFIG_PATH"


# Generate a unique MAC address and add to .wslconfig
echo "Generating unique MAC address for WSL2..."
MAC_ADDR=$(bash "$SCRIPT_DIR/generate_mac.sh" | grep "Generated MAC:" | awk '{print $3}' | tail -n1)
echo "Generated MAC: $MAC_ADDR"

echo "Running sed to update .wslconfig kernel path with actual Windows username..."
echo "sed -i 's|<insertusernamehere>|$WIN_USER|g' '$WSLCONFIG_PATH'"
sed -i "s|<insertusernamehere>|$WIN_USER|g" "$WSLCONFIG_PATH"

# Add MAC address to .wslconfig
if grep -q '^macAddress=' "$WSLCONFIG_PATH"; then
    sed -i "s|^macAddress=.*|macAddress=$MAC_ADDR|" "$WSLCONFIG_PATH"
else
    echo "macAddress=$MAC_ADDR" >> "$WSLCONFIG_PATH"
fi

echo "Copying .wslconfig to Windows user profile directory..."
cp "$WSLCONFIG_PATH" "/mnt/c/Users/$WIN_USER/.wslconfig"

# Check if .wslconfig was copied
if [ -f "/mnt/c/Users/$WIN_USER/.wslconfig" ]; then
    echo ".wslconfig copied successfully."
else
    echo "Error: .wslconfig was not copied successfully."
    exit 1
fi

# Install required build dependencies
echo "Installing required build dependencies..."
sudo apt-get update && sudo apt-get install -y build-essential flex bison libssl-dev libelf-dev libncurses5-dev git bc pahole

PROJECT_ROOT="$SCRIPT_DIR/.."

# Clone WSL2 kernel repository in project root
cd "$PROJECT_ROOT"
echo "Cloning the WSL2 kernel repository. This may take a while..."
if [ -d "WSL2-Linux-Kernel" ]; then
    echo "WSL2-Linux-Kernel directory already exists. Skipping clone."
else
    git clone --single-branch --depth 1 https://github.com/microsoft/WSL2-Linux-Kernel.git
fi
cd WSL2-Linux-Kernel

# Copying custom kernel config...
echo "Copying custom kernel config..."
cp "$CONFIG_PATH" .config

# Compile the kernel
echo "Compiling the kernel may take a while. Please wait..."
make -j$(nproc)

echo "Copying bzImage to Windows user directory..."
cp arch/x86/boot/bzImage "/mnt/c/Users/$WIN_USER/bzImage"

# Check if both .wslconfig and bzImage were copied
if [ -f "/mnt/c/Users/$WIN_USER/.wslconfig" ] && [ -f "/mnt/c/Users/$WIN_USER/bzImage" ]; then
    echo "\nCongratulations! Your custom WSL2 kernel setup is complete."
    echo "To finish, restart WSL from PowerShell with:"
    echo "    wsl --shutdown"
    echo "Then start WSL again with:"
    echo "    wsl"
    echo "This will load your custom kernel."
else
    echo "\nError: One or both files (.wslconfig or bzImage) were not copied successfully. Please check the script output and try again."
fi
