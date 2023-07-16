#!/bin/bash

# Make sure PATHs are available to the script (for when run by Cron).
export PATH="/home/manager/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

TARGET=external-backup-pool-1/docker-host-1
TIME="$(date)"

 echo ""
 echo "--------------------------"
 echo "Starting Snapshot & Backup"
 echo "$TIME"
 echo "--------------------------"

 echo ""
 echo "##### Running Local Manual Profile"
 echo ""

 zfs-autobackup local \
                $TARGET \
                --keep-source=1 \
                --keep-target=5 \
                --property-format=manual-backup:{} \
                --no-hold \
                --clear-refreservation \
                --strip-path 1 \
                --set-properties canmount=noauto,readonly=on \
                --progress \
                --verbose
 
 echo ""
 echo "##### Finished Local Manual Profile"
 echo ""
