#!/usr/bin/env bash

# Proof of concept script which creates 6 pre-configured vJunos-routers.

set -e

PATH="$PATH:/usr/sbin"

genconf() {

	# Router names are expected to follow the a-r11, b-ce21, k-pe8, etc naming convention.
	id="${name//[^0-9]}"

	[[ "$id" =~ ^[0-9]+$ ]] || { echo "$name does not have an integer <id> suffix" >&2; exit 1; }
	# 10.5.5.1 is gateway
	(( id >= 2 && id <= 254 )) || { echo "$id in $name is not between 2 - 254" >&2; exit 1; }

	cat <<- EOF
		system {
		    host-name $name;
		    root-authentication {
		        encrypted-password "$passwd_hash";
		    }
		    services {
		        ssh {
		            root-login allow;
		        }
		    }
		    syslog {
		        file interactive-commands {
		            interactive-commands any;
		        }
		        file messages {
		            any notice;
		            authorization info;
		        }
		    }
		}
		chassis {
		    fpc 0 {
		        lite-mode;
		    }
		}
		interfaces {
		    fxp0 {
		        unit 0 {
		            family inet {
		                address 10.5.5.$id/24;
		            }
		        }
		    }
		}
	EOF
}


passwd_hash=$(openssl passwd -6 -stdin <<< "root")

mkdir -v ~/jnpr-lab/
cp -v /media/storage/juniper_images/vJunos-router-23.2R1.15.qcow2 ~/jnpr-lab/


for name in a-r{10..15}; do

	mkdir -v ~/jnpr-lab/"$name"

	staging=$(mktemp -d /tmp/"${0##*/}".XXXXXXXX)
	mkdir -v "$staging/config"

	genconf > "$staging/config/juniper.conf"

	qemu-img create -q -f raw ~/jnpr-lab/"$name"/conf-disk.raw 1M
	mkfs.vfat -n "vmm-data" ~/jnpr-lab/"$name"/conf-disk.raw

	mntdir=$(mktemp -d /tmp/"${0##*/}".XXXXXXXX)
	sudo mount ~/jnpr-lab/"$name"/conf-disk.raw "$mntdir"

	sudo tar czf "$mntdir"/vmm-config.tgz -C "$staging" .

	sudo umount -f -q "$mntdir"
	rm -rfv "$staging" "$mntdir"

	echo

	qemu-img create -F qcow2 -b ~/jnpr-lab/vJunos-router-23.2R1.15.qcow2 \
		-f qcow2 ~/jnpr-lab/"$name"/vJunos-router-23.2R1.15.qcow2

	sudo virt-install --osinfo linux2022 \
		--name "$name-vjr" \
		--events on_crash=restart \
		--memory 5120 \
		--vcpus 4 \
		--import \
		--disk ~/jnpr-lab/"$name"/vJunos-router-23.2R1.15.qcow2,cache=directsync,bus=virtio \
		--disk ~/jnpr-lab/"$name"/conf-disk.raw,cache=directsync,bus=usb \
		--network bridge="a-br-ext,model=virtio,target=$name-vjr-ext" \
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
		--qemu-commandline="-smbios type=1,product=VM-VMX,family=lab" \
		--graphics none \
		--noautoconsole

	sudo virsh desc "$name-vjr" --title "vJunos-Router; Junos 23.2R1.15" --live --config
	sudo virsh autostart "$name-vjr"

done
