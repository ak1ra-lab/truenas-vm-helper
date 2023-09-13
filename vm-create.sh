#! /bin/bash
# author: ak1ra
# date: 2023-07-18
# Helper script to create VM on TrueNAS SCALE using cloud-init with Debian/Ubuntu cloud images
# Thanks-To: https://blog.robertorosario.com/setting-up-a-vm-on-truenas-scale-using-cloud-init/

set -o errexit
set -o nounset
set -o pipefail

function usage() {
    cat <<EOF

Usage:
    ./vm-create.sh [-h|--help]
    ./vm-create.sh [vm-image-filter]

ENVs:
    You can use some of the ENVs to override the default settings,
    the available ENVs are as follows:

    VM_DATASET, VM_LOCATION, VM_IMAGE_DIR,
    ADD_NIC_0, NIC_0_NAME, ADD_NIC_1, NIC_1_NAME

    The default value for these ENVs can be seen at the end of the script

Examples:
    ./vm-create.sh ubuntu
    ./vm-create.sh bookworm

    with ENVs,

    VM_DATASET=/mnt/tank ./vm-create.sh ubuntu
    ADD_NIC_0=true NIC_0_NAME=br0 ./vm-create.sh bookworm

EOF
    exit 0
}

function check_command() {
    for command in $@; do
        hash "$command" 2>/dev/null || {
            echo >&2 "Required command '$command' is not installed, Aborting..."
            exit 1
        }
    done
}

function find_vm_distro() {
    if echo "${VM_IMAGE}" | grep -qE '(debian|bullseye|bookworm|sid)'; then
        local distro=debian
    elif echo "${VM_IMAGE}" | grep -qE '(ubuntu|focal|jammy)'; then
        local distro=ubuntu
    else
        local distro=linux
    fi

    echo "$distro"
}

function prepare_seed() {
    # TrueNAS SCALE does not have `genisoimage` installed by default
    test -f ${VM_SEED} && rm -f ${VM_SEED}

    local network_config='{"version": 2, "ethernets": {}}'
    if [ -n "${VM_NIC_0_MAC}" ]; then
        network_config=$(
            echo $network_config |
                yq '.ethernets += {"nic0": {"dhcp4": "true", "set-name": "nic0", "match": {"macaddress": "'$VM_NIC_0_MAC'"}}}'
        )
    fi
    if [ -n "${VM_NIC_1_MAC}" ]; then
        network_config=$(
            echo $network_config |
                yq '.ethernets += {"nic1": {"dhcp4": "true", "set-name": "nic1", "match": {"macaddress": "'$VM_NIC_1_MAC'"}}}'
        )
    fi

    pushd cloud-init/${VM_DISTRO}
    echo $network_config | yq --prettyPrint . >network-config

    if hash genisoimage; then
        genisoimage -output ${VM_SEED} \
            -input-charset utf8 -volid CIDATA -joliet -rock user-data meta-data network-config
    else
        truncate --size 2M ${VM_SEED}
        mkfs.vfat -S 4096 -n CIDATA ${VM_SEED}

        local mount_dir=$(mktemp -d)
        mount -t vfat ${VM_SEED} ${mount_dir}
        cp -v user-data meta-data network-config ${mount_dir}

        umount ${mount_dir}
        rmdir -v ${mount_dir}
    fi
    popd
}

function prepare_vm_zvol() {
    zfs create -V 10GiB "${VM_ZVOL#/dev/zvol/}"
    dd if=${VM_IMAGE} of=${VM_ZVOL} bs=8M
}

