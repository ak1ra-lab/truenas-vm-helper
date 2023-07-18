#! /bin/bash
# author: ak1ra
# date: 2023-07-18
# helper script to create vm on TrueNAS SCALE using Debian/Ubuntu cloud images
# ref: https://blog.robertorosario.com/setting-up-a-vm-on-truenas-scale-using-cloud-init/

function usage() {
    cat <<EOF
Usage:
    ./create-vm.sh <VM_NAME>

    VM_NAME can only be letters, numbers and underscores.

EOF
    exit 1
}

function prepare_vm_zvol() {
    zfs create -V 10GiB "${VM_ZVOL#/dev/zvol/}"
    dd if=${VM_IMAGE} of=${VM_ZVOL} bs=128M
}

function create_vm() {
    # Create the VM
    midclt call vm.create '{"name": "'${VM_NAME}'", "cpu_mode": "HOST-MODEL", "bootloader": "UEFI", "vcpus": 1, "cores": 1, "threads": 1, "memory": 1024, "autostart": false, "shutdown_timeout": 30}' | tee ${VM_NAME}.json

    if [ $? -ne 0 ]; then
        exit 1
    fi
    local VM_ID=$(jq '.id' ${VM_NAME}.json)

    # Add the CDROM
    midclt call vm.device.create '{"vm": '${VM_ID}', "dtype": "CDROM", "order": 1000, "attributes": {"path": "'${VM_SEED}'"}}'

    # Add the DISK
    midclt call vm.device.create '{"vm": '${VM_ID}', "dtype": "DISK", "order": 1001, "attributes": {"path": "'${VM_ZVOL}'", "type": "VIRTIO"}}'

    # Add the DISPLAY
    midclt call vm.device.create '{"vm": '${VM_ID}', "dtype": "DISPLAY", "order": 1002, "attributes": {"web": true, "type": "VNC", "bind": "0.0.0.0", "wait": false}}'

    # Add the NIC
    # Obtain a random MAC address
    local MAC_ADDRESS=$(midclt call vm.random_mac)
    midclt call vm.device.create '{"vm": '${VM_ID}', "dtype": "NIC", "order": 1003, "attributes": {"type": "VIRTIO", "nic_attach": "enp35s0", "mac": "'${MAC_ADDRESS}'"}}'
}

function main() {
    local VM_IMAGE_LIST=($(find ${VM_IMAGE_DIR} -type f -name '*.raw' | grep -vE 'genericcloud|nocloud' | sort))

    local VM_NAME="$1"
    test -n "${VM_NAME}" || usage
    if ! echo "${VM_NAME}" | grep -qE '[a-z0-9_]+'; then
        usage
    fi

    local VM_ZVOL="/dev/zvol/${VM_ZVOL_DIR}/${VM_NAME}"
    if [ -b "${VM_ZVOL}" ]; then
        echo "ZVOL: ${VM_ZVOL} already exist, exit..."
        exit 1
    fi

    local VM_IMAGE=""
    while [ true ]; do
        for idx in ${!VM_IMAGE_LIST[@]}; do
            printf "%3d | %s\n" "$((idx))" "${VM_IMAGE_LIST[idx]#${VM_IMAGE_DIR}/}"
        done

        read -p "请根据序号选择要使用的虚拟机镜像: " choice
        echo $choice | egrep -q '[0-9][0-9]?'
        if [ $? -eq 0 ]; then
            VM_IMAGE="${VM_IMAGE_LIST[$((choice))]}"
            break
        fi
    done

    local VM_SEED="$(readlink -f $(dirname ${VM_IMAGE})/../../seed.iso)"
    test -f "${VM_SEED}" || exit 1

    prepare_vm_zvol
    create_vm
}

VM_ZVOL_DIR=apps/vm
VM_IMAGE_DIR=/mnt/apps/vm/images

main $@
