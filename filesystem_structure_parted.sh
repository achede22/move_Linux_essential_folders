#!/bin/bash

## Partition, clone UEFI, LVM Creation, Mount Volumes, Data Move, Change Root.

dumptonewfs(){

# Folder creation
  mkdir /media/oldroot /media/root

# Partitioning of the seccond disk
  parted /dev/xvdf mkpart primary 2048s 4095s
  parted /dev/xvdf --script -- mkpart primary 4096s 25% 
  parted /dev/xvdf --script -- mkpart primary 25% 100% 

# Creation of Physical and Groups Volumes
  pvcreate /dev/xvdf3
  vgcreate vgroot /dev/xvdf3

# Creation of Logical Volumes
  lvcreate -L 20G -n var vgroot 
  lvcreate -L 5G -n var_tmp vgroot 
  lvcreate -L 20G -n var_log vgroot 
  lvcreate -L 5G -n var_log_audit vgroot 
  lvcreate -L 20G -n tmp vgroot 
  lvcreate -l 100%FREE -n home vgroot

# Temporary Dorectories for data migration
  mkdir -p /media/root /media/var /media/var_log /media/var_log_audit /media/var_tmp /media/tmp /media/home 

# Logical Volumes Formating
  mkfs.xfs -f /dev/vgroot/var 
  mkfs.xfs -f /dev/vgroot/var_log
  mkfs.xfs -f /dev/vgroot/var_log_audit
  mkfs.xfs -f /dev/vgroot/var_tmp
  mkfs.xfs -f /dev/vgroot/tmp
  mkfs.xfs -f /dev/vgroot/home 

# Physical Volume Formating, Check and Mount
  mkfs.xfs -f /dev/xvdf2
  xfs_repair /dev/xvdf2 
  mount -o rw,nouuid /dev/xvdf2 /media/root 

# Clone of UEFI Volume
  dd if=/dev/xvda1 of=/dev/xvdf1 bs=1M conv=noerror,sync status=progress

# Data Origin Mount
  mount -o rw,nouuid /dev/xvda2 /media/oldroot

# Data Migration and Syncronization
  xfsdump -J - /media/oldroot | xfsrestore -J - /media/root
  sync

# Final Destination Data Folders
  mount /dev/vgroot/var /media/var
  mount /dev/vgroot/var_log /media/var_log
  mount /dev/vgroot/home /media/home

echo "RESIZE: Copying remaining data"

# Copy /var
  cp -rpZ /media/root/var/* /media/var/
  rm -rf /media/var/log/* /media/var/tmp/* 
  mkdir -p /media/var/log /media/var/tmp /media/var/log/audit 

# Copy /home
  cp -rpZ /media/root/home/* /media/home
  rm -rf /media/root/home/* 

# Copy /var/log
  cp -rpZ /media/root/var/log/* /media/var_log/
  rm -rf /media/var_log/audit/* 

# Re-Increase size for Root
  xfs_growfs /media/root 

# Clean incorrect
  rm -rf /media/root/var/* /media/root/home/* /media/root/tmp/*
  mkdir -p /media/root/var/log/audit /media/root/var/tmp

# Doing remount on proper filesystem structure
  umount /media/var_log 
  umount /media/var 
  umount /media/home 
  mount /dev/vgroot/home /media/root/home
  mount /dev/vgroot/var /media/root/var
  mount /dev/vgroot/var_log /media/root/var/log

# Change Root Path
  chroot /media/root restorecon -R /home
  chroot /media/root restorecon -R /var
  chroot /media/root restorecon -R /var/log
  chroot /media/root restorecon -R /var/tmp
  chroot /media/root restorecon -R /tmp

}


## Set FSTAB Format

set_fstab(){

blkid=$(blkid /dev/xvda2)
VOLUUID=$(echo $blkid | awk -F'"' '{print $2}') 

##To be added

echo "
####################################
##   BEGIN DEFAULT VOLUMEGROUPS   ##  
####################################
UUID=$VOLUUID /                       xfs     defaults        0 0
/dev/mapper/vgroot-var /var xfs defaults 0 0
/dev/mapper/vgroot-var_tmp /var/tmp xfs defaults,nodev,nosuid 0 0
/dev/mapper/vgroot-var_log /var/log xfs defaults 0 0
/dev/mapper/vgroot-var_log_audit /var/log/audit xfs defaults 0 0
/dev/mapper/vgroot-home /home xfs defaults,nodev 0 0
/dev/mapper/vgroot-tmp /tmp xfs defaults,nofail,nodev 0 0
none      /dev/shm        tmpfs   defaults,nosuid,nodev,noexec,size=1G        0 0
#####################################
##    END DEFAULT VOLUMEGROUPS     ##
#####################################" > /media/root/etc/fstab
}


## BEGIN ##
dumptonewfs
set_fstab
