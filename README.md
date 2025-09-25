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
Remove the snapshots
```
rm -rf /var/lib/libvirt/images/ubuntu20.04.snapshot-last
rm -rf /var/lib/libvirt/images/SQLServer.snapshot-last

```
