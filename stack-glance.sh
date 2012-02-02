# #!/usr/bin/env bash
# stack-glance.sh - Configure and install Glance for DevStack
#
# Installs Glance API and Registry services

PHASE=${1:-"all"}

# Keep track of the current devstack directory.
TOP_DIR=$(cd $(dirname "$0") && pwd)

# Import common functions and configuration
source $TOP_DIR/functions
source $TOP_DIR/stackrc

# This script exits on an error so that errors don't compound and you see
# only the first error that occured.
set -o errexit

# Print the commands being run so that we can see the command that triggers
# an error.  It is also useful for following allowing as the install occurs.
set -o xtrace

if [[ "all,reset" =~ "$PHASE" ]]; then
    # Delete existing images
    rm -rf $GLANCE_IMAGE_DIR

    # Use local glance directories
    mkdir -p $GLANCE_IMAGE_DIR

    # FIXME(dtroyer): test for mysql
    if [[ "1" == "1" ]]; then
        # Make sure vars are set
        if [[ -z $MYSQL_USER || -z $MYSQL_PASSWORD ]]; then
            echo "MySQL not configured?"
            exit 1
        fi
        # (re)create glance database
        mysql -u$MYSQL_USER -p$MYSQL_PASSWORD -e 'DROP DATABASE IF EXISTS glance;'
        mysql -u$MYSQL_USER -p$MYSQL_PASSWORD -e 'CREATE DATABASE glance;'
    fi
fi

if [[ "all,install" =~ "$PHASE" ]]; then

    if [[ "$ENABLED_SERVICES" =~ "g-api" ||
          "$ENABLED_SERVICES" =~ "n-api" ]]; then
        # image catalog service
        git_clone $GLANCE_REPO $GLANCE_DIR $GLANCE_BRANCH
        cd $GLANCE_DIR; sudo python setup.py develop
    fi

    function glance_config {
        sudo sed -e "
            s,%KEYSTONE_AUTH_HOST%,$KEYSTONE_AUTH_HOST,g;
            s,%KEYSTONE_AUTH_PORT%,$KEYSTONE_AUTH_PORT,g;
            s,%KEYSTONE_AUTH_PROTOCOL%,$KEYSTONE_AUTH_PROTOCOL,g;
            s,%KEYSTONE_SERVICE_HOST%,$KEYSTONE_SERVICE_HOST,g;
            s,%KEYSTONE_SERVICE_PORT%,$KEYSTONE_SERVICE_PORT,g;
            s,%KEYSTONE_SERVICE_PROTOCOL%,$KEYSTONE_SERVICE_PROTOCOL,g;
            s,%SQL_CONN%,$BASE_SQL_CONN/glance,g;
            s,%SERVICE_TOKEN%,$SERVICE_TOKEN,g;
            s,%DEST%,$DEST,g;
            s,%SYSLOG%,$SYSLOG,g;
        " -i $1
    }

    # Copy over our glance configurations and update them
    GLANCE_REGISTRY_CONF=$GLANCE_DIR/etc/glance-registry.conf
    cp $FILES/glance-registry.conf $GLANCE_REGISTRY_CONF
    glance_config $GLANCE_REGISTRY_CONF

    if [[ -e $FILES/glance-registry-paste.ini ]]; then
        GLANCE_REGISTRY_PASTE_INI=$GLANCE_DIR/etc/glance-registry-paste.ini
        cp $FILES/glance-registry-paste.ini $GLANCE_REGISTRY_PASTE_INI
        glance_config $GLANCE_REGISTRY_PASTE_INI
        # During the transition for Glance to the split config files
        # we cat them together to handle both pre- and post-merge
        cat $GLANCE_REGISTRY_PASTE_INI >>$GLANCE_REGISTRY_CONF
    fi

    GLANCE_API_CONF=$GLANCE_DIR/etc/glance-api.conf
    cp $FILES/glance-api.conf $GLANCE_API_CONF
    glance_config $GLANCE_API_CONF

    if [[ -e $FILES/glance-api-paste.ini ]]; then
        GLANCE_API_PASTE_INI=$GLANCE_DIR/etc/glance-api-paste.ini
        cp $FILES/glance-api-paste.ini $GLANCE_API_PASTE_INI
        glance_config $GLANCE_API_PASTE_INI
        # During the transition for Glance to the split config files
        # we cat them together to handle both pre- and post-merge
        cat $GLANCE_API_PASTE_INI >>$GLANCE_API_CONF
    fi

fi

if [[ "all,run" =~ "$PHASE" ]]; then
    # launch the glance registry service
    if [[ "$ENABLED_SERVICES" =~ "g-reg" ]]; then
        run_screen g-reg "cd $GLANCE_DIR; bin/glance-registry --config-file=etc/glance-registry.conf"
    fi

    # launch the glance api and wait for it to answer before continuing
    if [[ "$ENABLED_SERVICES" =~ "g-api" ]]; then
        run_screen g-api "cd $GLANCE_DIR; bin/glance-api --config-file=etc/glance-api.conf"
        echo "Waiting for g-api ($GLANCE_HOSTPORT) to start..."
        if ! timeout $SERVICE_TIMEOUT sh -c "while ! http_proxy= wget -q -O- http://$GLANCE_HOSTPORT; do sleep 1; done"; then
          echo "g-api did not start"
          exit 1
        fi
    fi
fi
