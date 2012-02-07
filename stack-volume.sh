# stack-volume.sh - Configure and install Nova's volume service
#

# This script exits on an error so that errors don't compound and you see
# only the first error that occured.
set -o errexit

# Print the commands being run so that we can see the command that triggers
# an error.  It is also useful for following along as the install occurs.
set -o xtrace

# Name of the lvm volume group to use/create for iscsi volumes
VOLUME_GROUP=${VOLUME_GROUP:-nova-volumes}
VOLUME_NAME_PREFIX=${VOLUME_NAME_PREFIX:-volume-}
INSTANCE_NAME_PREFIX=${INSTANCE_NAME_PREFIX:-instance-}

# Configure a default volume group called 'nova-volumes' for the nova-volume
# service if it does not yet exist.  If you don't wish to use a file backed
# volume group, create your own volume group called 'nova-volumes' before
# invoking stack.sh.
#
# By default, the backing file is 2G in size, and is stored in /opt/stack.

function reset_volume() {
    if ! sudo vgs $VOLUME_GROUP; then
        VOLUME_BACKING_FILE=${VOLUME_BACKING_FILE:-$DEST/nova-volumes-backing-file}
        VOLUME_BACKING_FILE_SIZE=${VOLUME_BACKING_FILE_SIZE:-2052M}
        # Only create if the file doesn't already exists
        [[ -f $VOLUME_BACKING_FILE ]] || truncate -s $VOLUME_BACKING_FILE_SIZE $VOLUME_BACKING_FILE
        DEV=`sudo losetup -f --show $VOLUME_BACKING_FILE`
        # Only create if the loopback device doesn't contain $VOLUME_GROUP
        if ! sudo vgs $VOLUME_GROUP; then sudo vgcreate $VOLUME_GROUP $DEV; fi
    fi

    if sudo vgs $VOLUME_GROUP; then
        # Remove nova iscsi targets
        sudo tgtadm --op show --mode target | grep $VOLUME_NAME_PREFIX | grep Target | cut -f3 -d ' ' | sudo xargs -n1 tgt-admin --delete || true
        # Clean out existing volumes
        for lv in `sudo lvs --noheadings -o lv_name $VOLUME_GROUP`; do
            # VOLUME_NAME_PREFIX prefixes the LVs we want
            if [[ "${lv#$VOLUME_NAME_PREFIX}" != "$lv" ]]; then
                sudo lvremove -f $VOLUME_GROUP/$lv
            fi
        done
    fi
}

function install_volume() {
    echo "Not implemented"
}

function configure_volume() {
    echo "Not implemented"
}

function start_volume() {
    # tgt in oneiric doesn't restart properly if tgtd isn't running
    # do it in two steps
    sudo stop tgt || true
    sudo start tgt

    run_screen n-vol "cd $NOVA_DIR && $NOVA_DIR/bin/nova-volume"
}
