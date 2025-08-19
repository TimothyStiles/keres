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