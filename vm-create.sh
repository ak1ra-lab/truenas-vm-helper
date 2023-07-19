#! /bin/bash
# author: ak1ra
# date: 2023-07-18
# Helper script to create VM on TrueNAS SCALE using cloud-init with Debian/Ubuntu cloud images
# Thanks-To: https://blog.robertorosario.com/setting-up-a-vm-on-truenas-scale-using-cloud-init/

function prepare_vm_zvol() {
    zfs create -V 10GiB "${VM_ZVOL#/dev/zvol/}"
    dd if=${VM_IMAGE} of=${VM_ZVOL} bs=128M
}

function vm_create() {
    # Create the VM
    midclt call vm.create '{"name": "'${VM_NAME}'", "cpu_mode": "HOST-MODEL", "bootloader": "UEFI", "vcpus": 1, "cores": 1, "threads": 1, "memory": 1024, "autostart": false, "shutdown_timeout": 30}' | tee ${VM_NAME}.json

    if [ $? -ne 0 ]; then
        exit 1
    fi
    local VM_ID=$(head --lines=1 ${VM_NAME}.json | jq '.id')

    # Add the CDROM
    midclt call vm.device.create '{"vm": '${VM_ID}', "dtype": "CDROM", "order": 1000, "attributes": {"path": "'${VM_SEED}'"}}' | tee --append ${VM_NAME}.json

    # Add the DISK
    midclt call vm.device.create '{"vm": '${VM_ID}', "dtype": "DISK", "order": 1001, "attributes": {"path": "'${VM_ZVOL}'", "type": "VIRTIO"}}' | tee --append ${VM_NAME}.json

    # Add the DISPLAY
    midclt call vm.device.create '{"vm": '${VM_ID}', "dtype": "DISPLAY", "order": 1002, "attributes": {"web": true, "type": "VNC", "bind": "0.0.0.0", "wait": false}}' | tee --append ${VM_NAME}.json

    # Add the NIC
    # Obtain a random MAC address
    local MAC_ADDRESS=$(midclt call vm.random_mac)
    midclt call vm.device.create '{"vm": '${VM_ID}', "dtype": "NIC", "order": 1003, "attributes": {"type": "VIRTIO", "nic_attach": "enp35s0", "mac": "'${MAC_ADDRESS}'"}}' | tee --append ${VM_NAME}.json
}

function main() {
    local VM_IMAGE_LIST=($(find ${VM_IMAGE_DIR} -type f -name '*.raw' | grep -vE 'genericcloud|nocloud' | sort))

    local VM_IMAGE=""
    while [ true ]; do
        for idx in ${!VM_IMAGE_LIST[@]}; do
            printf "%3d | %s\n" "$((idx))" "${VM_IMAGE_LIST[idx]#${VM_IMAGE_DIR}/}"
        done

        read -p "Please select VM_IMAGE (q to quit): " choice
        if [ "$choice" == "q" ] || [ "$choice" == "quit" ]; then
            exit 0
        fi
        echo $choice | grep -qE '[0-9][0-9]?'
        if [ $? -eq 0 ]; then
            VM_IMAGE="${VM_IMAGE_LIST[$((choice))]}"
            break
        fi
    done

    local VM_SEED="$(readlink -f $(dirname ${VM_IMAGE})/../../seed.iso)"
    test -f "${VM_SEED}" || exit 1

    local VM_NAME=""
    local VM_NAME_SUFFIX=$(echo $(basename ${VM_IMAGE%.raw}) | sed -E -e 's/[.-]+/_/g')
    while [ true ]; do
        read -p "Please input VM_NAME (q to quit): " VM_NAME_INPUT
        if [ "$VM_NAME_INPUT" == "q" ] || [ "$VM_NAME_INPUT" == "quit" ]; then
            exit 0
        fi
        if echo "${VM_NAME_INPUT}" | grep -qE '[a-z0-9_]+'; then
            VM_NAME="${VM_NAME_INPUT}_${VM_NAME_SUFFIX}"
            break
        else
            echo "VM_NAME can only be combination of letters, numbers and underscores."
        fi
    done

    local VM_ZVOL="/dev/zvol/${VM_ZVOL_DIR}/${VM_NAME}"
    if [ -b "${VM_ZVOL}" ]; then
        echo "ZVOL: ${VM_ZVOL} already exist, exit..."
        exit 1
    fi

    prepare_vm_zvol
    vm_create
}

VM_ZVOL_DIR=apps/vm
VM_IMAGE_DIR=/mnt/apps/vm/images

main $@
