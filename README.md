# Backup Virtual Machines images using Datto device
## QEMU hypervisor running virtual machines
We have two virtual machines (VM) running in the QEMU hypervisor that we need backup daily.
1. Windows machine which is used for OrCAD CIP database.
2. Ubuntu 20.04 machine running GitLab in the Docker container.

```
$ virsh list
 Id   Name                    State
---------------------------------------
 2    win-sql-server-2019-0   running
 4    gitlab-ce0              running
```
The VM images are located at **/var/lib/libvirt/images/**:
```
# ls -lah /var/lib/libvirt/images/
total 252G
drwx--x--x 2 root         root 4.0K Sep 25 01:25 .
drwxr-xr-x 8 root         root 4.0K Jan  7  2025 ..
-rw-r--r-- 2 libvirt-qemu kvm  207G Sep 25 12:28 SQLServer.qcow2
-rw-r--r-- 2 libvirt-qemu kvm   45G Sep 25 12:28 ubuntu20.04.qcow2
```
## Datto storage
There is a Datto storage with an IP address **192.168.1.148**.
Mount the directory **//192.168.1.148/Sapling-UKR/100** from this device (samba) to local directory **/home/sapukr** and put the tarball containing two *.qcow2* VMs images into this directory.
After that it is the Datto's job to process this tarball and save it.
We do it on a daily basis.
```
# cat /etc/fstab 
...
//192.168.1.148/Sapling-UKR/100 /home/sapukr cifs username=Saplingadmin,password=**************,_netdev,sec=ntlmv2i,vers=3.0 0  0
# ls -la /home/sapukr/
total 262353988
drwxr-xr-x 2 root root            0 Mar  1  2025 .
drwxr-xr-x 9 root root         4096 Jul 31 20:29 ..
-rwxr-xr-x 1 root root 268650444800 Sep 25 01:24 sap-lin-15.tar
```

## Crontab based daily backup
Run the script that prepares the tarball and send it to Datto device daily except weekend using crontab.
```
#crontab -e
1 0 * * 2-6 /home/saplingadmin/vm_backup_scripts/sbkp.sh >/dev/null 2>&1
```

## Backup the VMs and prepare the tarball
The following directories/files are created:
```
/root/bkps/gitlab-ce0/
/root/bkps/gitlab-ce0/ubuntu20.04.qcow2 <- a hard link to /var/lib/libvirt/images/ubuntu20.04.qcow2
/root/bkps/gitlab-ce0/gitlab-ce0.xml
/root/bkps/win-sql-server-2019-0/
/root/bkps/win-sql-server-2019-0/SQLServer.qcow2 <- a hard link to /var/lib/libvirt/images/SQLServer.qcow2
/root/bkps/win-sql-server-2019-0/win-sql-server-2019-0.xml
```
*.xml* files are created using the following commands:
```
virsh dumpxml gitlab-ce0
virsh dumpxml win-sql-server-2019-0
```
The snapshots are created, and simultaneously the VM is switched to those snapshots (temporary until the backup process is finished)
```
virsh snapshot-create-as --domain gitlab-ce0 snapshot-last --disk-only --atomic --quiesce --no-metadata
virsh snapshot-create-as --domain win-sql-server-2019-0 snapshot-last --disk-only --atomic --quiesce --no-metadata
```
The VMs are now running from the snapshots:
```
/var/lib/libvirt/images/ubuntu20.04.snapshot-last
/var/lib/libvirt/images/SQLServer.snapshot-last
```
Now put the *ubuntu20.04.qcow2* and *SQLServer.qcow2* into the tarball.  
Hard link /root/bkps/gitlab-ce0/ubuntu20.04.qcow2 to /var/lib/libvirt/images/ubuntu20.04.qcow2  
Hard link /root/bkps/win-sql-server-2019-0/SQLServer.qcow2 to /var/lib/libvirt/images/SQLServer.qcow2  
```
ln /var/lib/libvirt/images/SQLServer.qcow2 /root/bkps/win-sql-server-2019-0/SQLServer.qcow2
ln /var/lib/libvirt/images/ubuntu20.04.qcow2 /root/bkps/gitlab-ce0/ubuntu20.04.qcow2
```
Create the tarball:
```
tar -cvf /root/sap-lin-15.tar -C /root/bkps .
./
./gitlab-ce0/
./gitlab-ce0/ubuntu20.04.qcow2
./gitlab-ce0/gitlab-ce0.xml
./win-sql-server-2019-0/
./win-sql-server-2019-0/SQLServer.qcow2
./win-sql-server-2019-0/win-sql-server-2019-0.xml
```
Send the tarball to Datto device
```
cp -f /root/sap-lin-15.tar /home/sapukr
```
List of files in archive:
```
tar -tvf /home/sapukr/sap-lin-15.tar
drwxr-xr-x root/root         0 2025-09-25 00:01 ./
drwxr-xr-x root/root         0 2025-09-25 00:01 ./gitlab-ce0/
-rw-r--r-- libvirt-qemu/kvm 47017885696 2025-09-25 00:01 ./gitlab-ce0/ubuntu20.04.qcow2
-rw-r--r-- root/root               8564 2025-09-25 00:01 ./gitlab-ce0/gitlab-ce0.xml
drwxr-xr-x root/root                  0 2025-09-25 00:01 ./win-sql-server-2019-0/
-rw-r--r-- libvirt-qemu/kvm 221632528384 2025-09-25 00:01 ./win-sql-server-2019-0/SQLServer.qcow2
-rw-r--r-- root/root                7580 2025-09-25 00:01 ./win-sql-server-2019-0/win-sql-server-2019-0.xml
```
Switch VM back from snapshot
```
virsh blockcommit win-sql-server-2019-0 sda --active --verbose --pivot
virsh blockcommit gitlab-ce0 vda --active --verbose --pivot
```
Merge the snapshot into the parent image.
```
rm -rf /var/lib/libvirt/images/ubuntu20.04.snapshot-last
rm -rf /var/lib/libvirt/images/SQLServer.snapshot-last

```



