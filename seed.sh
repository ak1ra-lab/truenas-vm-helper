#! /bin/bash

DISTRO="$1"
REMOTE_DIR="nas:/mnt/apps/vm/images/${DISTRO}/"

case "${DISTRO}" in
debian | ubuntu)
    pushd "${DISTRO}"

    genisoimage -output seed.iso -input-charset utf8 -volid cidata -joliet -rock user-data meta-data

    scp seed.iso "${REMOTE_DIR}" && rm -f ${DISTRO}.iso

    popd
    ;;
*)
    exit 1
    ;;
esac
