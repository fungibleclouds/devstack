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


# Determine OS Vendor, Release and Update
# Tested with OS/X, Ubuntu, RedHat, CentOS, Fedora
# Returns results in global variables:
# os_VENDOR - vendor name
# os_RELEASE - release
# os_UPDATE - update
# os_PACKAGE - package type
# os_CODENAME - vendor's codename for release
# GetOSVersion
GetOSVersion() {
    # Figure out which vendor we are
    if [[ -n "`which sw_vers 2>/dev/null`" ]]; then
        # OS/X
        os_VENDOR=`sw_vers -productName`
        os_RELEASE=`sw_vers -productVersion`
        os_UPDATE=${os_RELEASE##*.}
        os_RELEASE=${os_RELEASE%.*}
        os_PACKAGE=""
        if [[ "$os_RELEASE" =~ "10.7" ]]; then
            os_CODENAME="lion"
        elif [[ "$os_RELEASE" =~ "10.6" ]]; then
            os_CODENAME="snow leopard"
        elif [[ "$os_RELEASE" =~ "10.5" ]]; then
            os_CODENAME="leopard"
        elif [[ "$os_RELEASE" =~ "10.4" ]]; then
            os_CODENAME="tiger"
        elif [[ "$os_RELEASE" =~ "10.3" ]]; then
            os_CODENAME="panther"
        else
            os_CODENAME=""
        fi
    elif [[ -x $(which lsb_release) ]]; then
        os_VENDOR=$(lsb_release -i -s)
        os_RELEASE=$(lsb_release -r -s)
        os_UPDATE=""
        if [[ "Debian,Ubuntu" =~ $os_VENDOR ]]; then
            os_PACKAGE="deb"
        else
            os_PACKAGE="rpm"
        fi
        os_CODENAME=$(lsb_release -c -s)
    elif [[ -r /etc/redhat-release ]]; then
        # Red Hat Enterprise Linux Server release 5.5 (Tikanga)
        # CentOS release 5.5 (Final)
        # CentOS Linux release 6.0 (Final)
        # Fedora release 16 (Verne)
        os_CODENAME=""
        for r in "Red Hat" CentOS Fedora; do
            os_VENDOR=$r
            if [[ -n "`grep \"$r\" /etc/redhat-release`" ]]; then
                ver=`sed -e 's/^.* \(.*\) (\(.*\)).*$/\1\|\2/' /etc/redhat-release`
                os_CODENAME=${ver#*|}
                os_RELEASE=${ver%|*}
                os_UPDATE=${os_RELEASE##*.}
                os_RELEASE=${os_RELEASE%.*}
                break
            fi
            os_VENDOR=""
        done
        os_PACKAGE="rpm"
    fi
    export os_VENDOR os_RELEASE os_UPDATE os_PACKAGE os_CODENAME
}


# Distro-agnostic package installer
# install_package package [package ...]
function install_package() {
    if [[ -z "$os_PACKAGE" ]]; then
        GetOSInfo
    fi
    if [[ "$os_PACKAGE" = "deb" ]]; then
        apt_get install "$@"
    else
        yum_install "$@"
    fi
}


# pip install wrapper to set cache and proxy environment variables
# pip_install package [package ...]
function pip_install {
    [[ "$OFFLINE" = "True" ]] && return
    if [[ -z "$os_PACKAGE" ]]; then
        GetOSInfo
    fi
    if [[ "$os_PACKAGE" = "deb" ]]; then
        CMD_PIP=/usr/bin/pip
    else
        CMD_PIP=/usr/bin/pip-python
    fi
    sudo PIP_DOWNLOAD_CACHE=/var/cache/pip \
        HTTP_PROXY=$http_proxy \
        HTTPS_PROXY=$https_proxy \
        $CMD_PIP install --use-mirrors $@
}


# yum wrapper to set arguments correctly
# yum_install package [package ...]
function yum_install() {
    [[ "$OFFLINE" = "True" ]] && return
    local sudo="sudo"
    [[ "$(id -u)" = "0" ]] && sudo="env"
    $sudo http_proxy=$http_proxy https_proxy=$https_proxy \
        yum install -y "$@"
}




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

# Destination path for installation ``DEST``
DEST=${DEST:-/opt/stack}

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
    if [[ ! -r $DESTDIR/$FILENAME ]]; then
        curl -C - -o $DESTDIR/$FILENAME $URL
    fi
}

if [[ "oneiric" =~ ${DISTRO} ]]; then
    # oneiric has packages for 3.3.3
    OS_PKGS="zookeeper zookeeper-bin zookeeperd python-zookeeper"
    PIPS=pykeeper
elif [[  "f16" =~ ${DISTRO} ]]; then
    # no packages here, build from source
    PIPS=pykeeper

    ZOO_SRC_FILE=${STABLE_SOURCE##*/}
    ZOO_RELEASE=${ZOO_SRC_FILE%.tar.gz}
    gogetit $STABLE_SOURCE $ZOO_DIR/files ${ZOO_SRC_FILE}

    mkdir -p $ZOO_DIR/src
    cd $ZOO_DIR/src
    tar xzvf $ZOO_DIR/files/${ZOO_SRC_FILE}
    cd $ZOO_RELEASE

    # Build C bindings
    pushd src/c
    ./configure --prefix=/usr/local
    make
    sudo make install
    sudo ldconfig
    popd

    # Build Python bindings
    pushd contrib/zkpython
    ant install
fi

if [[ -n "$OS_PKGS" ]]; then
    install_package $OS_PKGS
fi
if [[ -n "$PIPS" ]]; then
    pip_install $PIPS
fi