## Restore from error "cannot acquire state change lock (held by monitor=remoteDispatchDomainBlockJobAbort)".
- Sometimes the virtual machine could not be restarted or stopped and the following error is reported:
```
$ virsh destroy win-sql-server-2019-0
error: Failed to destroy domain win-sql-server-2019-0
error: Timed out during operation: cannot acquire state change lock
(held by monitor=remoteDispatchDomainBlockJobAbort)
```
- To exit this state restart libvirtd


```
sudo su
[sudo] password for saplingadmin: 
root@sap-lin-15:/home/saplingadmin# systemctl restart libvirtd
```
- Restart the VMs.
- Check the output of the command virsh domblklist:


```
# virsh list
 Id   Name                    State
---------------------------------------
 17   win-sql-server-2019-0   running
 18   gitlab-ce0              running
# virsh domblklist win-sql-server-2019-0 | awk 'NR>2'
 sda      /var/lib/libvirt/images/SQLServer.snapshot-last
```
- If the name ends with .snapshot-last  we should do the blockcommit operation to go back to SQLServer.qcow2 instead of snapshot. Otherwise the following updates will not work.

```
# virsh blockcommit win-sql-server-2019-0 sda --active --verbose --pivot
Block commit: [100 %]
Successfully pivoted
root@sap-lin-15:/home/saplingadmin# virsh domblklist win-sql-server-2019-0 | awk 'NR>2'
 sda      /var/lib/libvirt/images/SQLServer.qcow2
```
Same for gitlab-ce0:
```
# virsh domblklist gitlab-ce0  | awk 'NR>2'
 vda      /var/lib/libvirt/images/ubuntu20.04.snapshot-last
# virsh blockcommit gitlab-ce0 vda --active --verbose --pivot
Block commit: [100 %]
Successfully pivoted

# virsh domblklist gitlab-ce0  | awk 'NR>2'
 vda      /var/lib/libvirt/images/ubuntu20.04.qcow2
```
## Restore backup
The message from IT guys looks like this:
```
Hi Oleksandr,
It seems the CIP server SQL database has gotten corrupted.
After working with OrCAD support they are suggesting to restore the VM to the state it was on 4/23.
I restored the snapshot file from the datto on 4/23 at 6pm. You can access it here:
\\192.168.1.104\Sapling-UKR-18-00-02-Apr-23-25
Please let me know if you have any questions.
Kind Regards,
```

- Stop backups schedule:
```
crontab -e
```
- Comment out:
```
#1 0 * * * /bin/sbkp.sh >/dev/null 2>&1 
#0 * * * * /bin/checkmount.sh >/dev/null 2>&1
```
- Modify /etc/fstab

