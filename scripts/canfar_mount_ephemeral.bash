#!/bin/bash

EXEC_NAME=$(basename $0 .${0##*.})
EXEC_VERSION=0.1_beta
OLDMOUNTPOINT="/mnt"
NEWMOUNTPOINT="/ephemeral"

msg() {
    echo " >> ${EXEC_NAME}: $1"
}

die() {
    echo "${EXEC_NAME}: $1" 1>&2
    exit 1
}

grep -q ephemeral /etc/mtab && msg "$NEWMOUNTPOINT already mounted" && exit 0
umount $OLDMOUNTPOINT >& /dev/null || msg "Could not unmount $OLDMOUNTPOINT"
mkdir -p $NEWMOUNTPOINT >& /dev/null || msg "Could not create new mountpoint $NEWMOUNTPOINT"
sed -i 's/\/mnt/\/ephemeral/g' /etc/fstab >& /dev/null || msg "Could not modify /etc/fstab"
mount $NEWMOUNTPOINT >& /dev/null || die "Could not mount $NEWMOUNTPOINT"
chmod 777 $NEWMOUNTPOINT || msg "Could not set $NEWMOUNTPOINT permissions"

msg "Ephemeral partition mounted at $NEWMOUNTPOINT"
