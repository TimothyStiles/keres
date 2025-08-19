Talos makes it easy to slap together a bunch of computers and virtual machines into a working kubernetes cluster IF every node is running talos linux.

I'd guess that for 97% of Talos' enterprise customers this works just fine for them. However, I'm not an enterprise customer. I have two windows machines that triple as machine learning rigs, workstations, and over-glorified xboxs which have plenty of compute to spare which I'd like to add to my cluster while still being able to use them as desktop computers.

Talos makes this really hard. Throw on top of it Windows and Windows Sub Linux networking weirdness and needing a linux kernel that supports ISCSI to support longhorn storage this makes it REALLY hard to add a Windows node to your kubernetes cluster.

And yet it has been done...

![Kubernetes Nodes](resources/images/kube-get-nodes-wide.png)

I'm going to assume you already have windows sub linux 2 (wsl2) running ubuntu successfully installed. For this demo I'm using Ubuntu 24.04.3 LTS with a custom compiled kernel that we'll be compiling so we can support iscsi, longhorn, and nvme storage.


## Table of Contents

- [Creating a Bridge Network](#creating-a-bridge-network)
- [Compiling a Custom Kernel](#compile-custom-kernel)
- [Attaching our Bridge Network and Custom Kernel using wslconfig](#attach-bridge-network-and-custom-kernel-using-wslconfig)
- [Installing Docker Desktop as DockerDesktop](#install-docker-desktop-as-dockerdesktop)
- [Install kubead, kubectl, talosctl](#install-kubead-kubectl-talosctl)
- [Copy talos config to new machine](#copy-talos-config-to-new-machine)
- [Run join script with talos config to pull needed configs and credentials](#run-join-script-with-talos-config-to-pull-needed-configs-and-credentials)
- [Troubleshoot CNI](#troubleshoot-cni)
- [Restart Kubelet and connect to cluster](#restart-kubelet-and-connect-to-cluster)
- [Reinstall vscode and codeserver if remotely connecting to code server](#reinstall-vscode-and-codeserver-if-remotely-connecting-to-code-server)

## Creating a Bridge Network

This feature is being deprecated in WSL2 but it's the only networking mode that won't constantly shoot you in the foot when running kubernetes.

The default network settings create a little personal network for WSL2 within windows that cannot access your local area network. This means you'll have to open every port you'll need on BOTH the Windows host operating system and the WSL2 system PLUS port forward them from the Windows host to WSL2. This is messy and will not play nice with almost everything

Using a mirrored network is suggested by WSL2 but this will play terribly with the container network interface and will still require you to open ports on BOTH windows and WSL2 plus break a bunch of docker desktop and vscode remote container related stuff.

Thus we're going to use a bridge network. This network will bridge our WSL2 instance through the windows host straight onto the lan with it's own proper ip address. This won't mess up any other networked services and will let you open ports only on WSL2.

If you haven't already install hyper-v. Open it up. On the top bar there will be an action tab. Click that and choose `virtual switch manager` and from there set up a virtual switch called lan with these settings.

![Bridge Network Hyper-V](resources/images/bridge-network-hyperv.png)

You can also do this with powershell while running as administrator

If you haven't enabled hyper-v already, enable it, it may ask you to restart to enable:

```
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All
```

If you don't know your NetAdapterName
```
New-VMSwitch -Name "lan" -NetAdapterName (Get-NetAdapter | Where-Object {$_.Status -eq "Up" -and $_.ConnectorPresent -eq $true -and $_.PhysicalMediaType -eq 14} | Select-Object -First 1 -ExpandProperty Name) -AllowManagementOS $true
```

If you do know your NetAdapterName
```
New-VMSwitch -Name "lan" -NetAdapterName "Ethernet" -AllowManagementOS $true
```


## Compiling Your Own WSL2 Kernel

Remember that screenshot where I showed all the nodes in my kubernetes cluster?

![Kubernetes Nodes](resources/images/kube-get-nodes-wide.png)

If you look closely you'll notice that it lists the kernel each node uses and they're all talos except for the one running windows. `6.6.87.2-microsoft-standard-WSL2+` to be exact.

That little `+` means that the kernel was compiled and added by hand. This is how we include iscsi for attached network storage and native nvme support for WSL2.

Don't worry too much about the specifics since I've automated this for us with a script and configs we'll apply in the next section.