#!/bin/bash


# Server side
apt update

apt install nfs-kernel-server


if grep -E "^/home" /etc/fstab; then
    sed -i "s~^/home~/home *(rw,sync,root_squash,no_subtree_check,sec=krb5p)" /etc/fstab
else
    echo "/home *(rw,sync,root_squash,no_subtree_check,sec=krb5p)" >> /etc/exports
fi

exportfs -arv
systemctl restart nfs-server.service



