# vJunos-Router and vMX virtualized with KVM-QEMU-libvirt stack in Debian 12 without Juniper orchestration scripts

Network topology used as an example:

![Juniper vXM virtualized with KVM-QEMU-libvirt stack in Debian 12](https://github.com/tonusoo/vMX-without-Juniper-orchestration-scripts/blob/main/imgs/Juniper_vXM_virtualized_with_KVM-QEMU-libvirt_stack_in_Debian_12.png)

### Host machine network configuration

[Network configuration](https://github.com/tonusoo/vMX-without-Juniper-orchestration-scripts/blob/main/misc/vMX_lab_host_network_config.txt) of the host machine is managed by `systemd-networkd`:

![vMX lab host network config](https://github.com/tonusoo/vMX-without-Juniper-orchestration-scripts/blob/main/imgs/vMX_lab_host_network_config.png)

Output of `networkctl` once the `a-r1`, `a-r2` and `a-r42` routers are running:

![output of networkctl](https://github.com/tonusoo/vMX-without-Juniper-orchestration-scripts/blob/main/imgs/vMX_lab_networkctl_output.png)

Resources like VMs, Linux bridges and TAP interfaces related to `iasb-class` project have the `a-` prefix. For example, this allows to find VMs related to this project with `sudo virsh list --all --name | grep ^a-` or all the Linux bridges related to this project with `ip -br l sh type bridge | grep ^a-`:
```
martin@deb-lab-svr:~$ ip -br l sh type bridge | grep ^a-
a-br-default     UP             5e:3a:61:99:80:c0 <BROADCAST,MULTICAST,UP,LOWER_UP>
a-br-ext         UP             1e:37:c1:45:4e:be <BROADCAST,MULTICAST,UP,LOWER_UP>
a-r1-br-int      UP             b2:f0:00:0b:76:fc <BROADCAST,MULTICAST,UP,LOWER_UP>
a-r1-r2-1        UP             2a:ea:f8:5f:2d:92 <BROADCAST,MULTICAST,UP,LOWER_UP>
a-r1-r2-2        UP             3a:4b:3e:50:89:b9 <BROADCAST,MULTICAST,UP,LOWER_UP>
a-r2-br-int      UP             3a:29:3c:25:f2:4c <BROADCAST,MULTICAST,UP,LOWER_UP>
a-r2-r42-1       UP             82:c2:d1:d4:e1:da <BROADCAST,MULTICAST,UP,LOWER_UP>
a-r42-br-int     UP             92:eb:0d:1e:75:17 <BROADCAST,MULTICAST,UP,LOWER_UP>
martin@deb-lab-svr:~$
```
Next project in the same host machine would have the `b-` prefix.

Host machine is running a [patched `bridge` module](https://github.com/tonusoo/vMX-without-Juniper-orchestration-scripts/blob/main/misc/br_private.patch) where [bridges forward LACP frames](https://github.com/tonusoo/vMX-without-Juniper-orchestration-scripts/blob/main/scripts-and-conf/etc/udev/rules.d/90-linux-br-group-fwd-mask.rules)(dst MAC `01:80:C2:00:00:02`).

The host machine has a [`patch-linux-bridge.deb`](https://github.com/tonusoo/vMX-without-Juniper-orchestration-scripts/blob/main/misc/patch-linux-bridge.deb) package installed, which is a workaround to ensure that the `bridge` module is automatically patched each time the kernel is upgraded:
```
martin@deb-lab-svr:~$ dpkg -l patch-linux-bridge
Desired=Unknown/Install/Remove/Purge/Hold
| Status=Not/Inst/Conf-files/Unpacked/halF-conf/Half-inst/trig-aWait/Trig-pend
|/ Err?=(none)/Reinst-required (Status,Err: uppercase=bad)
||/ Name               Version      Architecture Description
+++-==================-============-============-===================================================================================
ii  patch-linux-bridge 0.1          all          Patches bridge.ko to remove all group forwarding restrictions for the Linux bridge.
martin@deb-lab-svr:~$
```
This works in a way that the `patch-linux-bridge.deb` provides a [dpkg trigger](https://github.com/tonusoo/vMX-without-Juniper-orchestration-scripts/blob/main/patch-linux-bridge/DEBIAN/triggers) which ensures that the [postinst script](https://github.com/tonusoo/vMX-without-Juniper-orchestration-scripts/blob/main/patch-linux-bridge/DEBIAN/postinst) of the `patch-linux-bridge.deb` is executed if the `linux-image-amd64` package is upgraded. Triggers are processed at the end of the `apt upgrade` and even if the trigger for the `patch-linux-bridge` fails, then this does not prevent processing the triggers for other packages. An example of `apt upgrade` where kernel was upgraded from `6.1.0-25-amd64` to `6.1.0-26-amd64` and the `bridge` module was automatically patched can be seen [here](https://github.com/tonusoo/vMX-without-Juniper-orchestration-scripts/blob/main/misc/output_of_apt_upgrade.txt).

One could use `libvirt` to manage the bridges([example](https://github.com/tonusoo/vMX-without-Juniper-orchestration-scripts/blob/main/misc/a-r1-r2-2.xml)), but `systemd-networkd` approach has an advantage of keeping all(including physical interfaces of the host machine) the network related configuration in one place.

### Creating the vMX virtual machines

Both the `vCP` and `vFP` virtual machines are created with `virt-install`:
```
martin@deb-lab-svr:~$ mkdir ~/iasb-class
martin@deb-lab-svr:~$ # Extract the base images from HDD storage to SSDs
martin@deb-lab-svr:~$ tar -xf /media/storage/juniper_images/vmx-bundle-21.4R3.15.tgz --directory ~/iasb-class/
martin@deb-lab-svr:~$ # user "martin" belongs to the "sudo" group, and /home/martin has 755 permissions, which come from the default UMASK value in /etc/login.defs
martin@deb-lab-svr:~$ for name in a-r{1..2} a-r42; do

    mkdir -p ~/iasb-class/"$name"/images

    qemu-img create -F qcow2 -b ~/iasb-class/vmx/images/junos-vmx-x86-64-21.4R3.15.qcow2 -f qcow2 ~/iasb-class/"$name"/images/junos-vmx-x86-64-21.4R3.15.qcow2
    qemu-img create -F qcow2 -b ~/iasb-class/vmx/images/vmxhdd.img -f qcow2 ~/iasb-class/"$name"/images/vmxhdd.img
    qemu-img create -F raw -b ~/iasb-class/vmx/images/metadata-usb-re.img -f qcow2 ~/iasb-class/"$name"/images/metadata-usb-re.img

    sudo virt-install --osinfo freebsd12.2 \
        --name "$name-vcp" \
        --events on_crash=restart \
        --memory 1024 \
        --vcpus 1 \
        --import \
        --disk ~/iasb-class/"$name"/images/junos-vmx-x86-64-21.4R3.15.qcow2,cache=directsync \
        --disk ~/iasb-class/"$name"/images/vmxhdd.img,cache=directsync \
        --disk ~/iasb-class/"$name"/images/metadata-usb-re.img,cache=directsync \
        --network bridge="a-br-ext,model=virtio,target=$name-vcp-ext" \
        --network bridge="$name-br-int,model=virtio,target=$name-vcp-int" \
        --graphics none \
        --noautoconsole

    sudo virsh desc "$name-vcp" --title "vMX vCP; Junos 21.4R3.15" --live --config
    sudo virsh autostart "$name-vcp"


    qemu-img create -F raw -b ~/iasb-class/vmx/images/vFPC-20220714.img -f qcow2 ~/iasb-class/"$name"/images/vFPC-20220714.img

    sudo virt-install --osinfo linux2022 \
        --name "$name-vfp" \
        --events on_crash=restart \
        --memory 4096 \
        --vcpus 3 \
        --import \
        --disk ~/iasb-class/"$name"/images/vFPC-20220714.img,cache=directsync \
        --network bridge="a-br-ext,model=virtio,target=$name-vfp-ext" \
        --network bridge="$name-br-int,model=virtio,target=$name-vfp-int" \
        --network bridge="a-br-default,model=virtio,target=$name-ge-0.0.0" \
        --network bridge="a-br-default,model=virtio,target=$name-ge-0.0.1" \
        --network bridge="a-br-default,model=virtio,target=$name-ge-0.0.2" \
        --network bridge="a-br-default,model=virtio,target=$name-ge-0.0.3" \
        --network bridge="a-br-default,model=virtio,target=$name-ge-0.0.4" \
        --network bridge="a-br-default,model=virtio,target=$name-ge-0.0.5" \
        --network bridge="a-br-default,model=virtio,target=$name-ge-0.0.6" \
        --network bridge="a-br-default,model=virtio,target=$name-ge-0.0.7" \
        --network bridge="a-br-default,model=virtio,target=$name-ge-0.0.8" \
        --network bridge="a-br-default,model=virtio,target=$name-ge-0.0.9" \
        --graphics none \
        --noautoconsole

    sudo virsh desc "$name-vfp" --title "vMX vFP" --live --config
    sudo virsh autostart "$name-vfp"

done
Formatting '/home/martin/iasb-class/a-r1/images/junos-vmx-x86-64-21.4R3.15.qcow2', fmt=qcow2 cluster_size=65536 extended_l2=off compression_type=zlib size=28992077824 backing_file=/home/martin/iasb-class/vmx/images/junos-vmx-x86-64-21.4R3.15.qcow2 backing_fmt=qcow2 lazy_refcounts=off refcount_bits=16
Formatting '/home/martin/iasb-class/a-r1/images/vmxhdd.img', fmt=qcow2 cluster_size=65536 extended_l2=off compression_type=zlib size=8589934592 backing_file=/home/martin/iasb-class/vmx/images/vmxhdd.img backing_fmt=qcow2 lazy_refcounts=off refcount_bits=16
Formatting '/home/martin/iasb-class/a-r1/images/metadata-usb-re.img', fmt=qcow2 cluster_size=65536 extended_l2=off compression_type=zlib size=10485760 backing_file=/home/martin/iasb-class/vmx/images/metadata-usb-re.img backing_fmt=raw lazy_refcounts=off refcount_bits=16

Starting install...
Creating domain...                                                                                                                                                                                                                                                                                      |    0 B  00:00:00
Domain creation completed.
Domain title updated successfully
Domain 'a-r1-vcp' marked as autostarted

Formatting '/home/martin/iasb-class/a-r1/images/vFPC-20220714.img', fmt=qcow2 cluster_size=65536 extended_l2=off compression_type=zlib size=8889827328 backing_file=/home/martin/iasb-class/vmx/images/vFPC-20220714.img backing_fmt=raw lazy_refcounts=off refcount_bits=16

Starting install...
Creating domain...                                                                                                                                                                                                                                                                                      |    0 B  00:00:00
Domain creation completed.
Domain title updated successfully
Domain 'a-r1-vfp' marked as autostarted

Formatting '/home/martin/iasb-class/a-r2/images/junos-vmx-x86-64-21.4R3.15.qcow2', fmt=qcow2 cluster_size=65536 extended_l2=off compression_type=zlib size=28992077824 backing_file=/home/martin/iasb-class/vmx/images/junos-vmx-x86-64-21.4R3.15.qcow2 backing_fmt=qcow2 lazy_refcounts=off refcount_bits=16
Formatting '/home/martin/iasb-class/a-r2/images/vmxhdd.img', fmt=qcow2 cluster_size=65536 extended_l2=off compression_type=zlib size=8589934592 backing_file=/home/martin/iasb-class/vmx/images/vmxhdd.img backing_fmt=qcow2 lazy_refcounts=off refcount_bits=16
Formatting '/home/martin/iasb-class/a-r2/images/metadata-usb-re.img', fmt=qcow2 cluster_size=65536 extended_l2=off compression_type=zlib size=10485760 backing_file=/home/martin/iasb-class/vmx/images/metadata-usb-re.img backing_fmt=raw lazy_refcounts=off refcount_bits=16

Starting install...
Creating domain...                                                                                                                                                                                                                                                                                      |    0 B  00:00:00
Domain creation completed.
Domain title updated successfully
Domain 'a-r2-vcp' marked as autostarted

Formatting '/home/martin/iasb-class/a-r2/images/vFPC-20220714.img', fmt=qcow2 cluster_size=65536 extended_l2=off compression_type=zlib size=8889827328 backing_file=/home/martin/iasb-class/vmx/images/vFPC-20220714.img backing_fmt=raw lazy_refcounts=off refcount_bits=16

Starting install...
Creating domain...                                                                                                                                                                                                                                                                                      |    0 B  00:00:00
Domain creation completed.
Domain title updated successfully
Domain 'a-r2-vfp' marked as autostarted

Formatting '/home/martin/iasb-class/a-r42/images/junos-vmx-x86-64-21.4R3.15.qcow2', fmt=qcow2 cluster_size=65536 extended_l2=off compression_type=zlib size=28992077824 backing_file=/home/martin/iasb-class/vmx/images/junos-vmx-x86-64-21.4R3.15.qcow2 backing_fmt=qcow2 lazy_refcounts=off refcount_bits=16
Formatting '/home/martin/iasb-class/a-r42/images/vmxhdd.img', fmt=qcow2 cluster_size=65536 extended_l2=off compression_type=zlib size=8589934592 backing_file=/home/martin/iasb-class/vmx/images/vmxhdd.img backing_fmt=qcow2 lazy_refcounts=off refcount_bits=16
Formatting '/home/martin/iasb-class/a-r42/images/metadata-usb-re.img', fmt=qcow2 cluster_size=65536 extended_l2=off compression_type=zlib size=10485760 backing_file=/home/martin/iasb-class/vmx/images/metadata-usb-re.img backing_fmt=raw lazy_refcounts=off refcount_bits=16

Starting install...
Creating domain...                                                                                                                                                                                                                                                                                      |    0 B  00:00:00
Domain creation completed.
Domain title updated successfully
Domain 'a-r42-vcp' marked as autostarted

Formatting '/home/martin/iasb-class/a-r42/images/vFPC-20220714.img', fmt=qcow2 cluster_size=65536 extended_l2=off compression_type=zlib size=8889827328 backing_file=/home/martin/iasb-class/vmx/images/vFPC-20220714.img backing_fmt=raw lazy_refcounts=off refcount_bits=16

Starting install...
Creating domain...                                                                                                                                                                                                                                                                                      |    0 B  00:00:00
Domain creation completed.
Domain title updated successfully
Domain 'a-r42-vfp' marked as autostarted

martin@deb-lab-svr:~$
```

As seen above, the `vFP` VMs were built with ten vNICs for `ge-0.0.0` - `ge-0.0.9` interfaces. While it's possible to add vNICs to an already running `vFP` with `virsh attach-interface ... --live`(for example `sudo virsh attach-interface a-r1-vfp bridge a-r1-r2-2 --target a-r1-ge-0.0.1 --model virtio --config --live`), then this approach requires re-enumerating the PCIe bus with `echo 1 > /sys/bus/pci/rescan` in the `vFP` virtual machine. In addition, if the `riot`(virtual Trio chipset) DPDK application in `vFP` is already running, then this needs to be also restarted in order it to pick up the new PCIe network interfaces.

`vFP` interfaces are connected to correct bridges with [mv-vm-int](https://github.com/tonusoo/vMX-without-Juniper-orchestration-scripts/blob/main/scripts-and-conf/usr/local/bin/mv-vm-int) script:
```
martin@deb-lab-svr:~$ # a-r1-vfp
martin@deb-lab-svr:~$ sudo mv-vm-int a-r1-ge-0.0.0 a-r1-r2-1
Device updated successfully

Connected a-r1-ge-0.0.0 from bridge a-br-default to bridge a-r1-r2-1 and updated a-r1-vfp XML
martin@deb-lab-svr:~$ sudo mv-vm-int a-r1-ge-0.0.1 a-r1-r2-2
Device updated successfully

Connected a-r1-ge-0.0.1 from bridge a-br-default to bridge a-r1-r2-2 and updated a-r1-vfp XML
martin@deb-lab-svr:~$
martin@deb-lab-svr:~$ # a-r2-vfp
martin@deb-lab-svr:~$ sudo mv-vm-int a-r2-ge-0.0.0 a-r1-r2-1
Device updated successfully

Connected a-r2-ge-0.0.0 from bridge a-br-default to bridge a-r1-r2-1 and updated a-r2-vfp XML
martin@deb-lab-svr:~$ sudo mv-vm-int a-r2-ge-0.0.1 a-r1-r2-2
Device updated successfully

Connected a-r2-ge-0.0.1 from bridge a-br-default to bridge a-r1-r2-2 and updated a-r2-vfp XML
martin@deb-lab-svr:~$ sudo mv-vm-int a-r2-ge-0.0.2 a-r2-r42-1
Device updated successfully

Connected a-r2-ge-0.0.2 from bridge a-br-default to bridge a-r2-r42-1 and updated a-r2-vfp XML
martin@deb-lab-svr:~$
martin@deb-lab-svr:~$ # a-r42-vfp
martin@deb-lab-svr:~$ sudo mv-vm-int a-r42-ge-0.0.0 a-r2-r42-1
Device updated successfully

Connected a-r42-ge-0.0.0 from bridge a-br-default to bridge a-r2-r42-1 and updated a-r42-vfp XML
martin@deb-lab-svr:~$
```

Output of `virsh domiflist` for `a-r2-vfp` VM:
```
martin@deb-lab-svr:~$ sudo virsh domiflist a-r2-vfp
 Interface       Type     Source         Model    MAC
---------------------------------------------------------------------
 a-r2-vfp-ext    bridge   a-br-ext       virtio   52:54:00:76:f2:f1
 a-r2-vfp-int    bridge   a-r2-br-int    virtio   52:54:00:3a:67:e3
 a-r2-ge-0.0.0   bridge   a-r1-r2-1      virtio   52:54:00:56:5c:b5
 a-r2-ge-0.0.1   bridge   a-r1-r2-2      virtio   52:54:00:7f:c8:4c
 a-r2-ge-0.0.2   bridge   a-r2-r42-1     virtio   52:54:00:9d:e6:3e
 a-r2-ge-0.0.3   bridge   a-br-default   virtio   52:54:00:b8:d3:29
 a-r2-ge-0.0.4   bridge   a-br-default   virtio   52:54:00:17:d4:51
 a-r2-ge-0.0.5   bridge   a-br-default   virtio   52:54:00:11:a7:f6
 a-r2-ge-0.0.6   bridge   a-br-default   virtio   52:54:00:54:63:be
 a-r2-ge-0.0.7   bridge   a-br-default   virtio   52:54:00:c5:36:b2
 a-r2-ge-0.0.8   bridge   a-br-default   virtio   52:54:00:7c:7d:de
 a-r2-ge-0.0.9   bridge   a-br-default   virtio   52:54:00:7e:54:7d

martin@deb-lab-svr:~$
martin@deb-lab-svr:~$ ip l sh master a-r2-r42-1
321: a-r2-ge-0.0.2: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue master a-r2-r42-1 state UNKNOWN mode DEFAULT group default qlen 1000
    link/ether fe:54:00:9d:e6:3e brd ff:ff:ff:ff:ff:ff
333: a-r42-ge-0.0.0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue master a-r2-r42-1 state UNKNOWN mode DEFAULT group default qlen 1000
    link/ether fe:54:00:60:e9:3b brd ff:ff:ff:ff:ff:ff
martin@deb-lab-svr:~$
```

However, depending on the lab, it might be sufficient to leave the interfaces in `<project_letter>-br-default` bridge.

The `vCP` and `vFP` virtual machines were installed under **system** libvirtd instance(**qemu:///system** URI) which ensures that the VM autostart on host boot works and one can use TAP interfaces with custom names(for example `a-r1-ge-0.0.0`). For desktop(e.g lab workstation) use cases one might prefer that the `vCP` and `vFP` virtual machines are installed under **session** libvirtd instance(**qemu:///session** URI) and started once the user logs in. This requires that the user is in the `kvm` group and `qemu-bridge-helper` has [setuid attribute set](https://wiki.qemu.org/Features/HelperNetworking):
```
martin@deb-lab-svr:~$ groups
martin sudo kvm
martin@deb-lab-svr:~$
martin@deb-lab-svr:~$ ls -l /dev/kvm
crw-rw---- 1 root kvm 10, 232 Sep 19 01:12 /dev/kvm
martin@deb-lab-svr:~$
martin@deb-lab-svr:~$ ls -l /usr/lib/qemu/qemu-bridge-helper
-rwsr-xr-x 1 root root 664280 Jul 17 14:27 /usr/lib/qemu/qemu-bridge-helper
martin@deb-lab-svr:~$
```
Some distros, like `Fedora 40` and `AlmaLinux 9.4`, ship with more permissive access to `/dev/kvm`, and `qemu-bridge-helper` is configured with the setuid attribute by the package manager.

Default ACL file of `qemu-bridge-helper` named `/etc/qemu/bridge.conf` includes an ACL file named `/etc/qemu/martin.conf` which allows user `martin` to connect TAP interfaces to any bridge with the `qemu-bridge-helper` utility:
```
martin@deb-lab-svr:~$ # The only user of group named "martin" is user "martin"
martin@deb-lab-svr:~$ ls -l /etc/qemu/
total 8
-rw-r--r-- 1 root root   30 Sep 15 17:00 bridge.conf
-rw-rw---- 1 root martin 10 Sep 15 22:30 martin.conf
martin@deb-lab-svr:~$
martin@deb-lab-svr:~$ cat /etc/qemu/bridge.conf
include /etc/qemu/martin.conf
martin@deb-lab-svr:~$
martin@deb-lab-svr:~$ cat /etc/qemu/martin.conf
allow all
martin@deb-lab-svr:~$
```

Example of `a-r42-vfp` installed under **session** libvirtd instance:
```
martin@deb-lab-svr:~$ virsh uri
qemu:///session

martin@deb-lab-svr:~$ virt-install --osinfo linux2022 \
    --name a-r42-vfp \
    --memory 4096 \
    --vcpus 3 \
    --import \
    --disk ~/vmx-lab/a-r42/images/vFPC-20220714.img,cache=directsync \
    --network bridge="a-br-ext",model=virtio,target="a-r42-vfp-ext" \
    --network bridge="a-r42-br-int",model=virtio,target="a-r42-vfp-int" \
    --network bridge="a-r2-r42-1",model=virtio,target="a-r42-ge-0.0.0" \
    --graphics none \
    --noautoconsole

Starting install...
Creating domain...                                                                                                                                                                                                                                        |    0 B  00:00:00
Domain creation completed.
martin@deb-lab-svr:~$
martin@deb-lab-svr:~$ virsh list
 Id   Name        State
---------------------------
 2    a-r42-vfp   running

martin@deb-lab-svr:~$
martin@deb-lab-svr:~$ # TAP interfaces names are auto generated
martin@deb-lab-svr:~$ virsh domiflist a-r42-vfp
 Interface   Type     Source         Model    MAC
-----------------------------------------------------------------
 tap0        bridge   a-br-ext       virtio   52:54:00:85:40:76
 tap1        bridge   a-r42-br-int   virtio   52:54:00:89:e9:a4
 tap2        bridge   a-r2-r42-1     virtio   52:54:00:c4:59:ef

martin@deb-lab-svr:~$
```

### Creating a vJunos-router virtual machine and changing the network topology

A `vJunos-router` named `a-r3` is added, `ge-0/0/2` of `a-r2` is connected to `a-r2-r3-1`, `ge-0/0/3` of `a-r2` is connected to `a-r2-r42-1` and a 50ms RTT is introduced between `a-r2` and `a-r3` routers:

![Juniper routers virtualized with KVM-QEMU-libvirt stack in Debian 12 with a-r3](https://github.com/tonusoo/vMX-without-Juniper-orchestration-scripts/blob/main/imgs/Juniper_routers_virtualized_with_KVM-QEMU-libvirt_stack_in_Debian_12_with_a-r3.png)

`vJunos-router` built without initial configuration:
```
martin@deb-lab-svr:~$ mkdir ~/iasb-class/vJunos-router
martin@deb-lab-svr:~$ # Extract the base image from HDD storage to SSDs
martin@deb-lab-svr:~$ cp -v /media/storage/juniper_images/vJunos-router-23.2R1.15.qcow2 ~/iasb-class/vJunos-router/
'/media/storage/juniper_images/vJunos-router-23.2R1.15.qcow2' -> '/home/martin/iasb-class/vJunos-router/vJunos-router-23.2R1.15.qcow2'
martin@deb-lab-svr:~$
martin@deb-lab-svr:~$ mkdir -p ~/iasb-class/a-r3/images
martin@deb-lab-svr:~$ qemu-img create -F qcow2 -b ~/iasb-class/vJunos-router/vJunos-router-23.2R1.15.qcow2 -f qcow2 ~/iasb-class/a-r3/images/vJunos-router-23.2R1.15.qcow2
Formatting '/home/martin/iasb-class/a-r3/images/vJunos-router-23.2R1.15.qcow2', fmt=qcow2 cluster_size=65536 extended_l2=off compression_type=zlib size=34100740096 backing_file=/home/martin/iasb-class/vJunos-router/vJunos-router-23.2R1.15.qcow2 backing_fmt=qcow2 lazy_refcounts=off refcount_bits=16
martin@deb-lab-svr:~$
martin@deb-lab-svr:~$ sudo virt-install --osinfo linux2022 \
    --name a-r3-vjr \
    --events on_crash=restart \
    --memory 5120 \
    --vcpus 4 \
    --import \
    --disk ~/iasb-class/a-r3/images/vJunos-router-23.2R1.15.qcow2,cache=directsync \
    --network bridge="a-br-ext,model=virtio,target=a-r3-vjr-ext" \
    --network bridge="a-br-default,model=virtio,target=a-r3-ge-0.0.0" \
    --network bridge="a-br-default,model=virtio,target=a-r3-ge-0.0.1" \
    --network bridge="a-br-default,model=virtio,target=a-r3-ge-0.0.2" \
    --network bridge="a-br-default,model=virtio,target=a-r3-ge-0.0.3" \
    --network bridge="a-br-default,model=virtio,target=a-r3-ge-0.0.4" \
    --network bridge="a-br-default,model=virtio,target=a-r3-ge-0.0.5" \
    --network bridge="a-br-default,model=virtio,target=a-r3-ge-0.0.6" \
    --network bridge="a-br-default,model=virtio,target=a-r3-ge-0.0.7" \
    --network bridge="a-br-default,model=virtio,target=a-r3-ge-0.0.8" \
    --network bridge="a-br-default,model=virtio,target=a-r3-ge-0.0.9" \
    --qemu-commandline="-smbios type=1,product=VM-VMX,family=lab" \
    --graphics none \
    --noautoconsole

Starting install...
Creating domain...                                                                                                                                                                                                                                                                                      |    0 B  00:00:00
Domain creation completed.
martin@deb-lab-svr:~$ sudo virsh desc "a-r3-vjr" --title "vJunos-Router; Junos 23.2R1.15" --live --config
Domain title updated successfully
martin@deb-lab-svr:~$ sudo virsh autostart "a-r3-vjr"
Domain 'a-r3-vjr' marked as autostarted

martin@deb-lab-svr:~$
martin@deb-lab-svr:~$ sudo virsh list --title
 Id   Name        State     Title
------------------------------------------------------------
 3    a-r1-vcp    running   vMX vCP; Junos 21.4R3.15
 4    a-r1-vfp    running   vMX vFP
 5    a-r2-vcp    running   vMX vCP; Junos 21.4R3.15
 6    a-r2-vfp    running   vMX vFP
 7    a-r42-vcp   running   vMX vCP; Junos 21.4R3.15
 8    a-r42-vfp   running   vMX vFP
 9    a-r3-vjr    running   vJunos-Router; Junos 23.2R1.15

martin@deb-lab-svr:~$
```

Connecting the `a-r2` interface `ge-0/0/2` from `a-r2-r42-1` to `a-r2-r3-1`(created by adjusting the configuration of `systemd-networkd`) and `ge-0/0/3` to `a-r2-r42-1`:
```
martin@deb-lab-svr:~$ ip l sh dev a-r2-ge-0.0.2
321: a-r2-ge-0.0.2: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue master a-r2-r42-1 state UNKNOWN mode DEFAULT group default qlen 1000
    link/ether fe:54:00:9d:e6:3e brd ff:ff:ff:ff:ff:ff
martin@deb-lab-svr:~$
martin@deb-lab-svr:~$ sudo mv-vm-int a-r2-ge-0.0.2 a-r2-r3-1
Device updated successfully

Connected a-r2-ge-0.0.2 from bridge a-r2-r42-1 to bridge a-r2-r3-1 and updated a-r2-vfp XML
martin@deb-lab-svr:$
martin@deb-lab-svr:~$ ip l sh dev a-r2-ge-0.0.2
321: a-r2-ge-0.0.2: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue master a-r2-r3-1 state UNKNOWN mode DEFAULT group default qlen 1000
    link/ether fe:54:00:9d:e6:3e brd ff:ff:ff:ff:ff:ff
martin@deb-lab-svr:~$
martin@deb-lab-svr:~$ sudo mv-vm-int a-r2-ge-0.0.3 a-r2-r42-1
Device updated successfully

Connected a-r2-ge-0.0.3 from bridge a-br-default to bridge a-r2-r42-1 and updated a-r2-vfp XML
martin@deb-lab-svr:~$
```

Connecting the `a-r3` interface `ge-0/0/0` from `a-br-default` to `a-r2-r3-1`:
```
martin@deb-lab-svr:~$ sudo mv-vm-int a-r3-ge-0.0.0 a-r2-r3-1
Device updated successfully

Connected a-r3-ge-0.0.0 from bridge a-br-default to bridge a-r2-r3-1 and updated a-r3-vjr XML
martin@deb-lab-svr:~$
martin@deb-lab-svr:~$ ip l sh master a-r2-r3-1
321: a-r2-ge-0.0.2: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue master a-r2-r3-1 state UNKNOWN mode DEFAULT group default qlen 1000
    link/ether fe:54:00:9d:e6:3e brd ff:ff:ff:ff:ff:ff
344: a-r3-ge-0.0.0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue master a-r2-r3-1 state UNKNOWN mode DEFAULT group default qlen 1000
    link/ether fe:54:00:ff:f1:dc brd ff:ff:ff:ff:ff:ff
martin@deb-lab-svr:~$
```

`vJunos-router` is able to configure itself on a first boot from conf file in `vmm-config.tgz` archive stored on an attached USB flash drive with FAT file system. For example, [this proof of concept script](https://github.com/tonusoo/vMX-without-Juniper-orchestration-scripts/blob/main/misc/build-vjunos-routers.bash) creates six `vJunos-routers` named from `a-r10` to `a-r15` with IPv4 address on `fxp0.0` management interface and SSH enabled.

50 millisecond RTT between the `a-r2` and `a-r3` routers was added by the [/etc/libvirt/hooks/qemu](https://github.com/tonusoo/vMX-without-Juniper-orchestration-scripts/blob/main/scripts-and-conf/etc/libvirt/hooks/qemu) libvirt hook script once the `a-r3-vjr` VM was started:
```
martin@deb-lab-svr:~$ sudo tc -d qdisc sh dev a-r3-ge-0.0.0
qdisc netem 816b: root refcnt 2 limit 1000 delay 50ms
martin@deb-lab-svr:~$
```


### Shutting down the vMX and vJunos-Router VMs during the host machine shutdown

During the host machine shutdown, the [`libvirt-guests`](https://www.libvirt.org/manpages/libvirt-guests.html) calls `virsh shutdown` for each virtual machine in order to perform the graceful shutdown of the VM. `virsh shutdown` tries to connect to QEMU Guest Agent(`qemu-ga`) running in VM and sends an `{"execute":"guest-shutdown","arguments":{"mode":"powerdown"}}` call. This is shortly followed by ACPI "Power key pressed short" signal to the virtual machine. As both `vMX` `vCP` and `vFP` do not have the `qemu-ga` installed and there is no daemon like `acpid` or `systemd-logind` to handle the ACPI events, then the `virsh shutdown` has no affect on `vCP` and `vFP` virtual machines. This means that the `libvirt-guests`, by default, waits 5 minutes for each VM as VMs are shutdown one after another and in case of 3 `vMX` routers the host machine shutdown will take over 30 minutes. Taking this into account, a more reasonable configuration for `libvirt-guests` might be, for example, to enable parallel shutdowns up to 20 guests at the same time and 180 seconds wait time for all the VMs in total:
```
martin@deb-lab-svr:~$ sudo sed -i 's/^#PARALLEL_SHUTDOWN=0$/PARALLEL_SHUTDOWN=20/' /etc/default/libvirt-guests
martin@deb-lab-svr:~$ sudo sed -i 's/^#SHUTDOWN_TIMEOUT=300$/SHUTDOWN_TIMEOUT=180/' /etc/default/libvirt-guests
martin@deb-lab-svr:~$
```

The official `vmx.sh --stop` isn't any more graceful and effectively pulls the virtual power cord for each `vCP` and `vFP` by executing `virsh destroy` under the hood. If the graceful shutdown is desired, then a similar [script](https://github.com/tonusoo/vMX-without-Juniper-orchestration-scripts/blob/main/scripts-and-conf/usr/local/bin/shutdown-vmx)(requires `expect` package) could be called [before the `ExecStop=` of libvirt-guests systemd service](https://github.com/tonusoo/vMX-without-Juniper-orchestration-scripts/blob/main/scripts-and-conf/etc/systemd/system/libvirt-guests.service.d/override.conf).

Contrary to `vMX`, the `vJunos-Router` has an `acpid` running which is configured to execute `/sbin/shutdown -h now "Power button pressed"` command once the VM receives the ACPI "Power key pressed short" signal. During the forwarding plane VM shutdown, an `/etc/init.d/junos-vcp` init script with argument "stop" is called which tries to execute `halt -p` in nested control plane VM.

Messages on host machine console after executing `poweroff` in host machine when above-mentioned [shutdown-vmx](https://github.com/tonusoo/vMX-without-Juniper-orchestration-scripts/blob/main/scripts-and-conf/usr/local/bin/shutdown-vmx) script is in use:
![vMX and vJunos-Router shutdown in host machine](https://github.com/tonusoo/vMX-without-Juniper-orchestration-scripts/blob/main/imgs/vMX_and_vJunos-Router_shutdown_in_host_machine.png)


### Various notes related to the project

* Console access to routers can be established using the `virsh console <vm_name>` command. Example:

    ```
    martin@deb-lab-svr:~$ sudo virsh console a-r3-vjr
    Connected to domain 'a-r3-vjr'
    Escape character is ^] (Ctrl + ])


    FreeBSD/amd64 (edge3) (ttyu0)

    login: root
    Password:
    Last login: Wed Oct 23 00:40:33 on ttyu0

    --- JUNOS 23.2R1.15 Kernel 64-bit  JNPR-12.1-20230815.735906f_buil
    root@edge3:~ # cli
    root@edge3>
    martin@deb-lab-svr:~$
    ```


* Qemu monitor access:
    ```
    martin@deb-lab-svr:~$ sudo virsh qemu-monitor-command a-r3-vjr --hmp "info block"
    libvirt-1-format: /home/martin/iasb-class/a-r3/images/vJunos-router-23.2R1.15.qcow2 (qcow2)
        Attached to:      /machine/peripheral/virtio-disk0/virtio-backend
        Cache mode:       writethrough, direct
        Backing file:     /home/martin/iasb-class/vJunos-router/vJunos-router-23.2R1.15.qcow2 (chain depth: 1)


    martin@deb-lab-svr:~$ sudo virsh qemu-monitor-command a-r3-vjr --hmp "info blockstats"
    : rd_bytes=1234886656 wr_bytes=324805120 rd_operations=14835 wr_operations=2057 flush_operations=0 wr_total_time_ns=1377246988817 rd_total_time_ns=53329979260 flush_total_time_ns=0 rd_merged=459 wr_merged=95 idle_time_ns=1767581173


    martin@deb-lab-svr:~$ 
    ```

* Connecting to the Wind River Linux Bash shell and the virtualized line-card uKernel shell from `vCP`, respectively:

    ```
    root@core14> start shell pfe network base-os fpc0
    Last login: Wed Oct 23 00:57:04 UTC 2024 from 128.0.0.4 on pts/0
    root@qemux86-64:~#
    root@qemux86-64:~# pgrep -laf riot
    1447 sh /usr/share/pfe/start_dpdk_riot.sh 0x0BAA
    1468 sh start_riot.sh
    1598 /home/pfe/riot/build/app/riot -c 0x7 -n 2 --log-level=5 -w 03:00.0 -w 04:00.0 -w 05:00.0 -w 06:00.0 -w 07:00.0 -w 08:00.0 -w 09:00.0 -w 0a:00.0 -w 0b:00.0 -w 0c:00.0 -- --rx (0,0,0,1),(1,0,1,1),(2,0,2,1),(3,0,3,1),(4,0,4,1),(5,0,5,1),(6,0,6,1),(7,0,7,1),(8,0,8,1),(9,0,9,1), --tx (0,1),(1,1),(2,1),(3,1),(4,1),(5,1),(6,1),(7,1),(8,1),(9,1), --w 2 --rpio local,3000,3001 --hostif local,3002 --bsz (32,32),(32,32),(32,32)
    root@qemux86-64:~#
    root@qemux86-64:~# logout
    rlogin: connection closed

    root@core14>

    root@core14> start shell pfe network fpc0


    VMX- platform (2800Mhz Intel(R) Atom(TM) CPU processor, 1792MB memory, 8192KB flash)

    VMX-0(core14 vty)# show jspec client

     ID       Name
      1       LUCHIP[0]

    VMX-0(core14 vty)#
    ```


* One can filter up to an application layer on a Linux bridge. As an example, rule below will count and log [BGP route-refresh messages](https://datatracker.ietf.org/doc/html/rfc2918#section-3) traversing the `a-r2-r3-1` bridge:
    ```
    martin@deb-lab-svr:~$ sudo nft -a list ruleset bridge
    table bridge filter { # handle 4
            chain forward { # handle 1
                    type filter hook forward priority 0; policy accept;
                    meta ibrname "a-r2-r3-1" tcp sport . tcp dport . @ih,144,8 { 0-65535 . 179 . 0x5, 179 . 0-65535 . 0x5 } counter packets 42 bytes 4580 log # handle 49
            }
    }
    martin@deb-lab-svr:~$
    ```

    Necessary kernel modules like `nft_meta_bridge` are loaded automatically. Another example, where OSPF version is set to 4 for OSPF packets egressing the `a-r3-ge-0.0.0` TAP interface:
    ```
    martin@deb-lab-svr:~$ sudo nft -a list ruleset bridge
    table bridge filter { # handle 3
            chain forward { # handle 1
                    type filter hook forward priority 0; policy accept;
                    oifname "a-r3-ge-0.0.0" ip protocol ospf @th,0,8 set 0x4 counter packets 3 bytes 240 # handle 20
            }
    }
    martin@deb-lab-svr:~$
    ```
    As expected, Junos will ignore such OSPF packets and log `OSPF packet ignored: invalid version (4) from <neigh_ip>` if OSPF traceoptions are enabled.


* By default, the virtual routers management interfaces have a DHCP client running and depending on the host machine network setup, one might prefer to connect the `fxp0` port directly to physical network with a DHCP server. This can be accomplished with `macvtap` device. For example, instead of `--network bridge="a-br-ext,model=virtio,target=a-r3-vjr-ext"` one can use `--network type="direct,source=enp2s0f1,source_mode=bridge,model=virtio"` which will essentially connect the `fxp0` of `a-r3-vjr` router to the same physical switch port where the host machine physical NIC `enp2s0f1` is connected to.
    ```
    martin@deb-lab-svr:~$ sudo virsh domiflist a-r3-vjr
     Interface       Type     Source         Model    MAC
    ---------------------------------------------------------------------
     macvtap1        direct   enp2s0f1       virtio   52:54:00:c0:3a:64
     a-r3-ge-0.0.0   bridge   a-br-default   virtio   52:54:00:57:be:42
     a-r3-ge-0.0.1   bridge   a-br-default   virtio   52:54:00:c7:83:d7
     a-r3-ge-0.0.2   bridge   a-br-default   virtio   52:54:00:cd:6f:c4
     a-r3-ge-0.0.3   bridge   a-br-default   virtio   52:54:00:93:a1:3e
     a-r3-ge-0.0.4   bridge   a-br-default   virtio   52:54:00:de:f1:7b
     a-r3-ge-0.0.5   bridge   a-br-default   virtio   52:54:00:30:68:9c
     a-r3-ge-0.0.6   bridge   a-br-default   virtio   52:54:00:1f:44:ce
     a-r3-ge-0.0.7   bridge   a-br-default   virtio   52:54:00:e6:55:24
     a-r3-ge-0.0.8   bridge   a-br-default   virtio   52:54:00:dd:5e:68
     a-r3-ge-0.0.9   bridge   a-br-default   virtio   52:54:00:af:f2:0b

    martin@deb-lab-svr:~$
    ```


* NAT can be used to make the virtual routers accessible from outside of the host machine. Relevant configuration snippets from `/etc/nftables.conf`:
    ```
    table inet filter {
    
            chain forward {
                    type filter hook forward priority filter; policy drop
    
                    # net.ipv4.ip_forward is 1. Isolate guests connected to a-br-ext from guests
                    # connected to other bridges.
                    iifname . oifname { "enp2s0f1" . "a-br-ext", "a-br-ext" . "enp2s0f1" } counter accept
    
            }
    
    }
    table ip nat {
    
            chain prerouting {
                    type nat hook prerouting priority dstnat; policy accept;
    
                    iifname "enp2s0f1" ip saddr 192.0.2.0/28 dnat ip to tcp dport map {
                        8123 : 10.5.5.123 . 22, # core14 / a-r1
                        8124 : 10.5.5.124 . 22, # core15 / a-r2
                        8125 : 10.5.5.107 . 22, # edge13 / a-r42
                        8126 : 10.5.5.211 . 22, # edge3 / a-r3
                    }
    
            }
    
            chain postrouting {
                    type nat hook postrouting priority srcnat; policy accept;
    
                    # Connections to guests linked to a-br-ext come from the address configured for
                    # a-br-ext, so no static routes are needed in the guests.
                    # Guests have Internet access.
                    iifname . oifname { "enp2s0f1" . "a-br-ext", "a-br-ext" . "enp2s0f1" } counter masquerade
    
            }
    
    }
    ```


* Host machine spec:
    ```
    CPU: 2x Intel Xeon E5-2680v2 @ 2.80 GHz (Noctua's NH-U12DXi4 cooler)
    MB: Supermicro X9DR3-F
    RAM: 16x mix of Micron MT36JSF2G72PZ-1G9N1KG and Hynix HMT42GR7AFR4C DDR3 SDRAM 16 GiB modules @ 1600 MT/s
    GPU: Nvidia GeForce GTX 970 (MSI GTX 970 GAMING 4G)
    SSD: 2x Kingston SA400S37/960G in Linux software RAID 1
    HDD: 2x Samsung 1TB HD103SJ in Linux software RAID 1
    add-in NIC: Solarflare SFN5161T with 2x 10GBASE-T ports
    add-in NIC: TP-LINK TG-3468 with Realtek 8111/8168 chipset
    ODD: LG WH16NS40
    PSU: Seasonic 850W SSR-850TR
    case: Phanteks Enthoo Pro PH-ES614PC full tower with additional Noctua NF-A14 case fan
    ```
    ![host machine](https://github.com/tonusoo/vMX-without-Juniper-orchestration-scripts/blob/main/imgs/host_machine.jpg)
