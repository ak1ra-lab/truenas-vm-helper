#! /bin/bash

codename="$1"

case "$codename" in
bullseye|bookworm|jammy)
    pushd $codename
    genisoimage -output ${codename}.iso -input-charset utf8 -volid cidata -joliet -rock user-data meta-data

    scp ${codename}.iso nas:/mnt/apps/vm/cloud-init/seed/ && rm -f ${codename}.iso
    scp create-vm.sh images.json nas:/mnt/apps/vm/cloud-init/
    popd
    ;;
*)
    exit 1
    ;;
esac