function vm_create() {
    local VM_CONFIG="${VM_DIR}/vm.json"

    # Create the VM
    midclt call vm.create '{"name": "'${VM_NAME}'", "cpu_mode": "HOST-MODEL", "bootloader": "UEFI", "vcpus": 1, "cores": 1, "threads": 1, "memory": 1024, "autostart": false, "shutdown_timeout": 30}' | tee ${VM_CONFIG}

    if [ $? -ne 0 ]; then
        exit 1
    fi
    local VM_ID=$(head --lines=1 ${VM_CONFIG} | yq '.id')

    # Add the DISK
    midclt call vm.device.create '{"vm": '${VM_ID}', "dtype": "DISK", "order": 1001, "attributes": {"path": "'${VM_ZVOL}'", "type": "VIRTIO"}}' | tee --append ${VM_CONFIG}

    # Add the DISPLAY
    midclt call vm.device.create '{"vm": '${VM_ID}', "dtype": "DISPLAY", "order": 1002, "attributes": {"web": true, "type": "VNC", "bind": "0.0.0.0", "wait": false}}' | tee --append ${VM_CONFIG}

    # Add the NIC
    # Obtain a random MAC address
    local VM_NIC_0_MAC=""
    if [ "${ADD_NIC_0}" == "true" ]; then
        VM_NIC_0_MAC=$(midclt call vm.random_mac)
        midclt call vm.device.create '{"vm": '${VM_ID}', "dtype": "NIC", "order": 1003, "attributes": {"type": "VIRTIO", "nic_attach": "'${NIC_0_NAME}'", "mac": "'${VM_NIC_0_MAC}'"}}' | tee --append ${VM_CONFIG}
    fi

    local VM_NIC_1_MAC=""
    if [ "${ADD_NIC_1}" == "true" ]; then
        VM_NIC_1_MAC=$(midclt call vm.random_mac)
        midclt call vm.device.create '{"vm": '${VM_ID}', "dtype": "NIC", "order": 1004, "attributes": {"type": "VIRTIO", "nic_attach": "'${NIC_1_NAME}'", "mac": "'${VM_NIC_1_MAC}'"}}' | tee --append ${VM_CONFIG}
    fi

    prepare_seed

    # Add the CDROM
    midclt call vm.device.create '{"vm": '${VM_ID}', "dtype": "CDROM", "order": 1005, "attributes": {"path": "'${VM_SEED}'"}}' | tee --append ${VM_CONFIG}
}

function main() {
    local VM_IMAGE_LIST=(
        $(
            find ${VM_IMAGE_DIR} -type f -name '*.raw' |
                grep -vE '(genericcloud|nocloud)' | grep -E ''${VM_IMAGE_FILTER}'' | sort
        )
    )

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

    local VM_ZVOL="/dev/zvol/${VM_DATASET}/${VM_NAME}"
    if [ -b "${VM_ZVOL}" ]; then
        echo "ZVOL: ${VM_ZVOL} already exist, exit..."
        exit 1
    fi

    local VM_DIR="${VM_LOCATION}/${VM_NAME}"
    test -d "${VM_DIR}" || mkdir -v -p "${VM_DIR}"

    local VM_SEED="${VM_DIR}/seed.iso"
    local VM_DISTRO=$(find_vm_distro)

    prepare_vm_zvol
    vm_create
}

check_command midclt yq zfs

if [ "$#" -gt 0 ]; then
    if [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
        usage
    fi

    VM_IMAGE_FILTER="$1"
else
    VM_IMAGE_FILTER=""
fi

VM_DATASET=${VM_DATASET:-apps/vm}
VM_LOCATION=${VM_LOCATION:-/mnt/${VM_DATASET}/machines}
VM_IMAGE_DIR=${VM_IMAGE_DIR:-/mnt/${VM_DATASET}/images}

ADD_NIC_0=${ADD_NIC_0:-true}
NIC_0_NAME=${NIC_0_NAME:-br0}

ADD_NIC_1=${ADD_NIC_1:-false}
NIC_1_NAME=${NIC_1_NAME:-br1}

test -d "${VM_LOCATION}" || mkdir -v -p "${VM_LOCATION}"
test -d "${VM_IMAGE_DIR}" || mkdir -v -p "${VM_IMAGE_DIR}"

main $@
