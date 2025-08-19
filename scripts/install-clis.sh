#!/bin/bash
set -e

# Variables
KUBE_VERSION="1.31.11"


# Update the apt package index and install packages needed for Kubernetes apt repository
sudo apt-get update
# apt-transport-https may be a dummy package; if so, you can skip that package
sudo apt-get install -y apt-transport-https ca-certificates curl gnupg

# Create /etc/apt/keyrings if it does not exist
if [ ! -d "/etc/apt/keyrings" ]; then
    sudo mkdir -p -m 755 /etc/apt/keyrings
fi

curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
sudo chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg


# Install Homebrew if missing
if ! command -v brew &> /dev/null; then
    echo "Homebrew not found. Installing Homebrew..."
    NONINTERACTIVE=1 bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    # Add Homebrew to PATH for Linux
    echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"' >> ~/.profile
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi

# Ensure Homebrew's bin is in PATH for this session
export PATH="/home/linuxbrew/.linuxbrew/bin:$PATH"
# Add Homebrew shellenv eval to ~/.bashrc for permanent setup
if ! grep -q 'brew shellenv' ~/.bashrc; then
    echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"' >> ~/.bashrc
fi


brew install siderolabs/tap/talosctl
TALOSCTL_VERSION=$(talosctl version --short 2>/dev/null | head -n1)

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo chmod 644 /etc/apt/sources.list.d/kubernetes.list



# Update apt package index, then install kubectl, kubeadm, and kubelet version 1.31.11
sudo apt-get update
sudo apt-get install -y kubelet=1.31.11-1.1 kubeadm=1.31.11-1.1 kubectl=1.31.11-1.1
sudo apt-mark hold kubelet kubeadm kubectl


echo "Installation complete: kubectl $(kubectl version --client --short | awk '{print $3}'), talosctl ${TALOSCTL_VERSION} (installed via Homebrew)"

# Check if talosctl is installed and in PATH
if command -v talosctl &> /dev/null; then
    echo "talosctl is installed and available in your PATH. Version: $(talosctl version --short 2>/dev/null | head -n1)"
else
    echo "Warning: talosctl is not available in your PATH. Try opening a new shell or ensure /home/linuxbrew/.linuxbrew/bin is in your PATH."
    echo "You can manually run: export PATH=\"/home/linuxbrew/.linuxbrew/bin:\$PATH\""
fi