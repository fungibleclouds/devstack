#!/usr/bin/env bash
# set up zookeeper for devstack


# Keep track of the current devstack directory.
TOP_DIR=$(cd $(dirname "$0")/.. && pwd)

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

if [[ "oneiric" =~ ${DISTRO} ]]; then
    # oneiric has packages for 3.3.3
    OS_PKGS="zookeeper zookeeper-bin zookeeperd python-zookeeper"
    PIPS=pykeeper
elif [[  "f16" =~ ${DISTRO} ]]; then
    # no packages here, build from source
    PIPS=pykeeper
fi

if [[ -n "$OS_PKGS" ]]; then
    install_package $OS_PKGS
fi
if [[ -n "$PIPS" ]]; then
    pip_install $PIPS
fi

