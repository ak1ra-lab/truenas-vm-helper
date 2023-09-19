#! /bin/bash
# author: ak1ra
# date: 2023-07-18
# Helper script to create VM on TrueNAS SCALE using cloud-init with Debian/Ubuntu cloud images
# Thanks-To: https://blog.robertorosario.com/setting-up-a-vm-on-truenas-scale-using-cloud-init/

set -o errexit
set -o nounset
set -o pipefail

usage() {
    cat <<EOF

Usage:
    ./vm-create.sh [-h|--help]
    ./vm-create.sh [vm-image-filter]

ENVs:
    You can use some of the ENVs to override the default settings,
    the available ENVs are as follows:

    vm_dataset, vm_location, vm_image_dir,
    add_nic_0, nic_0_name, add_nic_1, nic_1_name

    The default value for these ENVs can be seen at the end of the script

Examples:
    ./vm-create.sh ubuntu
    ./vm-create.sh bookworm

    with ENVs,

    vm_dataset=/mnt/tank ./vm-create.sh ubuntu
    add_nic_0=true nic_0_name=br0 ./vm-create.sh bookworm

EOF
    exit 0
}

check_command() {
    for command in $@; do
        hash "$command" 2>/dev/null || {
            echo >&2 "required command '$command' is not installed, aborting..."
            exit 1
        }
    done
}

find_vm_distro() {
    if echo "${vm_image}" | grep -qE '(debian|bullseye|bookworm|sid)'; then
        local distro=debian
    elif echo "${vm_image}" | grep -qE '(ubuntu|focal|jammy)'; then
        local distro=ubuntu
    else
        local distro=linux
    fi

    echo "$distro"
}

prepare_seed() {
    # TrueNAS SCALE does not have `genisoimage` installed by default
    test -f ${vm_seed} && rm -f ${vm_seed}

    local network_config='{"version": 2, "ethernets": {}}'
    if [ -n "${vm_nic_0_mac}" ]; then
        network_config=$(
            echo $network_config |
                yq '.ethernets += {"nic0": {"dhcp4": "true", "set-name": "nic0", "match": {"macaddress": "'$vm_nic_0_mac'"}}}'
        )
    fi
    if [ -n "${vm_nic_1_mac}" ]; then
        network_config=$(
            echo $network_config |
                yq '.ethernets += {"nic1": {"dhcp4": "true", "set-name": "nic1", "match": {"macaddress": "'$vm_nic_1_mac'"}}}'
        )
    fi

    pushd cloud-init/${vm_distro}
    echo $network_config | yq --prettyPrint . >network-config

    if hash genisoimage; then
        genisoimage -output ${vm_seed} \
            -input-charset utf8 -volid CIDATA -joliet -rock user-data meta-data network-config
    else
        truncate --size 2M ${vm_seed}
        mkfs.vfat -S 4096 -n CIDATA ${vm_seed}

        local mount_dir=$(mktemp -d)
        mount -t vfat ${vm_seed} ${mount_dir}
        cp -v user-data meta-data network-config ${mount_dir}

        umount ${mount_dir}
        rmdir -v ${mount_dir}
    fi
    popd
}

prepare_vm_zvol() {
    zfs create -V 10GiB "${vm_zvol#/dev/zvol/}"
    dd if=${vm_image} of=${vm_zvol} bs=8M
}