```
//192.168.1.104/Sapling-UKR-18-00-02-Apr-23-25 /mnt/Sapling-UKR-18-00-02-Apr-23-25 cifs username=Saplingadmin,password=**********,_netdev,sec=ntlmv2i 0  0
```
- Mount
```
mount -a
```
- Remove tarball:
```
rm -rf /root/sap-lin-15.tar
rm -rf /root/bkps/*
```
- Copy file:
```
nohup rsync --progress /mnt/Sapling-UKR-18-00-02-Apr-23-25/100/sap-lin-15.tar /root/bkps/ > /root/bkps/copy.log 2>&1 &
```
- Check copy progress:
```
tail -f /root/bkps/copy.log
```
- Shut down VM and remove the VM image:
```
virsh list
virsh shutdown win-sql-server-2019-0
rm /var/lib/libvirt/images/SQLServer.qcow2
```
- Check the content:
```
# tar tvf sap-lin-15.tar
drwxr-xr-x root/root         0 2025-04-23 00:01 ./
drwxr-xr-x root/root         0 2025-04-23 00:01 ./gitlab-ce0/
-rw-r--r-- libvirt-qemu/kvm 314638204928 2025-04-23 00:01 ./gitlab-ce0/ubuntu20.04.qcow2
-rw-r--r-- root/root                8566 2025-04-23 00:01 ./gitlab-ce0/gitlab-ce0.xml
drwxr-xr-x root/root                   0 2025-04-23 00:01 ./win-sql-server-2019-0/
-rw------- libvirt-qemu/kvm 204336726016 2025-04-23 00:01 ./win-sql-server-2019-0/SQLServer.qcow2
-rw-r--r-- root/root                7582 2025-04-23 00:01 ./win-sql-server-2019-0/win-sql-server-2019-0.xml
```
- Un-tar the .qcow2 and .xml files:
```
nohup tar -xvf sap-lin-15.tar ./win-sql-server-2019-0/win-sql-server-2019-0.xml ./win-sql-server-2019-0/SQLServer.qcow2 > /root/bkps/untar.log 2>&1 &
tail -f /root/bkps/untar.log
```
- Move the VM image:
```
mv ./win-sql-server-2019-0/SQLServer.qcow2 /var/lib/libvirt/images/SQLServer.qcow2
```
- Set correct permissions and ownership:
```
chown libvirt-qemu:kvm /var/lib/libvirt/images/SQLServer.qcow2
chmod 644 /var/lib/libvirt/images/SQLServer.qcow2
```
- Restore the VM Definition from the .xml file. The .xml file defines the VM's configuration (CPU, RAM, disk, NIC, etc.). Use virsh to define the VM from this file. This command registers the VM with libvirt using the settings in the .xml file without starting it.
```
virsh define ./win-sql-server-2019-0/win-sql-server-2019-0.xml
```
- Verify the VM is registered. You should see win-sql-server-2019-0 (or the name given in the XML file) listed.


```
virsh list --all
 Id   Name                    State
----------------------------------------
 2    gitlab-ce0              running
 -    win-sql-server-2019-0   shut off
```
- Finally, start the VM:
```
virsh start win-sql-server-2019-0
```
## Resize QCOW2 image
- Go to respective directory:

```
# cd /var/lib/libvirt/images
```
- Stop the VM: 

```
# virsh list
 Id   Name                    State
---------------------------------------
 2    win-sql-server-2019-0   running
 3    gitlab-ce0              running
# virsh shutdown gitlab-ce0
Domain gitlab-ce0 is being shutdown
```
- Check image info:
```
# qemu-img info ubuntu20.04.qcow2 
image: ubuntu20.04.qcow2
file format: qcow2
virtual size: 612 GiB (657129996800 bytes)
disk size: 130 GiB
cluster_size: 65536
Format specific information:
    compat: 1.1
    lazy refcounts: true
    refcount bits: 16
    corrupt: false


# virt-df -h  ubuntu20.04.qcow2
Filesystem                                Size       Used  Available  Use%
ubuntu20.04.qcow2:/dev/sda1               511M       4.0K       511M    1%
ubuntu20.04.qcow2:/dev/sda5               601G        39G       536G    7%
```
- Shrink the image:
```
nohup virt-sparsify  ubuntu20.04.qcow2 ubuntu20.04_shrink.qcow2 > /tmp/virt-sparsify.log 2>&1 &
tail -f /tmp/virt-sparsify.log
# 
[   0.0] Create overlay file in /tmp to protect source disk
[   0.1] Examine source disk
[   2.3] Fill free space in /dev/sda1 with zero
[   3.4] Fill free space in /dev/sda5 with zero
 100% ⟦▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒⟧ 00:00
[3382.0] Copy to destination and make sparse
```
