#! /bin/bash
# https://pve.proxmox.com/wiki/Cloud-Init_Support

set -o errexit
set -o nounset
set -o pipefail

# import shlib
this=$(readlink -f "$0")
. "$(dirname "$this")"/shlib.sh
# import .env.sh
dot_env_sh="${this%.sh}.env.sh"
test -f "$dot_env_sh" && . "$dot_env_sh"

usage() {
    cat <<EOF

Usage:
    $(basename $this) [-h|--help]
    $(basename $this) [vm-image-filter]

ENVs:
    You can use some of the ENVs to override the default settings,
    the available ENVs are as follows:

    vm_storage, vm_image_dir

    The default value for these ENVs can be seen at the end of the script

Examples:
    $(basename $this) ubuntu
    $(basename $this) bookworm

    with ENVs,

    vm_storage=apps $(basename $this) ubuntu
    vm_storage=apps vm_image_dir=/apps/vm/images $(basename $this) bookworm

EOF
    exit 0
}

qm_template() {
    # create a new vm with virtio scsi controller
    qm create "$vm_id" --name "$vm_name" --cpu cputype=host --cores 4 --balloon 1024 --memory 16384 --net0 virtio,bridge=vmbr0 --scsihw virtio-scsi-pci

    # import the downloaded disk to the $vm_storage vm_storage (eg: local-lvm), attaching it as a scsi drive
    qm set "$vm_id" --scsi0 ${vm_storage}:0,import-from=${vm_image}

    # add cloud-init cd-rom drive
    qm set "$vm_id" --ide0 ${vm_storage}:cloudinit

    # to be able to boot directly from the cloud-init image, set the boot parameter to order=scsi0 to restrict bios to boot from this disk only.
    qm set "$vm_id" --boot order=scsi0

    # for many cloud-init images, it is required to configure a serial console and use it as a display.
    qm set "$vm_id" --serial0 socket --vga serial0

    # in a last step, it is helpful to convert the vm into a template.
    qm template "$vm_id"
}

main() {
    local vm_image_list=(
        $(
            find ${vm_image_dir} -type f |
                grep -E '\.(qcow2|img)$' | grep -E ''${vm_image_filter}'' | sort
        )
    )

    local vm_image=""
    local vm_name=""
    while [ true ]; do
        for idx in ${!vm_image_list[@]}; do
            printf "%3d | %s\n" "$((idx))" "${vm_image_list[idx]#${vm_image_dir}/}"
        done

        read -p "please select vm_image (q to quit): " choice
        if [ "$choice" == "q" ] || [ "$choice" == "quit" ]; then
            exit 0
        fi
        echo $choice | grep -qE '[0-9][0-9]?'
        if [ $? -eq 0 ]; then
            vm_image="${vm_image_list[$((choice))]}"
            vm_name="$(basename $vm_image | sed -E -e 's%[\._]+%-%g')"
            break
        fi
    done

    local vm_id=""
    local vm_id_input=""
    while [ true ]; do
        read -p "please input vm_id (q to quit): " vm_id_input
        if [ "$vm_id_input" == "q" ] || [ "$vm_id_input" == "quit" ]; then
            exit 0
        fi
        if ! echo "${vm_id_input}" | grep -qE '[1-9][0-9]*'; then
            echo "vm_id can only be numbers."
            continue
        fi

        vm_id="${vm_id_input}"
        if [ ! -f "/etc/pve/qemu-server/${vm_id}.conf" ]; then
            break
        else
            log_warning "vm_id: $vm_id is already in use..."
        fi
    done

    qm_template
}

require_command qm

if [ "$#" -gt 0 ]; then
    if [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
        usage
    fi

    vm_image_filter="$1"
else
    vm_image_filter=""
fi

vm_storage=${vm_storage:-apps}
zfs_mountpoint=${zfs_mountpoint:-/}
vm_image_dir="${vm_image_dir:-${zfs_mountpoint}${vm_storage}/vm/images}"
test -d "$vm_image_dir" || mkdir -p "$vm_image_dir"

main "$@"
