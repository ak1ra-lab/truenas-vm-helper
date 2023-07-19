
## 使用 Debian cloud images 时遭遇的问题

### `device /dev/sr0 with label cidata not a valid seed`

错误信息如下,

```
[    8.419989] cloud-init[576]: 2023-07-18 09:43:08,433 - DataSourceNoCloud.py[WARNING]: device /dev/sr0 with label=cidata not a valid seed.
```

这个错误原因是缺少 meta-data 文件, 两个文件都是必须的, 尽管任意一个可以是空文件.

> `datasourcenocloud.py warning device /dev/sr0 with label cidata not a valid seed` appears when the nocloud datasource sees an ISO that e.g. only contains `user-data` but no `meta-data` - both are required, even if one is empty.

参考: [Cloud-init#Troubleshooting - ArchWiki](https://wiki.archlinux.org/title/Cloud-init#Troubleshooting)

### `/sbin/growpart: grep: not found`

这个问题是在尝试启动 `debian-12-genericcloud-amd64-20230711-1438.raw` 这个镜像时发现的,
`grep`, `sed`, `rm` 这些基础命令都找不到不太可能, 怀疑是 `/` 文件系统挂载时出了什么问题?

```
Starting systemd-udevd version 252.6-1
[    0.420721] SCSI subsystem initialized
[    0.438614] ACPI: \_SB_.LNKC: Enabled at IRQ 10
[    0.441128] scsi host0: ata_piix
[    0.445141] scsi host1: ata_piix
[    0.445425] ata1: PATA max MWDMA2 cmd 0x1f0 ctl 0x3f6 bmdma 0xc160 irq 14
[    0.445872] ata2: PATA max MWDMA2 cmd 0x170 ctl 0x376 bmdma 0xc168 irq 15
[    0.453831] ACPI: \_SB_.LNKB: Enabled at IRQ 11
[    0.477197] ACPI: \_SB_.LNKD: Enabled at IRQ 10
[    0.479077] virtio_blk virtio2: 1/0/0 default/read/poll queues
[    0.479714] virtio_blk virtio2: [vda] 20971520 512-byte logical blocks (10.7 GB/10.0 GiB)
[    0.484205] virtio_net virtio0 ens3: renamed from eth0
[    0.484746] GPT:Primary header thinks Alt. header is not at the end of the disk.
[    0.485202] GPT:4194303 != 20971519
[    0.485492] GPT:Alternate GPT header not at the end of the disk.
[    0.485876] GPT:4194303 != 20971519
[    0.486163] GPT: Use GNU Parted to correct GPT errors.
[    0.486532]  vda: vda1 vda14 vda15
Begin: Loading essential drivers ... done.
Begin: Running /scripts/init-premount ... done.
Begin: Mounting root file system ... Begin: Running /scripts/local-top ... done.
Begin: Running /scripts/local-premount ... done.
Begin: Will now check root file system ... fsck from util-linux 2.38.1
[/sbin/fsck.ext4 (1) -- /dev/vda1] fsck.ext4 -a -C0 /dev/vda1 
/dev/vda1: clean, 25833/122880 files, 190959/491264 blocks
done.
[    0.541497] EXT4-fs (vda1): mounted filesystem with ordered data mode. Quota mode: none.
done.
Begin: Running /scripts/local-bottom ... GROWROOT: /sbin/growpart: 824: /sbin/growpart: grep: not found
GPT PMBR size mismatch (4194303 != 20971519) will be corrected by write.
The backup GPT table is not on the end of the device.
/sbin/growpart: 853: /sbin/growpart: sed: not found
WARN: unknown label 
/sbin/growpart: 354: /sbin/growpart: sed: not found
FAILED: sed failed on dump output
/sbin/growpart: 83: /sbin/growpart: rm: not found
done.
Begin: Running /scripts/init-bottom ... done.
[    0.562915] Not activating Mandatory Access Control as /sbin/tomoyo-init does not exist.
[    0.582269] systemd[1]: Inserted module 'autofs4'
[    0.591044] systemd[1]: systemd 252.6-1 running in system mode (+PAM +AUDIT +SELINUX +APPARMOR +IMA +SMACK +SECCOMP +GCRYPT -GNUTLS +OPENSSL +ACL +BLKID +CURL +ELFUTILS +FIDO2 +IDN2 -IDN +IPTC +KMOD +LIBCRYPTSETUP +LIBFDISK +PCRE2 -PWQUALITY +P11KIT +QRENCODE +TPM2 +BZIP2 +LZ4 +XZ +ZLIB +ZSTD -BPF_FRAMEWORK -XKBCOMMON +UTMP +SYSVINIT default-hierarchy=unified)
[    0.592719] systemd[1]: Detected virtualization kvm.
[    0.593043] systemd[1]: Detected architecture x86-64.
```

## Debian 11 (bullseye) 最近几次构建的 `generic` type 镜像都无法启动

最初是发现 `debian-11-generic-amd64-20230515-1381.raw` 这个镜像出现 `segfault` 的错误, 系统无法启动, 进入 initramfs 命令行, 后续发现最近几次构建都无法启动,

```
[    0.609667] Run /init as init process
Loading, please wait...
Starting version 247.3-7+deb11u2
Segment violation
Begin: Loading essential drivers ... done.
[    0.614529] systemd-udevd[86]: segfault at 7fe4ffed0b30 ip 00007fe4ffdc7a12 sp 00007ffdbd7ce5e0 error 25 in libc-2.31.so[7fe4ffd22000+159000]
[    0.616037] Code: Unable to access opcode bytes at RIP 0x7fe4ffdc79e8.
Begin: Running /scripts/init-premount ... done.
Begin: Mounting root file system ... Begin: Running /scripts/local-top ... done.
Begin: Running /scripts/local-premount ... done.
Begin: Waiting for root file system ... Begin: Running /scripts/local-block ... done.
Begin: Running /scripts/local-block ... done.
... ...
Begin: Running /scripts/local-block ... done.
done.
Gave up waiting for root file system device.  Common problems:
 - Boot args (cat /proc/cmdline)
   - Check rootdelay= (did the system wait long enough?)
 - Missing modules (cat /proc/modules; ls /dev)
ALERT!  UUID=d39ab0ce-1f85-43e3-8dcb-adabd32bce5c does not exist.  Dropping to a shell!
(initramfs) 
```

## 总结一下

* ubuntu `jammy` 从一开始就能使用 `cloud-init`
* debian `bookworm` 的 `generic` type 镜像可以使用 `cloud-init`
* debian `bookworm` 的 `genericcloud` type 镜像启动时在 `GROWROOT` 阶段时会报 `/sbin/growpart: grep: not found`
    * 没找到原因, 怀疑是 `/` 文件系统挂载时出了什么问题?
* debian `bullseye` 的 `generic` type 镜像最近几个版本的构建是有问题的,
    * 各个版本表现还各自不太一样, 有些是直接找不到根分区进入 `initramfs` shell, 有些直接进入 UEFI shell...
        * 这个问题让我非常郁闷, 一度怀疑是我虚拟机设置或者是硬件不兼容, 排查半天找了个最初的版本, 发现一切正常
    * 最初的 `debian-11-generic-amd64-20210814-734.raw` 能正常启动
    * 最近的能正常启动的构建是 `debian-11-generic-amd64-20230124-1270.raw`
        * 这个版本之后的构建全部是坏的, 包括今天刚发布的构建
        * issues 区没看到有人反馈这个问题, 可能用户还是太少了?
        * 但是我仍然不确定是不是我硬件问题, 不知道有没有人愿意测试下?
    * 或许可以找下 5 月初可能是什么提交引入的 bug ?

下面这些镜像都是坏的,

```
debian/bullseye/20230501-1367/debian-11-generic-amd64-20230501-1367.raw
debian/bullseye/20230515-1381/debian-11-generic-amd64-20230515-1381.raw
debian/bullseye/20230601-1398/debian-11-generic-amd64-20230601-1398.raw
debian/bullseye/20230717-1444/debian-11-generic-amd64-20230717-1444.raw
```
