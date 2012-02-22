#!/usr/bin/env bash
# set up zookeeper for devstack

STABLE_SOURCE=http://ftp.wayne.edu/apache//zookeeper/stable/zookeeper-3.3.4.tar.gz

# Keep track of the current devstack directory.
TOP_DIR=$(cd $(dirname "$0")/.. && pwd)

# Print the commands being run so that we can see the command that triggers
# an error.  It is also useful for following allowing as the install occurs.
set -o xtrace

# Import common functions
source $TOP_DIR/functions

GetOSVersion
# Translate the OS version values into common nomenclature
if [[ "$os_VENDOR" == "Ubuntu" ]]; then
    # 'Everyone' refers to Ubuntu releases by the code name adjective
    DISTRO=$os_CODENAME
elif [[ "$os_VENDOR" == "Fedora" ]]; then
    # For Fedora, just use 'f' and the release
    DISTRO="f$os_RELEASE"
else
    # Catch-all for now is Vendor + Release + Update
    DISTRO="$os_VENDOR-$os_RELEASE.$os_UPDATE"
fi

source $TOP_DIR/stackrc

ZOO_DIR=$DEST/zookeeper

# gogetit <url> <destdir> [<filename>]
function gogetit() {
    local URL=$1
    local DESTDIR=$2
    local FILENAME=${URL##*/}
    local FILENAME=${3:-FILENAME}
    if [[ ! -d $DESTDIR ]]; then
        mkdir -p $DESTDIR
    fi
    curl -o $DESTDIR/$FILENAME $URL
}

if [[ "oneiric" =~ ${DISTRO} ]]; then
    # oneiric has packages for 3.3.3
    OS_PKGS="zookeeper zookeeper-bin zookeeperd python-zookeeper"
    PIPS=pykeeper
elif [[  "f16" =~ ${DISTRO} ]]; then
    # no packages here, build from source
    PIPS=pykeeper

    gogetit $STABLE_SOURCE $ZOO_DIR/files
fi

if [[ -n "$OS_PKGS" ]]; then
    install_package $OS_PKGS
fi
if [[ -n "$PIPS" ]]; then
    pip_install $PIPS
fi

