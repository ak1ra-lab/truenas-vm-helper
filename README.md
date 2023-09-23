
# truenas-vm-helper

Helper script to create VM on TrueNAS SCALE and Proxmox VE using cloud-init with Debian/Ubuntu cloud images,
thanks to [Setting up a VM on TrueNAS Scale using cloud-init][truenas-cloud-init] and [Proxmox Wiki - Cloud-Init Support][pve-cloud-init].

## Quick start

```shell
# git clone the source code
test -d ~/code/github.com/ak1ra-lab || mkdir -p ~/code/github.com/ak1ra-lab
cd ~/code/github.com/ak1ra-lab
git clone https://github.com/ak1ra-lab/truenas-vm-helper.git
cd ~/code/github.com/ak1ra-lab/truenas-vm-helper

# Optional, create a file ending with .env.sh suffix to override the default environment variables in the script
cat > vm-create.env.sh<<'EOF'
vm_storage=apps
zfs_mountpoint=/mnt/
vm_seed_dir=${zfs_mountpoint}${vm_storage}/vm/seed
vm_images_dir=${zfs_mountpoint}${vm_storage}/vm/images
add_nic_0=true
nic_0_name=br0
add_nic_1=false
nic_1_name=br1
EOF

cat > qm-get.env.sh<<'EOF'
vm_storage=apps
zfs_mountpoint=/
vm_image_dir=${zfs_mountpoint}${vm_storage}/vm/images
EOF

cat > qm-template.env.sh<<'EOF'
vm_storage=apps
zfs_mountpoint=/
vm_image_dir=${zfs_mountpoint}${vm_storage}/vm/images
EOF
```

---
## [How to use `cloud-init` in NoCloud DataSource?][cloud-init-nocloud]

> The data source NoCloud allows the user to provide user-data and meta-data to the instance without running a network service (or even without having a network at all).
> 
> You can provide meta-data and user-data to a local vm boot via files on a vfat or iso9660 filesystem. The filesystem volume label must be `cidata` or `CIDATA`.

The basic process is,

* Write `user-data` and `meta-data` files according to the cloud-init documentation.
    * Note that different versions of cloud-init are installed on different distributions.
* Use `genisoimage` to package the two files into `seed.iso`.
    * `genisoimage -output seed.iso -input-charset utf8 -volid CIDATA -joliet -rock user-data meta-data`
    * TrueNAS SCALE does not have `genisoimage` installed, if you want to use `genisoimage` on TrueNAS, you may need to break the TrueNAS system dependency
	* This script creates a small vfat filesystem (~2 MiB), mounts it and copies user-data and meta-data into it
* Create a virtual machine, download the cloud images `.raw` format `dd` to the virtual machine DISK.
    * [Debian cloud images][debian-cloud-images] downloads a `.tar.xz` image, which is decompressed into `.raw` format.
    * [Ubuntu cloud images][ubuntu-cloud-images] `.img` format is actually `.qcow2` format, you need to use `qemu-img convert` to convert the format.
        * `qemu-img convert -O raw input.img output.raw`
* Mount `seed.iso` on the CDROM device of the VM.


[truenas-cloud-init]: https://blog.robertorosario.com/setting-up-a-vm-on-truenas-scale-using-cloud-init/
[cloud-init-nocloud]: https://cloudinit.readthedocs.io/en/22.4.2/topics/datasources/nocloud.html
[debian-cloud-images]: https://cloud.debian.org/images/cloud/
[debian-cloud-images-repo]: https://salsa.debian.org/cloud-team/debian-cloud-images
[ubuntu-cloud-images]: https://cloud-images.ubuntu.com/
[cloud-init-bullseye]: https://cloudinit.readthedocs.io/en/20.4.1/
[cloud-init-bookworm]: https://cloudinit.readthedocs.io/en/22.4.2/index.html
[cloud-init-jammy]: https://cloudinit.readthedocs.io/en/23.1.2/index.html
[pve-cloud-init]: https://pve.proxmox.com/wiki/Cloud-Init_Support