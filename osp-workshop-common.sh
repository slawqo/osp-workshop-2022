#!/bin/bash

WORKDIR=$(dirname "$0")
SCENARIO_NUM=$(ls -d $WORKDIR/roles/scenario* | sed 's/.*scenario\([0-9]*\)/\1/g' | sort | tail -n1)

DEFAULT_BACKUP_NAME=backup

debug=false
ansible_params=""
backup_name=$DEFAULT_BACKUP_NAME
private_key=""

WORKSHOP_MESSAGE_FILE=/tmp/workshop_message

function prepare_scenario() {
    check_and_get_inventory
    rm -f $WORKSHOP_MESSAGE_FILE

    echo "Preparing scenario $1 ... please wait."
    if [ "$debug" == "true" ]; then
        $ansible_playbook $WORKDIR/playbooks/workarounds.yml
        $ansible_playbook $WORKDIR/playbooks/scenario.yml -e scenario=$1
        ansible_run_ecode=$?
    else
        $ansible_playbook $WORKDIR/playbooks/workarounds.yml
        $ansible_playbook $WORKDIR/playbooks/scenario.yml -e scenario=$1 > /dev/null
        ansible_run_ecode=$?
    fi

    if [ $ansible_run_ecode -eq 0 ]; then
        echo "Scenario $1 is ready."
    else
        echo "Scenario has failed!" >&2
        exit 3
    fi

    if [ -e $WORKSHOP_MESSAGE_FILE ]; then
        echo
        echo
        cat $WORKSHOP_MESSAGE_FILE
        echo
        echo
    fi
}


function do_snapshot() {
    check_and_get_inventory
    set -e

    $ansible_playbook $WORKDIR/playbooks/snapshot.yml -e backup_name=$backup_name -e snapshot_action=$1

    echo
    # Check that everything is fine
    if virsh list --all | tail -n+3 | grep -q paused; then
        echo "Some VMs got stuck in paused state, trying to fix it ..." 1>&2
        for vm in $(virsh list --all | awk '/paused/{ print $ 2}'); do
            virsh reset $vm
            virsh resume $vm
        done

        if virsh list --all | tail -n+3 | head -n-1 | grep -v running | grep -q "-"; then
            echo "Unable to resume some VMs, check libvirt" 1>&2
            exit 2
        fi

    fi

    $ansible_playbook $WORKDIR/playbooks/sync.yml

    echo "$1 operation using backup name $backup_name was successful"
}


