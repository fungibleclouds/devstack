# stack-swift.sh - Configure and install Swift for DevStack
# Installs Swift API

# This script exits on an error so that errors don't compound and you see
# only the first error that occured.
set -o errexit

# Print the commands being run so that we can see the command that triggers
# an error.  It is also useful for following along as the install occurs.
set -o xtrace

# Remove and recreate swift database and local storage
function reset_swift() {
    # We first do a bit of setup by creating the directories and
    # changing the permissions so we can run it as our user.

    USER_GROUP=$(id -g)
    sudo mkdir -p ${SWIFT_DATA_LOCATION}/drives
    sudo chown -R $USER:${USER_GROUP} ${SWIFT_DATA_LOCATION}

    # We then create a loopback disk and format it to XFS.
    # TODO: Reset disks on new pass.
    if [[ ! -e ${SWIFT_DATA_LOCATION}/drives/images/swift.img ]]; then
        mkdir -p  ${SWIFT_DATA_LOCATION}/drives/images
        sudo touch  ${SWIFT_DATA_LOCATION}/drives/images/swift.img
        sudo chown $USER: ${SWIFT_DATA_LOCATION}/drives/images/swift.img

        dd if=/dev/zero of=${SWIFT_DATA_LOCATION}/drives/images/swift.img \
            bs=1024 count=0 seek=${SWIFT_LOOPBACK_DISK_SIZE}
        mkfs.xfs -f -i size=1024  ${SWIFT_DATA_LOCATION}/drives/images/swift.img
    fi
}


# Check out swift, configure for development, process config files
function install_swift() {
    # storage service
    git_clone $SWIFT_REPO $SWIFT_DIR $SWIFT_BRANCH
    cd $SWIFT_DIR; sudo python setup.py develop

    # swift + keystone middleware
    git_clone $SWIFT_KEYSTONE_REPO $SWIFT_KEYSTONE_DIR $SWIFT_KEYSTONE_BRANCH
    cd $SWIFT_KEYSTONE_DIR; sudo python setup.py develop
}

