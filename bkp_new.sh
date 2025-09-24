#!/bin/bash
set -x
#set -e
tar_dir=/root
backup_dir=${tar_dir}/bkps
real_backup_dir=/home/sapukr
backup_archive_name=$(hostname).tar
backup_archive_path=${tar_dir}/${backup_archive_name}

mkdir -p ${backup_dir}
rm -rf ${backup_dir}/*
rm -rf ${backup_archive_path}

create_and_copy_tarball() {
	printf "\n"
	echo "Archiving ${backup_dir} into ${backup_archive_path}"
	# cd ${backup_dir}
	tar -cvf ${backup_archive_path} -C ${backup_dir} .
	echo "Copy ${backup_archive_path} into ${real_backup_dir}"
	cp -f ${backup_archive_path} ${real_backup_dir}
	sync
	printf "Clean up: delete ${backup_dir}/* ${backup_archive_path}..."
	printf "\n"
	dmesg | tail -n 20
	printf "\n\nList of files in archive:\n"
	tar -tvf ${real_backup_dir}/${backup_archive_name}

}
vm=`virsh list | awk 'NR>2 {print $2}'`
for activevm in ${vm}
do
	echo "Working with ${activevm}"
	echo "Creating dir ${backup_dir}/${activevm}"
	mkdir -p ${backup_dir}/${activevm}
	virsh dumpxml ${activevm} > ${backup_dir}/${activevm}/${activevm}.xml
	disk_path=`virsh domblklist ${activevm} | awk 'NR>2 {print $2}'`

	for path in ${disk_path}
	do
		if [[ "${path}" =~ \.qcow2$ ]]; then
			snapshot_file="${path%.*}.snapshot-last"
			rm -f "${snapshot_file}"
		fi
	done

	virsh snapshot-create-as --domain ${activevm} snapshot-last --disk-only --atomic --quiesce --no-metadata
	for path in ${disk_path}
	do
		if [[ "${path}" =~ \.qcow2$ ]]; then
			filename=`basename ${path}`
			echo "Hard link ${backup_dir}/${activevm}/${filename} to ${path}"
			ln ${path} ${backup_dir}/${activevm}/${filename}
			sync
		else
			echo "Invalid VM path:${path}!"
		fi
	done
	printf "\n"
done

create_and_copy_tarball

vm=`virsh list | awk 'NR>2 {print $2}'`
for activevm in ${vm}
do
	while read -r disk path; do
		# Skip header lines and ensure disk is not empty
		if [[ -n "${disk}" ]]; then
			if [[ "${path}" =~ \.snapshot-last$ ]]; then
				virsh blockcommit ${activevm} ${disk} --active --verbose --pivot
				if [[ $? -eq 0 ]]; then
					echo "Blockcommit completed successfully, remove snapshot"
					echo "rm -rf ${path}"
					rm -rf ${path}
					sync
					printf "\n\n"
				else
					echo "Blockcommit failed with an error."
				fi
			else
				echo "Invalid VM path:${path}!"
			fi
		fi
	done < <(virsh domblklist "${activevm}" | awk 'NR>2')
done
#sleep 3
#rsync --ignore-times --delete -a -P -r -v -e ssh ${backup_dir}/ dmytrof@192.168.1.102:/backup

