
# truenas-vm-helper

Helper script to create VM on TrueNAS SCALE using cloud-init with Debian/Ubuntu cloud images,
thanks to [Setting up a VM on TrueNAS Scale using cloud-init](https://blog.robertorosario.com/setting-up-a-vm-on-truenas-scale-using-cloud-init/)

## [Debian cloud images](https://cloud.debian.org/images/cloud/)

Debian cloud images 存在几个不同类别 (type),

- _azure_: Optimized for the Microsoft Azure environment
- _ec2_: Optimized for the Amazon EC2
- _generic_: Should run in any environment using cloud-init, for e.g. OpenStack, DigitalOcean and also on bare metal.
- _genericcloud_: Similar to generic. Should run in any virtualised environment. Is smaller than `generic` by excluding drivers for physical hardware.
- _nocloud_: Mostly useful for testing the build process itself. Doesn't have cloud-init installed, but instead allows root login without a password.

Debian cloud images GitLab repository: https://salsa.debian.org/cloud-team/debian-cloud-images.git

## 如何在 `nocloud` 环境 (如 TrueNAS SCALE Virtualization) 使用 Debian/Ubuntu cloud images

基本流程,

* 根据 cloud-init 文档编写 `user-data` 和 `meta-data` 文件
    * 注意各发行版不同版本镜像安装的 cloud-init 版本不同
* 使用 `genisoimage` 将这两个文件打包成 `seed.iso`
    * `genisoimage -output seed.iso -input-charset utf8 -volid cidata -joliet -rock user-data meta-data`
    * TrueNAS SCALE 并没有安装 `genisoimage`, 需要在别的机器上创建 `seed.iso` 或者打破 TrueNAS 系统依赖
* 创建虚拟机, 下载 cloud images 的 `.raw` 格式 `dd` 到虚拟机 DISK
    * TrueNAS 中的 DISK 设备可创建 ZVOL 直接使用
    * [Debian cloud images](https://cloud.debian.org/images/cloud/) 可下载 `.tar.xz` 格式镜像, 解压后就是 `.raw` 格式
    * [Ubuntu cloud images](https://cloud-images.ubuntu.com/) 的 `.img` 格式实际上为 `.qcow2` 格式, 需要用 `qemu-img convert` 转换格式
        * `qemu-img convert -O raw input.img output.raw`
* 将 `seed.iso` 挂载到虚拟机的 CDROM 设备上, 注意启动顺序需要在 DISK 之前
    * 上面给出的文章提到 CDROM 设备启动顺序需要在 DISK 之后可能有误?
        * 实测在 DISK 之后不会读取 CDROM 中挂载的 `seed.iso`

参考文档,

* Debian 11 (bullseye): [cloud-init 20.4.1 documentation](https://cloudinit.readthedocs.io/en/20.4.1/)
* Debian 12 (bookworm): [cloud-init 22.4.2 documentation](https://cloudinit.readthedocs.io/en/22.4.2/index.html)
* Ubuntu 22.04 (jammy): [cloud-init 23.1.2 documentation](https://cloudinit.readthedocs.io/en/23.1.2/reference/modules.html)
