#!/bin/bash

WIN_USER=$(powershell.exe '$env:USERNAME' | tr -d '\r')
echo "Windows username: $WIN_USER"

# Update .wslconfig kernel path with actual Windows username
sed -i "s|<insertusernamehere>|$WIN_USER|g" "$(dirname "$0")/../configs/.wslconfig"

# Copy .wslconfig to Windows user profile directory
cp "$(dirname "$0")/../configs/.wslconfig" "/mnt/c/Users/$WIN_USER/.wslconfig"

# Ensure git is installed
if ! command -v git &> /dev/null; then
	echo "git not found, installing..."
	sudo apt-get update && sudo apt-get install -y git
fi


# Clone WSL2 kernel repository
git clone --single-branch --depth 1 https://github.com/microsoft/WSL2-Linux-Kernel.git

# Enter the kernel repo
cd WSL2-Linux-Kernel

echo "Compiling the kernel may take a while. Please wait..."

# Copy custom config
cp "$(dirname "$0")/../configs/wsl2-kernel-config" .config

# Compile the kernel
make -j$(nproc)

# Copy bzImage to Windows user directory
cp arch/x86/boot/bzImage "/mnt/c/Users/$WIN_USER/bzImage"
