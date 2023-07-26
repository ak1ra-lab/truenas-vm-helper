
# truenas-vm-helper

Helper script to create VM on TrueNAS SCALE using cloud-init with Debian/Ubuntu cloud images,
thanks to [Setting up a VM on TrueNAS Scale using cloud-init][truenas-cloud-init]

## How to use this script?

* Configure the `VM_DATASET` variable in `vm-create.sh` to be the ZFS Dataset that you intend to use to store the VMs.
* Download raw format cloud images (eg. [debian][debian-cloud-images], [ubuntu][ubuntu-cloud-images]) for each operating system to the `$VM_IMAGE_DIR` directory.
    * Theoretically all **raw** OS cloud images are supported, but I haven't tested them all.
    * `wget -c -x -P /mnt/apps/vm/images https://cloud.debian.org/images/cloud/bookworm/20230723-1450/debian-12-generic-amd64-20230723-1450.raw`
* Customize the `user-data` and `meta-data` in the `cloud-init/` directory.
* Execute `./vm-create.sh`, select `VM_IMAGE`, enter `VM_NAME`,
    * Note that `VM_NAME` can only be (lowercase) letters, numbers and underscores.

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
* Mount `seed.iso` on the CDROM device of the VM, note that the boot order needs to be before DISK.
    * [The article given above][truenas-cloud-init] says that the CDROM device needs to be booted after DISK, may be wrong?
    * It has been tested that the CDROM will not be read after the DISK boot sequence.


[truenas-cloud-init]: https://blog.robertorosario.com/setting-up-a-vm-on-truenas-scale-using-cloud-init/
[cloud-init-nocloud]: https://cloudinit.readthedocs.io/en/22.4.2/topics/datasources/nocloud.html
[debian-cloud-images]: https://cloud.debian.org/images/cloud/
[debian-cloud-images-repo]: https://salsa.debian.org/cloud-team/debian-cloud-images
[ubuntu-cloud-images]: https://cloud-images.ubuntu.com/
[cloud-init-bullseye]: https://cloudinit.readthedocs.io/en/20.4.1/
[cloud-init-bookworm]: https://cloudinit.readthedocs.io/en/22.4.2/index.html
[cloud-init-jammy]: https://cloudinit.readthedocs.io/en/23.1.2/index.html
