#!/bin/bash

function usage () {
    echo "Usage"
    echo "Usage : sudo `basename $0` [-c|--clone SRC DST]"
    exit 1
}

[ `whoami` = root ] || { sudo "$0" "$@"; exit $?; }

# parsing des arguments
disk_src=""
disk_dst=""
while [ $# -gt 0 ]; do
    case $1 in
        -c|--clone)
            disk_src="${2}"
            disk_dst="${3}"
            shift 3
            ;;
        -*)
            usage
            ;;
    esac
done

if [ -z "${disk_src}" ] || [ -z "${disk_dst}" ]
then
    echo -e "SRC et DST ne peuvent pas être vide.\nSRC : ${disk_src}\nDST: ${disk_dst}"
    usage
fi

if [ ! -b "${disk_src}" ] || [ ! -b "${disk_dst}" ]
then
    echo -e "SRC et DST doivent être des disques.\nSRC : ${disk_src}\nDST: ${disk_dst}"
fi

for i in `mount | grep "${disk_src}" | cut -f1 -d" "`
do
    umount "${i}" 
done
for i in `mount | grep "${disk_dst}" | cut -f1 -d" "`
do
    umount "${i}" 
done

parted -s "${disk_dst}" "mktable msdos"
parted -s "${disk_dst}" "mkpart primary 2048s 41945087s"
parted -s "${disk_dst}" "mkpart primary 41945088s 46138391s"
# parted -s "${disk_dst}" "mkpart primary 46138391s -1"
parted -s "${disk_dst}" "mkpart primary 46138392s 100%"
parted -s "${disk_dst}" "print"
parted -s "${disk_dst}" "unit s" "print"
parted -s "${disk_dst}" "print"

mkfs.ext4 -F "${disk_dst}1"
mkswap -f "${disk_dst}2"
mkfs.ext4 -F  "${disk_dst}3"

dst_racine_uuid="`blkid -o value -s UUID "${disk_dst}1"`"
dst_swap_uuid="`blkid -o value -s UUID "${disk_dst}2"`"
dst_home_uuid="`blkid -o value -s UUID "${disk_dst}3"`"

mkdir -p /mnt/src/{racine,home}
mkdir -p /mnt/dst/{racine,home}

mount "${disk_src}1" "/mnt/src/racine"
mount "${disk_src}3" "/mnt/src/home"

mount "${disk_dst}1" "/mnt/dst/racine"
mount "${disk_dst}3" "/mnt/dst/home"

rsync -aASHX --info=progress2 "/mnt/src/racine/" "/mnt/dst/racine/"
rsync -aASHX --info=progress2 "/mnt/src/home/" "/mnt/dst/home/"

umount "/mnt/src/racine/"
umount "/mnt/src/home/"
umount "/mnt/dst/home/"

mount --bind "/dev/" "/mnt/dst/racine/dev/"
mount --bind "/proc/" "/mnt/dst/racine/proc/"
mount --bind "/sys/" "/mnt/dst/racine/sys/"

sed -i -e "/[[:blank:]]\/[[:blank:]]/ s/UUID=[^[:blank:]]\+/UUID=${dst_racine_uuid}/" "/mnt/dst/racine/etc/fstab"
sed -i -e "/[[:blank:]]swap[[:blank:]]/ s/UUID=[^[:blank:]]\+/UUID=${dst_swap_uuid}/" "/mnt/dst/racine/etc/fstab"
sed -i -e "/[[:blank:]]\/home[[:blank:]]/ s/UUID=[^[:blank:]]\+/UUID=${dst_home_uuid}/" "/mnt/dst/racine/etc/fstab"

chroot "/mnt/dst/racine/" "grub-install" "${disk_dst}"
chroot "/mnt/dst/racine/" "update-grub"

umount "/mnt/dst/racine/dev"
umount "/mnt/dst/racine/proc"
umount "/mnt/dst/racine/sys"
umount "/mnt/dst/racine/"

sync
