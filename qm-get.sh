#! /bin/sh

set -o errexit
set -o nounset
set -o pipefail

# import shlib
this=$(readlink -f "$0")
. "$(dirname "$this")"/shlib.sh

usage() {
    cat <<EOF

Usage:
    $(basename $this) [-h|--help]
    $(basename $this) [vm_image_url]

Cloud Images URLs:
    Debian: https://cloud.debian.org/images/cloud/
    Ubuntu: https://cloud-images.ubuntu.com/
    openSUSE: https://download.opensuse.org/repositories/Cloud:/Images:/
    Arch Linux: https://gitlab.archlinux.org/archlinux/arch-boxes
    Amazon Linux 2: https://cdn.amazonlinux.com/os-images/latest/
    CentOS 7: https://cloud.centos.org/centos/7/images/
    FreeBSD: https://download.freebsd.org/ftp/releases/VM-IMAGES/

ENVs:
    You can use some of the ENVs to override the default settings,
    the available ENVs are as follows:

    vm_storage, vm_image_dir

    The default value for these ENVs can be seen at the end of the script

Examples:
    $(basename $this) https://cloud.debian.org/images/cloud/bookworm/20230910-1499/debian-12-genericcloud-amd64-20230910-1499.qcow2

    with ENVs,

    vm_image_dir=/tank/vm/images $(basename $this) https://cloud.debian.org/images/cloud/bookworm/20230910-1499/debian-12-genericcloud-amd64-20230910-1499.qcow2

EOF
    exit 0
}

qm_get() {
    local vm_image_url="$1"
    local vm_image_checksum_url="$2"
    local vm_image=""
    vm_image="${vm_image_dir}/$(echo "$vm_image_url" | sed -E -e 's%^https?://%%')"

    if [ ! -f "$vm_image" ]; then
        wget -c -x -P "$vm_image_dir" "$vm_image_url"
    fi

    if [ -n "$vm_image_checksum_url" ]; then
        local vm_image_checksum_algo="$3"
        local vm_checksum=""
        vm_checksum="${vm_image_dir}/$(echo "$vm_image_checksum_url" | sed -E -e 's%^https?://%%')"

        wget -x -P "$vm_image_dir" "$vm_image_checksum_url"

        eval "hash_${vm_image_checksum_algo}_verify $vm_image $vm_checksum"
    fi

    if echo "$vm_image" | grep -qE '\.(gz|bz2|xz)$'; then
        case "$vm_image" in
        *.gz) gzip -k -d "$vm_image" ;;
        *.bz2) bzip2 -k -d "$vm_image" ;;
        *.xz) xz -k -d "$vm_image" ;;
        *) ;;
        esac
    fi
}

main() {
    local vm_storage=${vm_storage:-apps}
    local vm_image_dir="${vm_image_dir:-/${vm_storage}/vm/images}"
    test -d "$vm_image_dir" || mkdir -p "$vm_image_dir"

    if [ "$#" -gt 0 ]; then
        if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
            usage
        fi
        local vm_image_url="$1"
    else
        local vm_image_url=""
    fi

    if ! echo "$vm_image_url" | grep -qE '^https?://'; then
        log_err "vm_image_url: $vm_image_url not in HTTP format..."
        usage
    fi

    local vm_image_checksum_url=""
    local vm_image_checksum_algo=""

    case "$vm_image_url" in
    *cloud.debian.org*)
        vm_image_checksum_url="${vm_image_url%/*}/SHA512SUMS"
        vm_image_checksum_algo=sha512
        ;;
    *cloud-images.ubuntu.com*)
        vm_image_checksum_url="${vm_image_url%/*}/SHA256SUMS"
        vm_image_checksum_algo=sha256
        ;;
    *download.opensuse.org*)
        vm_image_checksum_url="${vm_image_url}.sha256"
        vm_image_checksum_algo=sha256
        ;;
    *geo.mirror.pkgbuild.com*)
        vm_image_checksum_url="${vm_image_url}.SHA256"
        vm_image_checksum_algo=sha256
        ;;
    *cdn.amazonlinux.com*)
        vm_image_checksum_url="${vm_image_url%/*}/SHA256SUMS"
        vm_image_checksum_algo=sha256
        ;;
    *cloud.centos.org/centos/7/*)
        vm_image_checksum_url="${vm_image_url%/*}/sha256sum.txt"
        vm_image_checksum_algo=sha256
        ;;
    *download.freebsd.org*)
        vm_image_checksum_url="${vm_image_url%/*}/CHECKSUM.SHA512"
        vm_image_checksum_algo=sha512
        ;;
    *) ;;
    esac

    qm_get "$vm_image_url" "$vm_image_checksum_url" "$vm_image_checksum_algo"
}

main "$@"
