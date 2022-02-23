#!/bin/bash

# Enable for debugging
# set -x

## --------------- ##
## Local Functions ##
## --------------- ##

## ------------- ##
## LSB functions ##
## ------------- ##

## Use the system's own implementations if it has any.
#if [ -e /etc/init.d/functions ]; then
#    . /etc/init.d/functions
#elif [ -e /etc/rc.d/init.d/functions ]; then
#    . /etc/rc.d/init.d/functions
#elif [ -e /lib/lsb/init-functions ]; then
#    . /lib/lsb/init-functions
#fi

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

# We expect to be running in the OVN sandbox environment here,
# patches for OVS and OVN tools are already setup.

# Pull-in customizations from the shared variables file
if [ -f ./vars ]; then
  source ./vars
else
  log_failure_msg "Can't find vars file at $PWD/vars"
  exit 1
fi

# ToDo: Reconsider using global variables here
RANDOM_MACS=()
UNIQUE_MACS=()
MAC_PREFIX="00:10:18"
#
# Generate an array of random MAC addresses.
#
gen_macs() {
  local mac_count=$1
  # ToDo: Find a better solution for avoiding address collisions
  for (( i = 1; i <= $mac_count + 5; i++ )); do
    RANDOM_MACS[$i]="$(printf '%s:%02X:%02X:%02X' $MAC_PREFIX $[RANDOM%256] $[RANDOM%256] $[RANDOM%256])"
  done
  UNIQUE_MACS=( $(echo ${RANDOM_MACS[@]} | tr [:space:] '\n' | awk '!a[$0]++'))

  # ToDo: Fix the problem instead of just reporting an error
  if [ "${#UNIQUE_MACS[@]}" -lt "$mac_count" ]; then
    log_failure_msg "Failed to generate $mac_count random MAC addresses"
    exit 1
  fi

  # Trim extra elements at the end of the array
  UNIQUE_MACS=( "${UNIQUE_MACS[@]::$mac_count}" )

  # print the results
  # echo "${UNIQUE_MACS[@]}"
}

IPS=()
#
# Generate an array of IPv4 addresses.
#
gen_ips() {
  local cidr="$1" ; local lo hi a b c d e f g h

  # range is bounded by network (-n) & broadcast (-b) addresses.
  lo=$(ipcalc -n "$cidr" | cut -f2 -d=)
  hi=$(ipcalc -b "$cidr" | cut -f2 -d=)

  IFS=. read -r a b c d <<< "$lo"
  IFS=. read -r e f g h <<< "$hi"

  # Generate array of addresses
  IPS=( $(eval "echo {$a..$e}.{$b..$f}.{$c..$g}.{$d..$h}") )

  # Strip the IP subnet network address from the front of the array
  IPS=("${IPS[@]:1}")

  # Strip the IP subnet broadcast address from the end of the array
  unset IPS[-1]

  # By convention, we use the first element of the array as the gateway

  # Print the results
  # echo "${IPS[*]}"
}

# Test gen_ips() function
#IP_PREFIX="192.168"
#for (( i = 0; i < 10; i++ )); do
#  gen_ips "$IP_PREFIX.$i.0/27"
#done

# ToDo: Error checking here
# MAX_LOGICAL_SWITCHES <= 256 (Using 192.168.X as address space)
# MAX_PORTS_PER_LOGICAL_SWTICH <= 253 (Using /24 subnet, GW is used by router)

##############################################################################
# We expect to be running in the OVN sandbox environment here.
# The OVS switch is already present and the ovn-north/south 
# daemons are already running
##############################################################################

# ToDo: Run some tests to check that OVN sandbox is running
# Some environment variables when running sandbox
#OVN_IC_NB_DB=unix:ic_nb1.ovsdb,unix:ic_nb2.ovsdb,unix:ic_nb3.ovsdb
#OVN_IC_SB_DB=unix:ic_sb1.ovsdb,unix:ic_sb2.ovsdb,unix:ic_sb3.ovsdb
#OVN_NB_DB=unix:nb1.ovsdb
#OVN_RUNDIR=/home/drc/src/ovn/tutorial/sandbox
#OVN_SB_DB=unix:sb1.ovsdb
#OVS_DBDIR=/home/drc/src/ovn/tutorial/sandbox
#OVS_LOGDIR=/home/drc/src/ovn/tutorial/sandbox
#OVS_RUNDIR=/home/drc/src/ovn/tutorial/sandbox
#OVS_SYSCONFDIR=/home/drc/src/ovn/tutorial/sandbox

##############################################################################
## Generate all the MAC addresses required
##############################################################################
mac_count=$((MAX_LOGICAL_SWITCHES + (MAX_LOGICAL_SWITCHES * MAX_PORTS_PER_LOGICAL_SWITCH)))
# DRC gen_macs $mac_count
UNIQUE_MACS=("00:00:00:00:ff:01" "00:00:00:00:ff:02" "50:54:00:00:00:01" "50:54:00:00:00:02" "50:54:00:00:00:03" "50:54:00:00:00:04")
log_success_msg "Generated $mac_count random MAC addresses"
log_success_msg "[${UNIQUE_MACS[*]}]"

##############################################################################
# Create logical routers
##############################################################################
# ToDo: Add support for multiple routers
for (( r = 0; r < $MAX_LOGICAL_ROUTERS; r++ )); do
  # DRC lr="$LOGICAL_ROUTER_NAME$(printf "%03d" $r)"
  lr="lr0"
  action "Creating logical router $lr" \
    ovn-nbctl lr-add $lr
done

##############################################################################
# Create an array of IP/MAC addresses for the logical router
##############################################################################
# gen_ips $ROUTER_CIDR
# router_ips=("${IPS[@]}")
# log_success_msg "Reserved IPv4 subnet $ROUTER_CIDR for logical router $lr"