function configure_swift() {
    # Mount the disk with a few mount
    # options to make it most efficient as possible for swift.
    mkdir -p ${SWIFT_DATA_LOCATION}/drives/sdb1
    if ! egrep -q ${SWIFT_DATA_LOCATION}/drives/sdb1 /proc/mounts; then
        sudo mount -t xfs -o loop,noatime,nodiratime,nobarrier,logbufs=8  \
            ${SWIFT_DATA_LOCATION}/drives/images/swift.img ${SWIFT_DATA_LOCATION}/drives/sdb1
    fi

    # We then create link to that mounted location so swift would know
    # where to go.
    for x in {1..4}; do sudo ln -sf ${SWIFT_DATA_LOCATION}/drives/sdb1/$x ${SWIFT_DATA_LOCATION}/$x; done

    # We now have to emulate a few different servers into one we
    # create all the directories needed for swift
    tmpd=""
    for d in ${SWIFT_DATA_LOCATION}/drives/sdb1/{1..4} \
        ${SWIFT_CONFIG_LOCATION}/{object,container,account}-server \
        ${SWIFT_DATA_LOCATION}/{1..4}/node/sdb1 /var/run/swift; do
        [[ -d $d ]] && continue
        sudo install -o ${USER} -g $USER_GROUP -d $d
    done

   # We do want to make sure this is all owned by our user.
   sudo chown -R $USER: ${SWIFT_DATA_LOCATION}/{1..4}/node
   sudo chown -R $USER: ${SWIFT_CONFIG_LOCATION}

   # swift-init has a bug using /etc/swift until bug #885595 is fixed
   # we have to create a link
   sudo ln -sf ${SWIFT_CONFIG_LOCATION} /etc/swift

   # Swift use rsync to syncronize between all the different
   # partitions (which make more sense when you have a multi-node
   # setup) we configure it with our version of rsync.
   sed -e "s/%GROUP%/${USER_GROUP}/;s/%USER%/$USER/;s,%SWIFT_DATA_LOCATION%,$SWIFT_DATA_LOCATION," $FILES/swift/rsyncd.conf | sudo tee /etc/rsyncd.conf
   sudo sed -i '/^RSYNC_ENABLE=false/ { s/false/true/ }' /etc/default/rsync

   # By default Swift will be installed with the tempauth middleware
   # which has some default username and password if you have
   # configured keystone it will checkout the directory.
   if [[ "$ENABLED_SERVICES" =~ "key" ]]; then
       swift_auth_server=keystone

       # We install the memcache server as this is will be used by the
       # middleware to cache the tokens auths for a long this is needed.
       apt_get install memcached

       # We need a special version of bin/swift which understand the
       # OpenStack api 2.0, we download it until this is getting
       # integrated in swift.
       sudo https_proxy=$https_proxy curl -s -o/usr/local/bin/swift \
           'https://review.openstack.org/gitweb?p=openstack/swift.git;a=blob_plain;f=bin/swift;hb=48bfda6e2fdf3886c98bd15649887d54b9a2574e'
   else
       swift_auth_server=tempauth
   fi

   # We do the install of the proxy-server and swift configuration
   # replacing a few directives to match our configuration.
   sed "s,%SWIFT_CONFIG_LOCATION%,${SWIFT_CONFIG_LOCATION},;s/%USER%/$USER/;s/%SERVICE_TOKEN%/${SERVICE_TOKEN}/;s/%AUTH_SERVER%/${swift_auth_server}/" \
       $FILES/swift/proxy-server.conf|sudo tee  ${SWIFT_CONFIG_LOCATION}/proxy-server.conf

   sed -e "s/%SWIFT_HASH%/$SWIFT_HASH/" $FILES/swift/swift.conf > ${SWIFT_CONFIG_LOCATION}/swift.conf

   # We need to generate a object/account/proxy configuration
   # emulating 4 nodes on different ports we have a little function
   # that help us doing that.
   function generate_swift_configuration() {
       local server_type=$1
       local bind_port=$2
       local log_facility=$3
       local node_number

       for node_number in {1..4}; do
           node_path=${SWIFT_DATA_LOCATION}/${node_number}
           sed -e "s,%SWIFT_CONFIG_LOCATION%,${SWIFT_CONFIG_LOCATION},;s,%USER%,$USER,;s,%NODE_PATH%,${node_path},;s,%BIND_PORT%,${bind_port},;s,%LOG_FACILITY%,${log_facility}," \
               $FILES/swift/${server_type}-server.conf > ${SWIFT_CONFIG_LOCATION}/${server_type}-server/${node_number}.conf
           bind_port=$(( ${bind_port} + 10 ))
           log_facility=$(( ${log_facility} + 1 ))
       done
   }
   generate_swift_configuration object 6010 2
   generate_swift_configuration container 6011 2
   generate_swift_configuration account 6012 2


   # We have some specific configuration for swift for rsyslog. See
   # the file /etc/rsyslog.d/10-swift.conf for more info.
   swift_log_dir=${SWIFT_DATA_LOCATION}/logs
   rm -rf ${swift_log_dir}
   mkdir -p ${swift_log_dir}/hourly
   sudo chown -R syslog:adm ${swift_log_dir}
   sed "s,%SWIFT_LOGDIR%,${swift_log_dir}," $FILES/swift/rsyslog.conf | sudo \
       tee /etc/rsyslog.d/10-swift.conf
   sudo restart rsyslog

   # We create two helper scripts :
   #
   # - swift-remakerings
   #   Allow to recreate rings from scratch.
   # - swift-startmain
   #   Restart your full cluster.
   #
   sed -e "s,%SWIFT_CONFIG_LOCATION%,${SWIFT_CONFIG_LOCATION},;s/%SWIFT_PARTITION_POWER_SIZE%/$SWIFT_PARTITION_POWER_SIZE/" $FILES/swift/swift-remakerings | \
       sudo tee /usr/local/bin/swift-remakerings
   sudo install -m755 $FILES/swift/swift-startmain /usr/local/bin/
   sudo chmod +x /usr/local/bin/swift-*
}

# Start swift services
function start_swift() {
   # We then can start rsync.
   sudo /etc/init.d/rsync restart || :

   # Create our ring for the object/container/account.
   /usr/local/bin/swift-remakerings

   # And now we launch swift-startmain to get our cluster running
   # ready to be tested.
   /usr/local/bin/swift-startmain || :

   unset s swift_hash swift_auth_server tmpd
}
