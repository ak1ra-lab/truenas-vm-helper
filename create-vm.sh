#! /bin/bash

function usage() {
    cat <<EOF
Usage:
    ./create-vm.sh <VM_NAME> <VM_IMAGE_REF>

    VM_NAME: only alphanumeric characters are allowed
    VM_IMAGE_REF: jq -r '.images|keys[]' images.json

VM_IMAGE_REF_LIST:
    $(echo $VM_IMAGE_REF_LIST | tr '\n' ' ')

EOF
    exit 1
}

function prepare_vm_zvol() {
    if [ -b "${VM_ZVOL}" ]; then
        echo "ZVOL: ${VM_ZVOL} already exist, exit..."
        exit 1
    fi

    zfs create -V 10GiB "${VM_ZVOL#/dev/zvol/}"
    dd if=${VM_IMAGE} of=${VM_ZVOL} bs=128M
}

function create_vm() {
    # Create the VM
    midclt call vm.create '{"name": "'${VM_NAME}'", "cpu_mode": "HOST-MODEL", "bootloader": "UEFI", "threads": 1, "memory": 1024}' | tee ${VM_NAME}.json

    VM_ID=$(jq '.id' ${VM_NAME}.json)
    test -n "${VM_ID}" || exit 1

    # Add the CDROM
    midclt call vm.device.create '{"vm": '${VM_ID}', "dtype": "CDROM", "order": 1000, "attributes": {"path": "'${VM_SEED}'"}}'

    # Add the DISK
    midclt call vm.device.create '{"vm": '${VM_ID}', "dtype": "DISK", "order": 1001, "attributes": {"path": "'${VM_ZVOL}'", "type": "VIRTIO"}}'

    # Add the DISPLAY
    midclt call vm.device.create '{"vm": '${VM_ID}', "dtype": "DISPLAY", "order": 1002, "attributes": {"web": true, "type": "VNC", "bind": "0.0.0.0", "wait": false}}'

    # Add the NIC
    # Obtain a random MAC address
    MAC_ADDRESS=$(midclt call vm.random_mac)
    midclt call vm.device.create '{"vm": '${VM_ID}', "dtype": "NIC", "order": 1003, "attributes": {"type": "VIRTIO", "nic_attach": "enp35s0", "mac": "'${MAC_ADDRESS}'"}}'
}

function main() {
    VM_IMAGE_REF_LIST=$(jq -r '.images|keys[]' images.json)

    VM_NAME="$1"
    test -n "${VM_NAME}" || usage
    VM_ZVOL="/dev/zvol/apps/vm/${VM_NAME}"

    VM_IMAGE_REF="$2"
    test -n "${VM_IMAGE_REF}" || usage
    if ! echo "${VM_IMAGE_REF_LIST}" | grep -q "${VM_IMAGE_REF}"; then
        echo "VM_IMAGE_REF: $VM_IMAGE_REF not in $VM_IMAGE_REF_LIST, exit..."
        exit 1
    fi

    VM_IMAGE=$(jq -r '.images["'$VM_IMAGE_REF'"].image' images.json)
    VM_SEED="/mnt/apps/vm/cloud-init/seed/${VM_IMAGE_REF}.iso"

    prepare_vm_zvol
    create_vm
}

main $@
