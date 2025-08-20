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
BOOTSTRAP_TOKEN=$(echo "$JOIN_CMD" | awk -F'--token ' '{print $2}' | awk '{print $1}')
echo "Bootstrap token: $BOOTSTRAP_TOKEN"


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
sudo sed -i "/server:/ s|:.*|: https://${VIP}:6443|g" \
  /etc/kubernetes/kubelet.conf \
  /etc/kubernetes/bootstrap-kubelet.conf

# Retrieve clusterDomain and clusterDNS from kubeletconfig using control plane IP
clusterDomain=$(talosctl -n "$CONTROL_PLANE_IP" get kubeletconfig -o jsonpath="{.spec.clusterDomain}")
clusterDNS=$(talosctl -n "$CONTROL_PLANE_IP" get kubeletconfig -o jsonpath="{.spec.clusterDNS}")
echo "clusterDomain: $clusterDomain"
echo "clusterDNS: $clusterDNS"


cat > /var/lib/kubelet/config.yaml <<EOT
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
authentication:
  anonymous:
    enabled: false
  webhook:
    enabled: true
  x509:
    clientCAFile: /etc/kubernetes/pki/ca.crt
authorization:
  mode: Webhook
clusterDomain: "$clusterDomain"
clusterDNS: $clusterDNS
runtimeRequestTimeout: "0s"
cgroupDriver: systemd # uhhhh might want to update this for anything else
EOT

# check to see if var/lib/kubelet/config.yaml exists
if [[ -f /var/lib/kubelet/config.yaml ]]; then
  echo "/var/lib/kubelet/config.yaml exists."
else
  echo "/var/lib/kubelet/config.yaml does not exist."
fi

# Write kubelet drop-in config to /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
sudo tee /etc/systemd/system/kubelet.service.d/10-kubeadm.conf > /dev/null <<'EOF'
# /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
# Note: This dropin only works with kubeadm and kubelet v1.11+
[Service]
Environment="KUBELET_KUBECONFIG_ARGS=--bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubeconfig --kubeconfig=/etc/kubernetes/kubeconfig-kubelet --container-runtime=remote --container-runtime-endpoint=unix:///var/run/crio/crio.sock --runtime-request-timeout=10m --cgroup-driver=systemd"
Environment="KUBELET_CONFIG_ARGS=--config=/etc/kubernetes/kubelet.yaml"
# This is a file that "kubeadm init" and "kubeadm join" generates at runtime, populating the KUBELET_KUBEADM_ARGS variable dynamically
#EnvironmentFile=-/var/lib/kubelet/kubeadm-flags.env
# This is a file that the user can use for overrides of the kubelet args as a last resort. Preferably, the user should use
# the .NodeRegistration.KubeletExtraArgs object in the configuration files instead. KUBELET_EXTRA_ARGS should be sourced from this file.
EnvironmentFile=-/etc/default/kubelet
ExecStart=
ExecStart=/usr/bin/kubelet $KUBELET_KUBECONFIG_ARGS $KUBELET_CONFIG_ARGS $KUBELET_KUBEADM_ARGS $KUBELET_EXTRA_ARGS

EOF

## reload system to see if changes take effect
systemctl daemon-reload