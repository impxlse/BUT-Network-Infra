#!/bin/bash


script_location="$(readlink -f "$0")"
source "$(dirname "$script_location")/network-structure.sh" # Contains arrays of network interfaces & VMs

qemu_options="-enable-kvm -M q35 -cpu host -smp $(nproc) -m 2G -display none" # Qemu shared launch options
tap_ifname="tap231" # TAP interface name for the router to communicate with the exterior



# Function to start the router VM if it exists
function start_router {
    img_name="$(echo "$router_ifaces" | cut -d ';' -f 1)" # Gets the name of the image file
    if [[ -e "$img_path/$img_name" ]]; then
        if [[ $(ps x | grep -c "$img_path/$img_name") -gt 1 ]]; then
            echo "router already running, skipping."
        else
            # If the router file image exists and is not already running,
            # build the network interfaces options & start it.
            echo "Starting router ($img_name) with tap interface $tap_ifname:"
            nic="-nic tap,ifname=$tap_ifname,model=virtio-net-pci,script=no,downscript=no"
            
            for network_id in "${!router_ifaces[@]}"; do # Interfaces for the subnets
                mac_addr="$(echo "${router_ifaces[$network_id]}" | cut -d ';' -f 3)"
                mcast="$(echo "${networks[$network_id]}" | cut -d ';' -f 7)"

                nic="$nic -nic socket,model=virtio-net-pci,mac=$mac_addr,mcast=$mcast"
                echo "- Interface for network $network_id: MAC=$mac_addr, MULTICAST=$mcast"
            done
            
            qemu-system-x86_64 $qemu_options \
            -drive file="$img_path/$img_name",format=raw \
            $nic &
        fi
    fi
}



function start_vms {
    for key in "${!vms[@]}"; do
        value="${vms[$key]}"
        img_name="$(echo "$value" | cut -d ';' -f 1)"
        mac_addr="$(echo "$value" | cut -d ';' -f 3)"
        network_id="$(echo "$value" | cut -d ';' -f 4)" # Id of the subnet
        mcast="$(echo "${networks[$network_id]}" | cut -d ';' -f 7)" # Multicast address used for the subnet
        
        if [[ -e "$img_path/$img_name" ]]; then
            if [[ $(ps x | grep -c "$img_path/$img_name") -gt 1 ]]; then
               echo "$key already running, skipping."
            else
               echo "Starting $key ($img_name) with MAC=$mac_addr, NETWORK_ID=$network_id, MULTICAST=$mcast."
        
               qemu-system-x86_64 $qemu_options \
               -drive file="$img_path/$img_name",format=raw \
               -nic socket,model=virtio-net-pci,mac="$mac_addr",mcast="$mcast" &
            fi
        fi
  done
}



echo "QEMU options: $qemu_options"
echo "Images path: $img_path"

start_router
start_vms