router_macs=("${UNIQUE_MACS[@]::$MAX_LOGICAL_SWITCHES}")
UNIQUE_MACS=("${UNIQUE_MACS[@]:$MAX_LOGICAL_SWITCHES}")
log_success_msg "Reserved ${#router_macs[@]} MAC addresses for logical router $lr"
log_success_msg "[${router_macs[*]}]"

##############################################################################
# Create logical switches, attaching them to the logical router
##############################################################################
for (( s = 0; s < $MAX_LOGICAL_SWITCHES; s++ )); do

  echo "========================================================="

  # Setup logical switch naming
  ls="$LOGICAL_SWITCH_NAME$(printf "%03d" $s)"
  # Port names that will be exposed to containers/namespaces
  lsp="$ls-$LOGICAL_SWITCH_PORT_NAME$(printf "%03d" $s)"
  # Downlink port on the router
  # DRC lrd="$lr-$ls"
  lrd="lrp$s"
  # Uplink port on the switch
  # lsu="$ls-$LOGICAL_SWITCH_UPLINK_NAME"
  lsu="lrp$s-attachment"

  # Create an array of IPv4 addresses for the logical switch
  # The gateway for each IPv4 subnet will be used by the router,
  # all remaining addresses will be used on the switch.
  SWITCH_NETWORK="192.168.$s.0"
  SWITCH_NETMASK="24"
  SWITCH_CIDR="$SWITCH_NETWORK/$SWITCH_NETMASK"
  gen_ips $SWITCH_CIDR
  switch_ips=("${IPS[@]}")
  log_success_msg "Reserved IPv4 subnet $SWITCH_CIDR for logical switch $ls"
  
  # Carve out an array of MAC addresses for the logical switch
  switch_macs=("${UNIQUE_MACS[@]::$MAX_PORTS_PER_LOGICAL_SWITCH}")
  UNIQUE_MACS=("${UNIQUE_MACS[@]:$MAX_PORTS_PER_LOGICAL_SWITCH}")
  log_success_msg "Reserved ${#switch_macs[@]} MAC addresses for logical switch $ls"
  log_success_msg "[${switch_macs[*]}]"

  # Create a new logical switch
  action "Creating logical switch $ls" \
    ovn-nbctl ls-add "$ls"

  # ovn-nbctl lrp-add lr0 lrp0 00:00:00:00:ff:01 192.168.0.1/24
  # Add a downlink port to the router for the switch
  action "Adding downlink port $lrd to router $lr" \
    ovn-nbctl lrp-add $lr $lrd ${router_macs[$s]} ${switch_ips[0]}/$SWITCH_NETMASK
  log_success_msg "IP: ${switch_ips[0]} MAC: ${router_macs[$s]}"

  # ovn-nbctl lsp-add sw0 lrp0-attachment
  # Add an uplink port to the switch
  action "Adding uplink port $lsu to switch $ls" \
    ovn-nbctl lsp-add $ls $lsu

  # ovn-nbctl lsp-set-type lrp0-attachment router
  # Set the uplink port type to "router"
  action "Setting uplink port $lsu to type \"router\"" \
    ovn-nbctl lsp-set-type $lsu router

  # ovn-nbctl lsp-set-addresses lrp0-attachment 00:00:00:00:ff:01
  # Forward traffic to the router through the switch's uplink port
  action "Forward router traffic ${router_macs[$s]} through uplink port $lsu" \
    ovn-nbctl lsp-set-addresses $lsu ${router_macs[$s]}

  # ovn-nbctl lsp-set-options lrp0-attachment router-port=lrp0
  # Attach the uplink port on the switch to the downlink port on the router
  action "Connecting switch uplink port $lsu to router downlink port $lrd" \
    ovn-nbctl lsp-set-options $lsu router-port=$lrd

  # Setup the base OVS port number for the current logical switch
  ovs_port=$(( s * MAX_PORTS_PER_LOGICAL_SWITCH ))

  # Create a number of ports on the logical switch for container/namespace use
  for (( p = 0; p < $MAX_PORTS_PER_LOGICAL_SWITCH; p++ )); do

    # Setup logical switch port naming
    lsp="$ls-$LOGICAL_SWITCH_PORT_NAME$(printf "%03d" $p)"
    sp="p$(printf "%04d" $((ovs_port + p)))"

    # ovn-nbctl lsp-add sw0 sw0-port1
    action "Adding logical port $lsp to switch $ls" \
      ovn-nbctl lsp-add $ls $lsp

    # ovn-nbctl lsp-set-addresses sw0-port1 "50:54:00:00:00:01 192.168.0.2"
    action "Assigning IP/MAC addresses to logical port $lsp" \
      ovn-nbctl lsp-set-addresses $lsp "${switch_macs[$p]} ${switch_ips[$((p+1))]}"
    log_success_msg "IP: ${switch_ips[$((p+1))]} MAC: ${switch_macs[$p]}"

    # ovs-vsctl add-port br-int p1 -- set Interface p1 external_ids:iface-id=sw0-port1
    # Connect the logical switch port to an OVS switch port
    action "Create OVS switch port $ovs_port for external use" \
      ovs-vsctl add-port br-int $sp -- \
        set Interface $sp external_ids:iface-id=$lsp
  done
done

# View a summary of the configuration
printf "\n=== ovn-nbctl show ===\n\n"
ovn-nbctl show
printf "\n=== ovn-nbctl show with wait hv ===\n\n"
ovn-nbctl --wait=hv show
printf "\n=== ovn-sbctl show ===\n\n"
ovn-sbctl show

# Show the results
log_success_msg "Final OVS bridge configuration"
ovs-vsctl show
