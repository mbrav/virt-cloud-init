#!/bin/bash

script_version="0.5.0"

# Script debug for outputting commands
# Set by running:
# $ export SCRIPT_DEBUG=true
if [[ -n $SCRIPT_DEBUG ]]; then
	set -x
fi

# COLORS
ncolors=$(command -v tput >/dev/null && tput colors) # supports color
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
	[[ -n "$2" ]] && exit "$2"
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
	echo -e "./virt-cloud-init.sh [download|prepare|create|regenerate-cloud-init|all] [-h] [-n|o|m|s|c|net|img|u|i|b] [ARG]"
	echo
	echo -e "${YELLOW}COMMANDS${CLEAR}"
	echo -e "download               Download iso"
	echo -e "prepare                Prepare image and cloud-init iso"
	echo -e "create                 Create VM with cloud-init iso (optionally can run)"
	echo -e "regenerate-cloud-init  Cleans VM disk off cloud-init, regenerates the iso"
	echo -e "all                    Run All commands above consecutively"
	echo
	echo -e "${YELLOW}OPTIONS${CLEAR}"
	echo -e "-h --help           Print this Help."
	echo -e "-n --name           Specify VM and image name prefix. Default: $vm_name"
	echo -e "-o --os             Specify OS variant. Default: $os_variant"
	echo -e "-m --memory         Specify VM memory (in MiB). Default: $vm_memory"
	echo -e "-s --storage        Specify VM images size (in K|M|G). Default: $vm_storage"
	echo -e "-c --cpus           Specify CPU numbers. Default: $vm_vcpus"
	echo -e "-net --network      Specify Network name for VM. Default: $network_name"
	echo -e "-img --image-index  Specify a known config listed in images.ini. By default asks dynamically."
	echo -e "-u --url            Specify custom url to an .qcow2 image. Default: $os_url"
	echo -e "-i --interactive    Flag to attaching console upon VM start (also boots the VM)."
	echo -e "-b --boot           Flag for booting VM after creation."
	echo
}

function choose_images() {
	# If an image index is not passed from command line
	if [ -z "${1}" ]; then
		while [ -z "$prompt_done" ]; do
			for i in "${!image_list[@]}"; do
				#os_info="${image_list[i]}"
				#os_info=($os_info)
				os_info=(${image_list[i]})
				echo "${YELLOW}${i}) ${CYAN}${os_info[0]} ${GREY}${os_info[2]##*/}"
			done

			echo "${GREEN}Please select and image (${YELLOW}0-${#image_list[@]}${GREEN}): ${RED}"

			read -r selected_image

			[ "$selected_image" -ge 0 ] 2>/dev/null && prompt_done=true || error_msg "Option must be an integer"
		done

		# Update image index
		img_index=$selected_image
	else
		os_info=(${image_list[${img_index}]})
	fi

	# Set image info based on $img_index
	set_os_info

	success_msg "$os_variant $image_name selected"
}

# Run command
download_iso() {

	if ! command -v wget >/dev/null; then
		error_msg "Wget not installed! Please install" 1
	fi

	mkdir -pv ./downloads

	info_msg "Downloading $image_name ..."

	if [ ! -f "./downloads/$image_name" ]; then
		wget $os_url -O "./downloads/$image_name"
		[ -f "./downloads/$image_name" ] && success_msg "Image downloaded" || error_msg "Image failed to download" 1
	else
		success_msg "Image $image_name already downloaded"
	fi
}

generate_cloud_init_disk() {
	if ! command -v cloud-localds >/dev/null; then
		error_msg "cloud-localds is not installed! Please install 'cloud-image-utils'" 1
	fi

	mkdir -pv cloud
	info_msg "Generating cloudinit yml file"
	[ -f "cloud/$vm_name-init.yml" ] && warning_msg "Overwriting cloud/$vm_name-init.yml file"
	cp -f cloud-init.yml cloud/$vm_name-init.yml

	info_msg "Replacing hostname with $vm_name in cloud/$vm_name-init.yml"
	sed -i "s/hostname:.*/hostname: $vm_name/" cloud/$vm_name-init.yml

	info_msg "Generating cloudinit image"
	sudo cloud-localds cloud/$vm_name-init.img cloud/$vm_name-init.yml
}

regenerate_cloud_init_disk() {
	if ! command -v cloud-localds >/dev/null; then
		error_msg "virt-customize is not installed! Please install 'libguestfs-tools'" 1
	fi

	virt-customize -a disk/debarm-disk.qcow2 --run-command "cloud-init clean"

	generate_cloud_init_disk
}

