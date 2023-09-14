#! /bin/bash
# https://pve.proxmox.com/wiki/Cloud-Init_Support

# https://cloud.debian.org/images/cloud/bookworm/
VM_IMAGE_BOOKWORM_URL="https://cloud.debian.org/images/cloud/bookworm/20230910-1499/debian-12-genericcloud-amd64-20230910-1499.qcow2"

# https://cloud-images.ubuntu.com/jammy/
VM_IMAGE_JAMMY_URL="https://cloud-images.ubuntu.com/jammy/20230828/jammy-server-cloudimg-amd64.img"

# https://cdn.amazonlinux.com/os-images/latest/
VM_IMAGE_AMAZON_LINUX_2_URL="https://cdn.amazonlinux.com/os-images/2.0.20230906.0/kvm/amzn2-kvm-2.0.20230906.0-x86_64.xfs.gpt.qcow2"

# https://download.opensuse.org/repositories/Cloud:/Images:/
VM_IMAGE_OPENSUSE_LEAP_URL="https://download.opensuse.org/repositories/Cloud:/Images:/Leap_15.5/images/openSUSE-Leap-15.5.x86_64-1.0.0-NoCloud-Build1.79.qcow2"

# https://gitlab.archlinux.org/archlinux/arch-boxes
VM_IMAGE_ARCHLINUX_URL="https://geo.mirror.pkgbuild.com/images/v20230901.175781/Arch-Linux-x86_64-cloudimg-20230901.175781.qcow2"

main() {
    # download the image
    if [ ! -f "$VM_IMAGE" ]; then
        wget -c -P "$VM_IMAGE_DIR" "$VM_IMAGE_URL"
    fi

    # create a new VM with VirtIO SCSI controller
    qm create "$VM_ID" --name "$VM_IMAGE_NAME_FQDN" --memory 1024 --net0 virtio,bridge=vmbr0 --scsihw virtio-scsi-pci

    # import the downloaded disk to the $VM_DISK_STORAGE storage (eg: local-lvm), attaching it as a SCSI drive
    qm set "$VM_ID" --scsi0 ${VM_DISK_STORAGE}:0,import-from=${VM_IMAGE}

    # Add Cloud-Init CD-ROM drive
    qm set "$VM_ID" --ide2 ${VM_DISK_STORAGE}:cloudinit

    # To be able to boot directly from the Cloud-Init image, set the boot parameter to order=scsi0 to restrict BIOS to boot from this disk only.
    qm set "$VM_ID" --boot order=scsi0

    # For many Cloud-Init images, it is required to configure a serial console and use it as a display.
    qm set "$VM_ID" --serial0 socket --vga serial0

    # In a last step, it is helpful to convert the VM into a template.
    qm template "$VM_ID"
}

VM_ID=${VM_ID:-9000}
if [ -f "/etc/pve/qemu-server/${VM_ID}.conf" ]; then
    echo "VM_ID: $VM_ID is already in use..."
    exit 1
fi

VM_DISK_STORAGE=${VM_DISK_STORAGE:-apps}

VM_IMAGES_BASE_DIR="/${VM_DISK_STORAGE}/vm/images"
test -d "$VM_IMAGES_BASE_DIR" || mkdir -p "$VM_IMAGES_BASE_DIR"

VM_IMAGE_URL="${VM_IMAGE_URL:-$VM_IMAGE_BOOKWORM_URL}"
VM_IMAGE_DIR="${VM_IMAGES_BASE_DIR}/$(echo ${VM_IMAGE_URL%/*} | sed -E -e 's%^https?://%%' -e 's%:%%g')"
VM_IMAGE_NAME="${VM_IMAGE_URL##*/}"
VM_IMAGE_NAME_FQDN="$(echo ${VM_IMAGE_NAME%.*} | sed -E -e 's%[\._]%%g')"

VM_IMAGE="${VM_IMAGE_DIR}/${VM_IMAGE_NAME}"

main $@
