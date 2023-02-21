# virt-cloud-init

Script for preparing [cloud](https://github.com/canonical/cloud-init) init images for [virt-manager](https://virt-manager.org/)

## Description

This is a bash script that downloads a cloud init Debian image, resizes it, generates an iso image based on *cloud-init.yml* config, then runs it using virt-manager. Once created, the VM will also be available in your [Virtual Machine Manager](https://virt-manager.org/) GUI.

The script itself is designed to work in the directory where you plan to store iso and images for your VMs. It will create the following directories when all procedures are run:

```text
cloud/
disk/
downloads/
virt-cloud-init.sh
cloud-init.yml
```

- The *cloud/* folder will store all the *.iso* file that were generated based on the *cloud-init.yml* file.
- The *disk/* folder will store disk images of your VMs.
- The *downloads/* folder will store all the downloaded *.qcow2* images.

Currently, the script can be customized using argument flags. Other customization will be added in the future.

Before a run, edit the *cloud-init.yml* file according to your needs. Examples can be found at [cloud inits GitHub repo](https://github.com/canonical/cloud-init/tree/main/doc/examples).

## Script arguments

To view script's instructions, run:

```bash
./virt-cloud-init.sh --help
```

You will get the following text

```text
virt-cloud-init script v0.4.0
ABOUT
Cloud init image preparation tool for virt and virt-manager

SYNTAX
./virt-cloud-init.sh [download|prepare|run|all] [-h] [-n|o|m|s|c|net|u|i] [ARG]

COMMANDS
download            Download iso
prepare             Prepare image and cloud-init iso
run                 Run image with cloud-init iso
all                 Run All commands above consecutively

OPTIONS
-h --help           Print this Help.
-n --name           Specify VM and image name prefix. Default: default-vm
-o --os             Specify OS variant. Default: debian11
-m --memory         Specify VM memory (in MiB). Default: 2048
-s --storage        Specify VM images size (in K|M|G). Default: 16G
-c --cpus           Specify CPU numbers. Default: 2
-net --network      Specify Network name for VM. Default: default
-u --url            Specify custom url to an .qcow2 image. Default: https://cloud.debian.org/images/cloud/bullseye/latest/debian-11-generic-amd64.qcow2
-i --interactive (WIP)  Attach to console upon VM start. Default: false
```

Upon every run, you get the following interactive prompt:

```text
0) debian12 debian-12-genericcloud-amd64-daily.qcow2
1) debian11 debian-11-generic-amd64.qcow2
2) debian10 debian-10-generic-amd64.qcow2
3) ubuntu23.04 lunar-server-cloudimg-amd64.img
4) ubuntu22.04 jammy-server-cloudimg-amd64.img
5) ubuntu20.04 focal-server-cloudimg-amd64.img
6) ubuntu18.04 bionic-server-cloudimg-amd64.img
7) fedora37 Fedora-Cloud-Base-37-1.7.x86_64.qcow2
8) fedora36 Fedora-Cloud-Base-36-1.5.x86_64.qcow2
Please select and image (0-9):
7
[✓] fedora37 Fedora-Cloud-Base-37-1.7.x86_64.qcow2 selected
```

**Note:** Ubuntu support is WIP

## Examples

Download default Debian 11 image:

```bash
./virt-cloud-init.sh download
```

Change VM image name to "my-vm", resize it to 32GB and generate a cloud image iso with config based on `cloud-init.yml`:

```bash
./virt-cloud-init.sh prepare -n my-vm -m 4096 -s 32
```

Start VM with name "my-vm" and give 4096MB of memory

<details>
<summary>ℹ Note about Virtual Machine Manager URI</summary>

By default, libvert uses `qemu:///session` URI, hence, VMs created with `virt-install` will not appear in your Virtual Machine Manager GUI. To fix this issue, export the following variable:

```bash
export LIBVIRT_DEFAULT_URI="qemu:///system"
```

More info on this issue on [StackOverflow](https://stackoverflow.com/questions/35683443/why-are-my-vms-visible-to-either-virsh-virt-manager-but-not-both)

</details>

```bash
./virt-cloud-init.sh run -n my-vm -m 4096
```

Once you run initialize you vm in the output console, press `ctrl + ]` to exit tty.

cd /run/media/mbrav/hd1/iso && ./virt-cloud-init.sh all -m 4096 -c 2 -s 12 -n node1
