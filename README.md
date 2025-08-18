Talos makes it easy to slap together a bunch of computers and virtual machines into a working kubernetes cluster IF every node is running talos linux.

I'd guess that for 97% of Talos' enterprise customers this works just fine for them. However, I'm not an enterprise customer. I have two windows machines that triple as machine learning rigs, workstations, and over-glorified xboxs which have plenty of compute to spare which I'd like to add to my cluster while still being able to use them as desktop computers.

Talos makes this really hard. Throw on top of it Windows and Windows Sub Linux weirdness and needing a linux kernel that supports ISCSI to support longhorn storage this makes it REALLY hard to add a Windows node to your kubernetes cluster.

And yet it has been done...

![Kubernetes Nodes](resources/images/kube-get-nodes.png)



I'm going to assume you already have windows sub linux 2 (wsl2) running ubuntu successfully installed. For this demo I'm using Ubuntu 24.04.3 LTS with a custom compiled kernel that we'll be compiling so we can support iscsi, longhorn, and nvme storage.


Create bridge network
compile custom kernel
attach bridge network and custom kernel using wslconfig
install "Docker Desktop" as "DockerDesktop"
Install kubead, kubectl, talosctl
Move talos config to new machine
Run join script with talos config to pull needed configs and credentials
troubleshoot CNI
Restart Kubelet and connect to cluster
Probably reinstall vscode and codeserver if you're remotely connecting to code server.