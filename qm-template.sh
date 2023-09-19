#! /bin/bash
# https://pve.proxmox.com/wiki/Cloud-Init_Support

# https://cloud.debian.org/images/cloud/bookworm/
vm_image_bookworm_url="https://cloud.debian.org/images/cloud/bookworm/20230910-1499/debian-12-genericcloud-amd64-20230910-1499.qcow2"

# https://cloud-images.ubuntu.com/jammy/
vm_image_jammy_url="https://cloud-images.ubuntu.com/jammy/20230828/jammy-server-cloudimg-amd64.img"

# https://cdn.amazonlinux.com/os-images/latest/
vm_image_amazon_linux_2_url="https://cdn.amazonlinux.com/os-images/2.0.20230906.0/kvm/amzn2-kvm-2.0.20230906.0-x86_64.xfs.gpt.qcow2"

# https://download.opensuse.org/repositories/Cloud:/Images:/
vm_image_opensuse_leap_url="https://download.opensuse.org/repositories/Cloud:/Images:/Leap_15.5/images/openSUSE-Leap-15.5.x86_64-1.0.0-NoCloud-Build1.79.qcow2"

# https://gitlab.archlinux.org/archlinux/arch-boxes
vm_image_archlinux_url="https://geo.mirror.pkgbuild.com/images/v20230901.175781/Arch-Linux-x86_64-cloudimg-20230901.175781.qcow2"

main() {
    # download the image
    if [ ! -f "$vm_image" ]; then
        wget -c -P "$vm_image_dir" "$vm_image_url"
    fi

    # create a new vm with virtio scsi controller
    qm create "$vm_id" --name "$vm_image_name_fqdn" --memory 1024 --net0 virtio,bridge=vmbr0 --scsihw virtio-scsi-pci

    # import the downloaded disk to the $vm_disk_storage storage (eg: local-lvm), attaching it as a scsi drive
    qm set "$vm_id" --scsi0 ${vm_disk_storage}:0,import-from=${vm_image}

    # add cloud-init cd-rom drive
    qm set "$vm_id" --ide2 ${vm_disk_storage}:cloudinit

    # to be able to boot directly from the cloud-init image, set the boot parameter to order=scsi0 to restrict bios to boot from this disk only.
    qm set "$vm_id" --boot order=scsi0

    # for many cloud-init images, it is required to configure a serial console and use it as a display.
    qm set "$vm_id" --serial0 socket --vga serial0

    # in a last step, it is helpful to convert the vm into a template.
    qm template "$vm_id"
}

vm_id=${vm_id:-9000}
if [ -f "/etc/pve/qemu-server/${vm_id}.conf" ]; then
    echo "vm_id: $vm_id is already in use..."
    exit 1
fi

vm_disk_storage=${vm_disk_storage:-apps}

vm_images_base_dir="/${vm_disk_storage}/vm/images"
test -d "$vm_images_base_dir" || mkdir -p "$vm_images_base_dir"

vm_image_url="${vm_image_url:-$vm_image_bookworm_url}"
vm_image_dir="${vm_images_base_dir}/$(echo ${vm_image_url%/*} | sed -E -e 's%^https?://%%' -e 's%:%%g')"
vm_image_name="${vm_image_url##*/}"
vm_image_name_fqdn="$(echo ${vm_image_name%.*} | sed -E -e 's%[\._]%%g')"

vm_image="${vm_image_dir}/${vm_image_name}"

main $@
