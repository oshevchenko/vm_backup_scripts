#!/bin/bash
real_backup_dir="/home/sapukr"
ds=`date +%Y-%m-%d`
hostnamev="$(hostname)"
to=("oleksandrs@sapling-inc.com shevchenko.adb@gmail.com sean@voree.net evgenyr@sapling-inc.com")
fname="/tmp/bkp_out"
fname_subj="/tmp/bkp_subj"
SQL_DB_STATUS="ERROR!"
GITLAB_STATUS="ERROR!"

umount ${real_backup_dir}
mount -a

# check if /home/sapukr is mounted
MOUNT_EXIST=$(mount | grep ${real_backup_dir})
if [ -z "$MOUNT_EXIST" ]; then
    MOUNT_EXIST="ERROR!"
    printf "No network storage available! Do not run /bin/bkp_new.sh!\n\n" >$fname
else
    MOUNT_EXIST="OK!"
    # echo "Subject: [REPORT]: Storage: ${MOUNT_EXIST} Date: $ds on $hostnamev" >$fname
    # printf "\n\n" >>$fname
    printf "Run /home/saplingadmin/vm_backup_scripts/bkp_new.sh!\n\n" >$fname
    /home/saplingadmin/vm_backup_scripts/bkp_new.sh >>$fname 2>&1
    printf "\r\n\r\n" >>$fname
    df -H | grep ubuntu--vg-ubuntu--lv | column -t>> $fname
    printf "\r\n\r\nBR," >>$fname
    printf "\r\n\t$(uname -a)\n" >>$fname

    vm=`virsh list | awk 'NR>2 {print $2}'`
    for activevm in ${vm}
    do
        while read -r disk path; do
            if [[ "$disk" == "sda" && "$path" == "/var/lib/libvirt/images/SQLServer.qcow2" ]]; then
                SQL_DB_STATUS="OK!"
            fi
            if [[ "$disk" == "vda" && "$path" == "/var/lib/libvirt/images/ubuntu20.04.qcow2" ]]; then
                GITLAB_STATUS="OK!"
            fi
        done < <(virsh domblklist "${activevm}" | awk 'NR>2')
    done
fi

echo "Subject: [REPORT]: Storage: ${MOUNT_EXIST} SQLDB: ${SQL_DB_STATUS} GITLAB: ${GITLAB_STATUS} Date: $ds" >$fname_subj
printf "\n\n" >>$fname_subj
# copy the contents of fname to fname_subj
cat $fname >> $fname_subj
for dest in ${to[@]}; do
    /usr/sbin/ssmtp -v ${dest} -F "Sapling Server" < ${fname_subj};
done;