vm_create() {
    local vm_config="${vm_dir}/vm.json"

    # create the vm
    midclt call vm.create '{"name": "'${vm_name}'", "cpu_mode": "HOST-MODEL", "bootloader": "UEFI", "vcpus": 1, "cores": 1, "threads": 1, "memory": 1024, "autostart": false, "shutdown_timeout": 30}' | tee ${vm_config}

    if [ $? -ne 0 ]; then
        exit 1
    fi
    local vm_id=$(head --lines=1 ${vm_config} | yq '.id')

    # add the disk
    midclt call vm.device.create '{"vm": '${vm_id}', "dtype": "DISK", "order": 1001, "attributes": {"path": "'${vm_zvol}'", "type": "VIRTIO"}}' | tee --append ${vm_config}

    # add the display
    midclt call vm.device.create '{"vm": '${vm_id}', "dtype": "DISPLAY", "order": 1002, "attributes": {"web": true, "type": "VNC", "bind": "0.0.0.0", "wait": false}}' | tee --append ${vm_config}

    # add the nic
    # obtain a random mac address
    local vm_nic_0_mac=""
    if [ "${add_nic_0}" == "true" ]; then
        vm_nic_0_mac=$(midclt call vm.random_mac)
        midclt call vm.device.create '{"vm": '${vm_id}', "dtype": "NIC", "order": 1003, "attributes": {"type": "VIRTIO", "nic_attach": "'${nic_0_name}'", "mac": "'${vm_nic_0_mac}'"}}' | tee --append ${vm_config}
    fi

    local vm_nic_1_mac=""
    if [ "${add_nic_1}" == "true" ]; then
        vm_nic_1_mac=$(midclt call vm.random_mac)
        midclt call vm.device.create '{"vm": '${vm_id}', "dtype": "NIC", "order": 1004, "attributes": {"type": "VIRTIO", "nic_attach": "'${nic_1_name}'", "mac": "'${vm_nic_1_mac}'"}}' | tee --append ${vm_config}
    fi

    prepare_seed

    # add the cdrom
    midclt call vm.device.create '{"vm": '${vm_id}', "dtype": "CDROM", "order": 1005, "attributes": {"path": "'${vm_seed}'"}}' | tee --append ${vm_config}
}

main() {
    local vm_image_list=(
        $(
            find ${vm_image_dir} -type f -name '*.raw' |
                grep -vE '(genericcloud|nocloud)' | grep -E ''${vm_image_filter}'' | sort
        )
    )

    local vm_image=""
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
            break
        fi
    done

    local vm_name=""
    local vm_name_suffix=$(echo $(basename ${vm_image%.raw}) | sed -E -e 's/[.-]+/_/g')
    while [ true ]; do
        read -p "please input vm_name (q to quit): " vm_name_input
        if [ "$vm_name_input" == "q" ] || [ "$vm_name_input" == "quit" ]; then
            exit 0
        fi
        if echo "${vm_name_input}" | grep -qE '[a-z0-9_]+'; then
            vm_name="${vm_name_input}_${vm_name_suffix}"
            break
        else
            echo "vm_name can only be combination of letters, numbers and underscores."
        fi
    done

    local vm_zvol="/dev/zvol/${vm_dataset}/${vm_name}"
    if [ -b "${vm_zvol}" ]; then
        echo "zvol: ${vm_zvol} already exist, exit..."
        exit 1
    fi

    local vm_dir="${vm_location}/${vm_name}"
    test -d "${vm_dir}" || mkdir -v -p "${vm_dir}"

    local vm_seed="${vm_dir}/seed.iso"
    local vm_distro=$(find_vm_distro)

    prepare_vm_zvol
    vm_create
}

check_command midclt yq zfs

if [ "$#" -gt 0 ]; then
    if [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
        usage
    fi

    vm_image_filter="$1"
else
    vm_image_filter=""
fi

vm_dataset=${vm_dataset:-apps/vm}
vm_location=${vm_location:-/mnt/${vm_dataset}/machines}
vm_image_dir=${vm_image_dir:-/mnt/${vm_dataset}/images}

add_nic_0=${add_nic_0:-true}
nic_0_name=${nic_0_name:-br0}

add_nic_1=${add_nic_1:-false}
nic_1_name=${nic_1_name:-br1}

test -d "${vm_location}" || mkdir -v -p "${vm_location}"
test -d "${vm_image_dir}" || mkdir -v -p "${vm_image_dir}"

main $@
