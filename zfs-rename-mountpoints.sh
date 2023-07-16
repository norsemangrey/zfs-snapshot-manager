DATASETS=`zfs list $START | awk '{print $1}'`

for DATASET in $DATASETS; do

 echo Changing mounpoint on [ $DATASET ]
 zfs set muntpoint=/mnt/backup

done
