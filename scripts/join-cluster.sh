#!/bin/bash

# Check for Talos config
if [ ! -f "$HOME/.talos/config" ]; then
	echo "Talos config not found at ~/.talos/config. Please copy it from your control node or another machine with access."
	echo "Example: scp <user>@<control_node_ip>:~/.talos/config ~/.talos/config"
	exit 1
fi

# Get current Talos context and control plane IP
CURRENT_CONTEXT=$(talosctl config info | awk -F': *' '/Current context:/ {print $2}' | xargs)
CONTROL_PLANE_ENDPOINTS=$(talosctl config info | awk -F': *' '/Endpoints:/ {print $2}' | xargs)
CONTROL_PLANE_IP=$(echo "$CONTROL_PLANE_ENDPOINTS" | awk '{print $1}')


echo "Current Talos context: $CURRENT_CONTEXT"
echo "Control plane IP: $CONTROL_PLANE_IP"

# Extract kubeconfig from talos control plane and set it
if [ -n "$CONTROL_PLANE_IP" ]; then
	echo "Fetching kubeconfig from control plane ($CONTROL_PLANE_IP)..."
	talosctl kubeconfig -e "$CONTROL_PLANE_IP" --force
	export KUBECONFIG="$HOME/.kube/config"
	echo "KUBECONFIG set to $HOME/.kube/config"

	# Detect shell and profile
	if [ -n "$ZSH_VERSION" ]; then
		PROFILE="$HOME/.zshrc"
	elif [ -n "$BASH_VERSION" ]; then
		if [ -f "$HOME/.bash_profile" ]; then
			PROFILE="$HOME/.bash_profile"
		else
			PROFILE="$HOME/.bashrc"
		fi
	else
		# Fallback to .profile if neither bash nor zsh detected
		PROFILE="$HOME/.profile"
	fi

	# Add KUBECONFIG to profile if not already present
	if ! grep -q 'export KUBECONFIG="$HOME/.kube/config"' "$PROFILE"; then
		echo 'export KUBECONFIG="$HOME/.kube/config"' >> "$PROFILE"
		echo "Added KUBECONFIG to $PROFILE"
	fi

	# Source the profile to update current shell
	# shellcheck disable=SC1090
	. "$PROFILE"
	echo "Sourced $PROFILE to update environment."
else
	echo "Could not determine control plane IP. Cannot fetch kubeconfig."
	exit 1
fi

# Create a kubeadm bootstrap token and extract the token value
JOIN_CMD=$(kubeadm token create --print-join-command 2>/dev/null)
echo "$JOIN_CMD"
BOOTSTRAP_TOKEN=$(echo "$JOIN_CMD" | awk -F'--token ' '{print $2}' | awk '{print $1}')
echo "Bootstrap token: $BOOTSTRAP_TOKEN"

# check if bootstrap token is valid
if kubeadm token list | awk '{print $1}' | grep -q "^${BOOTSTRAP_TOKEN}$"; then
	echo "Bootstrap token is valid."
else
	echo "Error: Bootstrap token $BOOTSTRAP_TOKEN is not valid or has expired."
	exit 1
fi

# Create necessary RBAC roles and bindings for bootstrapping
kubectl create clusterrole system:certificates.k8s.io:certificatesigningrequestnodes --verb=create,get,list,watch,approve --resource=certificatesigningrequests.certificates.k8s.io
kubectl create clusterrolebinding kubeadm:kubelet-bootstrap --clusterrole=system:certificates.k8s.io:certificatesigningrequestnodes --group=system:bootstrappers

# Copying /etc/kubernetes from control plane node $CONTROL_PLANE_IP into a temporary directory
echo "Copying /etc/kubernetes from control plane node $CONTROL_PLANE_IP..."
TMP_K8S_DIR=$(mktemp -d)
talosctl -n $CONTROL_PLANE_IP copy /etc/kubernetes - | tar -xz -C "$TMP_K8S_DIR"

# Ensure the required files/folders exist
if [[ -f "$TMP_K8S_DIR/bootstrap-kubeconfig" && -f "$TMP_K8S_DIR/kubelet.yaml" && -f "$TMP_K8S_DIR/pki/ca.crt" ]]; then
	echo "Required files found: bootstrap-kubeconfig, kubelet.yaml, pki/ca.crt"
else
	echo "Error: One or more required files are missing after extraction."
	rm -rf "$TMP_K8S_DIR"
	exit 1
fi

# Create destination directories if needed
sudo mkdir -p /etc/kubernetes/pki

# Copy files to the new node's /etc/kubernetes
sudo cp "$TMP_K8S_DIR/bootstrap-kubeconfig" /etc/kubernetes/
sudo cp "$TMP_K8S_DIR/kubelet.yaml" /etc/kubernetes/
sudo cp "$TMP_K8S_DIR/pki/ca.crt" /etc/kubernetes/pki/

echo "Files copied to /etc/kubernetes/ on this node."

# Clean up temporary directory
rm -rf "$TMP_K8S_DIR"

# Add serverTLSBootstrap: true to kubelet.yaml
sudo sed -i '/^ *kubelet:/a \\ \ \\serverTLSBootstrap: true' /etc/kubernetes/kubelet.yaml
echo "serverTLSBootstrap: true added to /etc/kubernetes/kubelet.yaml."

