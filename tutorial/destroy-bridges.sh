#!/bin/bash

# Enable for debugging
# set -x

# Use the system's own implementations if it has any.
if [ -e /etc/init.d/functions ]; then
    . /etc/init.d/functions
elif [ -e /etc/rc.d/init.d/functions ]; then
    . /etc/rc.d/init.d/functions
elif [ -e /lib/lsb/init-functions ]; then
    . /lib/lsb/init-functions
fi

# Implement missing functions (e.g. OpenSUSE lacks 'action').
if type log_success_msg >/dev/null 2>&1; then :; else
    log_success_msg () {
        printf '%s.\n' "$*"
    }
fi
if type log_failure_msg >/dev/null 2>&1; then :; else
    log_failure_msg () {
        printf '%s ... failed!\n' "$*"
    }
fi
if type log_warning_msg >/dev/null 2>&1; then :; else
    log_warning_msg () {
        printf '%s ... (warning).\n' "$*"
    }
fi
if type action >/dev/null 2>&1; then :; else
    action () {
       STRING=$1
       shift
       "$@"
       rc=$?
       if test $rc = 0; then
            log_success_msg "$STRING"
       else
            log_failure_msg "$STRING"
       fi
       return $rc
    }
fi

# Test the message printing functions
#log_success_msg "This is a success message"
#log_failure_msg "This is a failure message"
#log_warning_msg "This is a warning message"
#action "Running a successful action" sleep 1
#action "Running a failing action" false

# Make sure we're running as root
[ "$EUID" -eq 0 ] || exec sudo bash "$0" "$@"

# Add OVS helper scripts to the path
if [ -e /usr/local/bin/ovs-vsctl ]; then
  # Using a locally installed version of OVS
  PATH=$PATH:/usr/local/bin:/usr/local/share/openvswitch/scripts
  log_success_msg "Using locally installed OVS"
  LOCAL=1
elif [ -e /usr/bin/ovs-vsctl ]; then
  # Using a distro installed version of OVS
  PATH=$PATH:/usr/share/openvswitch/scripts
  log_success_msg "Using distro installed OVS"
  LOCAL=0
else
  log_failure_msg "Can't locate OVS scripts"
  exit 1
fi

# Pull-in customizations from the shared file
if [ -f ./vars ]; then
  source ./vars
else
  log_failure_msg "Can't find vars file"
  exit 1
fi

#action "Killing openflow controller (ovs-testcontroller)" \
#  kill -9 `cat /usr/local/var/run/openvswitch/ovs-testcontroller.pid`

for b in "${BRIDGES[@]}"; do
  action "Deleting existing bridge $b" \
    ovs-vsctl --if-exists del-br "$b"
done

# Show the results
log_success_msg "Final OVS bridge configuration"
ovs-vsctl show
