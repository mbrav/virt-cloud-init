#!/bin/bash

script_version="0.1.0"

image_urls=(
    "https://cloud.debian.org/images/cloud/buster/latest/debian-10-generic-arm64.qcow2"
    "https://cloud.debian.org/images/cloud/bullseye/latest/debian-11-generic-amd64.qcow2"
    "https://cloud.debian.org/images/cloud/bookworm/daily/latest/debian-12-genericcloud-amd64-daily.qcow2"
)

vm_name=default-vm
os_variant=debian11
network_name=default
vm_memory=2048
vm_storage=16
vm_vcpus=2
img_index=1
url=${image_urls[$img_index]}
image_name=${url##*/}
image_no_ext=${image_name%.*}

# Script debug for outputting commands
# Set by running:
# $ export SCRIPT_DEBUG=true
if [[ -n $SCRIPT_DEBUG ]]; then
    set -x
fi

# COLORS
ncolors=$(command -v tput > /dev/null && tput colors) # supports color
if [[ -n $ncolors && -z $NO_COLOR ]]; then
    TERMCOLS=$(tput cols)
    CLEAR="$(tput sgr0)"

    # 4 bit colors 
    if test $ncolors -ge 8; then 
        # Normal 
        BLACK="$(tput setaf 0)"
        RED="$(tput setaf 1)"
        GREEN="$(tput setaf 2)"
        YELLOW="$(tput setaf 3)"
        BLUE="$(tput setaf 4)"
        MAGENTA="$(tput setaf 5)"
        CYAN="$(tput setaf 6)"
        GREY="$(tput setaf 7)"
    fi

    # >4 bit colors 
    if test $ncolors -gt 8; then 
        # High intensity 
        BLACK_I="$(tput setaf 8)"
        RED_I="$(tput setaf 9)"
        GREEN_I="$(tput setaf 10)"
        YELLOW_I="$(tput setaf 11)"
        BLUE_I="$(tput setaf 12)"
        MAGENTA_I="$(tput setaf 13)"
        CYAN_I="$(tput setaf 14)"
        WHITE="$(tput setaf 15)"
    else
        BLACK_I=$BLACK
        RED_I=$RED
        GREEN_I=$GREEN
        YELLOW_I=$YELLOW
        BLUE_I=$BLUE
        MAGENTA_I=$MAGENTA
        CYAN_I=$CYAN
        WHITE=$GREY
    fi

    # Styles
    UNDERLINE="$(tput smul)"
    STANDOUT="$(tput smso)"
    BOLD="$(tput bold)"
fi

function error_msg() {
    # Error message
    # $1            - Message string argument 
    # $2 (optional) - exit code  
    echo -e "${RED}${BOLD}[X] ${1}${CLEAR}"
    [[ -n $2 ]] && exit $2
}

function warning_msg() {
    echo -e "${YELLOW}${BOLD}[!] ${*}${CLEAR}"
}

function success_msg() {
    echo -e "${GREEN}${BOLD}[✓] ${*}${CLEAR}"
}

function info_msg() {
    echo -e "${CYAN}[i] ${*}${CLEAR}"
}

# Display Help
help() {
    echo -e "${CYAN}${BOLD}virt-cloud-init script v${script_version}${CLEAR}"
    echo -e "${YELLOW}ABOUT${CLEAR}"
    echo -e "Cloud init image preparation tool for virt and virt-manager"
    echo
    echo -e "${YELLOW}SYNTAX${CLEAR}"
    echo -e "./cloud-image.sh [download|prepare|run|all] [-h] [-n|o|m|c|u] [ARG]"
    echo
    echo -e "${YELLOW}COMMANDS${CLEAR}"
    echo -e "download            Download iso"
    echo -e "prepare             Prepare image and cloud-init iso"
    echo -e "run                 Run image with cloud-init iso"
    echo -e "all                 Run All commands above consecutively"
    echo
    echo -e "${YELLOW}OPTIONS${CLEAR}"
    echo -e "-h --help           Print this Help."
    echo -e "-n --name           Specify VM and image name prefix. Default: $vm_name"
    echo -e "-o --os             Specify OS variant. Default: $os_variant"
    echo -e "-m --memory         Specify VM memory. Default: $vm_memory"
    echo -e "-s --storage        Specify VM images size in GB. Default: $vm_storage"
    echo -e "-c --cpus           Specify CPU numbers. Default: $vm_vcpus"
    echo -e "-net --network      Specify Network name for VM. Default: $network_name"
    echo -e "-u --url            Specify custom url to an .qcow2 image. Default: $url"
    echo
}

# Run command
download_iso() {

    if ! command -v wget > /dev/null; then
        error_msg "Wget not installed! Please install" 1
    fi

    mkdir -pv ./downloads

    info_msg "Downloading $image_name ..."

    if [ ! -f "./downloads/$image_name" ]; then
        wget $url -O "./downloads/$image_name"
        [ -f "./downloads/$image_name" ] && success_msg "Image downloaded" || error_msg "Image failed to download" 1
    else
        success_msg "Image $image_name already downloaded"
    fi
}

prepare_iso() {

    if ! command -v qemu-img > /dev/null; then
        error_msg "qemu-img not installed! Please install" 1
    fi

    if ! command -v cloud-localds > /dev/null; then
        error_msg "cloud-localds not installed! Please install" 
    fi

    mkdir -pv ./disk ./cloud

    echo -e "$CYAN----SOURCE IMAGE INFO----$YELLOW"
    qemu-img info "downloads/$image_name"
    echo -e "$CLEAR"

    info_msg "Converting image"
    sudo qemu-img convert \
        -f qcow2 \
        -O qcow2 "downloads/$image_name" \
        "disk/$vm_name-disk.qcow2"

    info_msg "Resizing image"
    sudo qemu-img resize "disk/$vm_name-disk.qcow2" "${vm_storage}G"

    info_msg "Generating cloudinit image"
    sudo cloud-localds cloud/$vm_name-init.img cloud-init.yml


    echo -e "$CYAN----DISK IMAGE INFO----$YELLOW"
    qemu-img info "disk/$vm_name-disk.qcow2"
    echo -e "$CLEAR"

    echo -e "$CYAN----CLOUD INIT IMAGE INFO----$YELLOW"
    qemu-img info cloud/$vm_name-init.img
    echo -e "$CLEAR"
}

run_iso() {

    if ! command -v virt-install > /dev/null; then
        error_msg "virt-install not installed! Please install" 1
    fi

    info_msg "Creating vm"

    sudo virt-install \
        --name $vm_name \
        --os-variant $os_variant \
        --virt-type kvm \
        --memory $vm_memory \
        --vcpus $vm_vcpus \
        --boot hd,menu=on \
        --cdrom "cloud/$vm_name-init.img" \
        --disk "disk/$vm_name-disk.qcow2",device=disk,bus=virtio \
        --boot cdrom \
        --network network="$network_name",model=virtio \
        --graphics none \
        --console pty,target_type=serial
}

# Run all procedures by default
script_command=all

# ARG parser
if [ $# -eq 0 ]; then
    # If no arguments, display help
    help
else
    while [ $# -gt 0 ]; do
        case $1 in
            --help|-h)
                help
                shift # shift argument
                exit 0
            ;;
            download)
                script_command=download
                shift # shift argument
            ;;
            prepare)
                script_command=prepare
                shift # shift argument
            ;;
            run)
                script_command=run
                shift # shift argument
            ;;
            all)
                script_command=all
                shift # shift argument
            ;;
            --name|-n)
                vm_name="$2"
                shift # shift argument
                shift # shift value
            ;;
            --os|-o)
                os_variant="$2"
                shift # shift argument
                shift # shift value
            ;;
            --memory|-m)
                vm_memory="$2"
                shift # shift argument
                shift # shift value
            ;;
            --storage|-s)
                vm_storage="$2"
                shift # shift argument
                shift # shift value
            ;;
            --cpus|-c)
                vm_vcpus="$2"
                shift # shift argument
                shift # shift value
            ;;
            --network|-net)
                network_name="$2"
                shift # shift argument
                shift # shift value
            ;;
            --url|-u)
                url="$2"
                shift # shift argument
                shift # shift value
            ;;
            -*)
                error_msg "Unknown option $1" 22
                exit 1
            ;;
            *)
                error_msg "Unknown argument $1"
                echo 'If you want to pass an argument with spaces'
                echo 'pass the argument like this: "my argument"'
                exit 1
            ;;
        esac
    done
fi

# Run Command parser
case $script_command in
    download)
        download_iso
    ;;
    prepare)
        prepare_iso
    ;;
    run)
        run_iso
    ;;
    all)
        download_iso
        prepare_iso
        run_iso
    ;;
    *)
        error_msg "Unknown command to run: $script_command"
        echo 'Please see list of commands that you can run in help'
        exit 1
    ;;
esac
