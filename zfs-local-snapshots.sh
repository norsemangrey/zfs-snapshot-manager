#!/bin/bash

# Make sure PATHs are available to the script (for when run by Cron).
export PATH="/home/manager/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

TIME="$(date)"

 echo ""
 echo "-----------------------"
 echo "Starting Local Snapshot"
 echo "$TIME"
 echo "-----------------------"

 echo ""
 echo "##### Running Snapshot Profile"
 echo ""

 zfs-autobackup docker-host-1 \
                --keep-source=1 \
                --property-format=snapshot:{} \
                --snapshot-format %Y-%m-%dT%H:%M:%S \
                --exclude-received \
                --progress \
                --debug \
                --verbose

 echo ""
 echo "##### Finished Snapshot Profile"
 echo ""
