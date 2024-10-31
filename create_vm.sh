#!/bin/bash
# Script to test kickstart script by kvm + libvirt

virsh destroy openstack-aio
virsh undefine openstack-aio
if [ -e /var/lib/libvirt/images/openstack-aio.qcow2 ]; then
  rm /var/lib/libvirt/images/openstack-aio.qcow2
fi

virt-install \
    --name=openstack-aio \
    --ram=8196 \
    --arch=x86_64 \
    --cpu=host-passthrough \
    --vcpus=4 \
    --osinfo=centos-stream9 \
    --initrd-inject="openstack-aio-ks.cfg" \
    --extra-args="inst.ks=file:/openstack-aio-ks.cfg console=tty0 console=ttyS0,115200" \
    --disk="/var/lib/libvirt/images/openstack-aio.qcow2,size=20,sparse=true,format=qcow2" \
    --location="https://odcs.stream.centos.org/production/latest-CentOS-Stream/compose/BaseOS/x86_64/os" \
    --network=default \
    --serial=pty \
    --nographics