prepare_iso() {

	if ! command -v qemu-img >/dev/null; then
		error_msg "qemu-img not installed! Please install" 1
	fi

	mkdir -pv disk

	generate_cloud_init_disk

	echo -e "$CYAN----SOURCE IMAGE INFO----$YELLOW"
	qemu-img info "downloads/$image_name"
	echo -e "$CLEAR"

	# Convert image extension to raw when .img
	[ "$image_extension" = img ] && image_extension=raw

	info_msg "Converting image to .qcow2"
	sudo qemu-img convert \
		-f $image_extension \
		-O qcow2 \
		"downloads/$image_name" \
		"disk/$vm_name-disk.qcow2"

	info_msg "Resizing image"
	sudo qemu-img resize "disk/$vm_name-disk.qcow2" "${vm_storage}"

	echo -e "$CYAN----CLOUD INIT IMAGE INFO----$YELLOW"
	qemu-img info cloud/$vm_name-init.img
	echo -e "$CLEAR"

	echo -e "$CYAN----DISK IMAGE INFO----$YELLOW"
	qemu-img info "disk/$vm_name-disk.qcow2"
	echo -e "$CLEAR"
}

create_vm() {
	if ! command -v virt-install >/dev/null; then
		error_msg "virt-install not installed! Please install" 1
	fi

	info_msg "Creating vm"

	sudo virt-install \
		--noreboot \
		--autoconsole "${option_attach_console}" \
		--install no_install="${option_do_not_boot}" \
		--name "${vm_name}" \
		--os-variant "${os_variant}" \
		--connect qemu:///system \
		--virt-type kvm \
		--memory "${vm_memory}" \
		--vcpus "${vm_vcpus}" \
		--boot hd,menu=on \
		--disk "disk/$vm_name-disk.qcow2,device=disk,bus=virtio" \
		--disk "cloud/$vm_name-init.img,device=disk,bus=virtio" \
		--network network="$network_name",model=virtio \
		--graphics none \
		--console pty,target_type="$os_serial"
}

set_os_info() {
	# Set os_info based on $img_index
	os_info=(${image_list[$img_index]})
	os_variant=${os_info[0]}
	os_serial=${os_info[1]}
	os_url=${os_info[2]}
	image_name=${os_url##*/}
	image_extension=${image_name##*.}
}

# Import image list
source ./images.ini

# Use debian11 by default
img_index=''

# Set image info
set_os_info

# VM creation default values
vm_name='default-vm'
network_name='default'
vm_memory='2048'
vm_storage='16G'
vm_vcpus='2'

# No interaction by default
option_attach_console='none'

# Do not start VM by default
option_do_not_boot='yes'

# Run all procedures by default
script_command='all'

# ARG parser
if [ $# -eq 0 ]; then
	# If no arguments, display help
	help
else
	while [ $# -gt 0 ]; do
		case $1 in
		--help | -h)
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
		create)
			script_command=create
			shift # shift argument
			;;
		regenerate-cloud-init)
			script_command=regenerate-cloud-init
			shift # shift argument
			;;
		all)
			script_command=all
			shift # shift argument
			;;
		--name | -n)
			vm_name="$2"
			shift # shift argument
			shift # shift value
			;;
		--image-index | -img)
			img_index="$2"
			shift # shift flag
			shift # shift value
			;;
		--os | -o)
			os_variant="$2"
			shift # shift argument
			shift # shift value
			;;
		--url | -u)
			os_url="$2"
			shift # shift argument
			shift # shift value
			;;
		--memory | -m)
			vm_memory="$2"
			shift # shift argument
			shift # shift value
			;;
		--storage | -s)
			vm_storage="$2"
			shift # shift argument
			shift # shift value
			;;
		--cpus | -c)
			vm_vcpus="$2"
			shift # shift argument
			shift # shift value
			;;
		--network | -net)
			network_name="$2"
			shift # shift argument
			shift # shift value
			;;
		--interactive | -i)
			option_attach_console='text'
			option_do_not_boot='no'
			shift # shift flag
			;;
		--boot | -b)
			option_do_not_boot='no'
			shift # shift flag
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

# Run image chooser by default
choose_images "${img_index}"

# Run Command parser
case $script_command in
download)
	download_iso
	;;
prepare)
	download_iso
	prepare_iso
	;;
create)
	create_vm
	;;
regenerate-cloud-init)
	regenerate_cloud_init_disk
	;;
all)
	download_iso
	prepare_iso
	create_vm
	;;
*)
	error_msg "Unknown command to run: $script_command"
	echo 'Please see list of commands that you can run in help'
	exit 1
	;;
esac
