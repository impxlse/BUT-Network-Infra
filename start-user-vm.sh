#!/bin/bash
qemu-system-x86_64 -enable-kvm -M q35 -cpu host -smp 8 -m 4G -drive format=raw,file=$HOME/SAE4/vm-user.img -nic socket,model=virtio-net-pci,mac=52:55:55:55:02:02,mcast=225.0.0.2:5555 -display gtk
