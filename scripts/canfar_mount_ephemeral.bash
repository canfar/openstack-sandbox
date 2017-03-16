#!/bin/bash

EXEC_NAME=$(basename $0 .${0##*.})
EXEC_VERSION=0.1
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
umount $OLDMOUNTPOINT >& /dev/null
mkdir -p $NEWMOUNTPOINT >& /dev/null
sed -i -e 's/\/mnt/\/ephemeral/g' /etc/fstab >& /dev/null
mount $NEWMOUNTPOINT >& /dev/null || die "Could not mount $NEWMOUNTPOINT"
chmod 777 $NEWMOUNTPOINT || msg "Could not set $NEWMOUNTPOINT permissions"

msg "Ephemeral partition mounted at $NEWMOUNTPOINT"