sudo sed -i "s|token: .*|token: $BOOTSTRAP_TOKEN|" /etc/kubernetes/bootstrap-kubeconfig

# Update or create server addresses in /etc/kubernetes/kubelet.yaml and /etc/kubernetes/bootstrap-kubeconfig
for f in /etc/kubernetes/kubelet.yaml /etc/kubernetes/bootstrap-kubeconfig; do
	if sudo grep -q "^ *server:" "$f"; then
		sudo sed -i "/^ *server:/ s|:.*|: https://${CONTROL_PLANE_IP}:6443|" "$f"
	else
		sudo echo "server: https://${CONTROL_PLANE_IP}:6443" | sudo tee -a "$f"
	fi
done

# Check for kubelet config and handle creation/overwrite
KUBELET_CONF_DIR="/etc/systemd/system/kubelet.service.d"
KUBELET_CONF_FILE="$KUBELET_CONF_DIR/10-kubeadm.conf"

if [ ! -d "$KUBELET_CONF_DIR" ]; then
	echo "Directory $KUBELET_CONF_DIR does not exist. Creating it..."
	sudo mkdir -p "$KUBELET_CONF_DIR"
fi

if [ -f "$KUBELET_CONF_FILE" ]; then
	echo "Warning: $KUBELET_CONF_FILE already exists and will be overwritten."
else
	echo "$KUBELET_CONF_FILE does not exist. It will be created."
fi


# Write kubelet drop-in config to /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
sudo tee /etc/systemd/system/kubelet.service.d/10-kubeadm.conf > /dev/null <<'EOF'
# /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
# Note: This dropin only works with kubeadm and kubelet v1.11+
[Service]
Environment="KUBELET_KUBECONFIG_ARGS=--bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubeconfig --kubeconfig=/etc/kubernetes/kubeconfig-kubelet --cgroup-driver=systemd"
Environment="KUBELET_CONFIG_ARGS=--config=/etc/kubernetes/kubelet.yaml"
# This is a file that "kubeadm init" and "kubeadm join" generates at runtime, populating the KUBELET_KUBEADM_ARGS variable dynamically
#EnvironmentFile=-/var/lib/kubelet/kubeadm-flags.env
# This is a file that the user can use for overrides of the kubelet args as a last resort. Preferably, the user should use
# the .NodeRegistration.KubeletExtraArgs object in the configuration files instead. KUBELET_EXTRA_ARGS should be sourced from this file.
EnvironmentFile=-/etc/default/kubelet
ExecStart=
ExecStart=/usr/bin/kubelet $KUBELET_KUBECONFIG_ARGS $KUBELET_CONFIG_ARGS $KUBELET_KUBEADM_ARGS $KUBELET_EXTRA_ARGS

EOF



# Ensure vm.overcommit_memory=1 is set in /etc/sysctl.conf
if ! grep -q '^vm\.overcommit_memory=1' /etc/sysctl.conf; then
	if grep -q '^vm\.overcommit_memory=' /etc/sysctl.conf; then
		sudo sed -i 's/^vm\.overcommit_memory=.*/vm.overcommit_memory=1/' /etc/sysctl.conf
	else
		echo "vm.overcommit_memory=1" | sudo tee -a /etc/sysctl.conf
	fi
fi

# Ensure kernel.panic=10 is set in /etc/sysctl.conf
if ! grep -q '^kernel\.panic=10' /etc/sysctl.conf; then
	if grep -q '^kernel\.panic=' /etc/sysctl.conf; then
		sudo sed -i 's/^kernel\.panic=.*/kernel.panic=10/' /etc/sysctl.conf
	else
		echo "kernel.panic=10" | sudo tee -a /etc/sysctl.conf
	fi
fi
sudo sysctl -p
## reload system to see if changes take effect
sudo systemctl enable --now containerd
sudo systemctl restart kubelet
sudo systemctl daemon-reload

TOKEN_ID=$(echo "$BOOTSTRAP_TOKEN" | cut -c1-6)
kubectl get csr --no-headers | awk "/system:bootstrap:$TOKEN_ID/"'{print $1}' | xargs -r kubectl certificate approve

# Check for control-plane taint and remove if present (at script end)
NODE_NAME=$(kubectl get node --selector="kubernetes.io/hostname=$(hostname)" -o jsonpath='{.items[0].metadata.name}')
if [ -z "$NODE_NAME" ]; then
	NODE_NAME=$(hostname)
fi
TAINT_PRESENT=$(kubectl get node "$NODE_NAME" -o jsonpath='{.spec.taints}' | grep 'node-role.kubernetes.io/control-plane')
if [ -n "$TAINT_PRESENT" ]; then
	echo "Node $NODE_NAME has the control-plane NoSchedule taint. Removing it so Longhorn and other pods can be scheduled."
	kubectl taint node "$NODE_NAME" node-role.kubernetes.io/control-plane:NoSchedule-
else
	echo "Node $NODE_NAME does not have the control-plane NoSchedule taint."
fi


# Ensure /var/lib/longhorn exists
sudo mkdir -p /var/lib/longhorn
# Bind mount /var/lib/longhorn to itself (required for mount propagation)
sudo mount --bind /var/lib/longhorn /var/lib/longhorn
# Make /var/lib/longhorn a shared mount
sudo mount --make-shared /var/lib/longhorn
echo "/var/lib/longhorn is now a shared mount for Longhorn compatibility."

sudo systemctl restart kubelet