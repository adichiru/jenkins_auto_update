#!/bin/bash

# Author: Adi Chiru (achiru@ea.com)
# Date: 2016-03-09

# This script is used to automatically update the Jenkins server from Ubuntu's official repository.
# It is supposed to be run via cron or manually. It produces a log file detailing each run.
# The log file is in the same directory as the script and has the same name as the script with the
# suffix .log


# VARIABLES:
print_log_messages_on_screen="yes"


# FUNCTIONS:
function usage () {
    echo "Usage: $0 {update|rollback} [version]"
    echo "The script accepts one or two parameters only; these are"
    echo "  update - the script will update local Jenkins installation via apt-get"
    echo "  rollback - the script will rollback the Jenkins package to a version"
    echo "             specified by the second argument"
    echo "  version - only required for the rollback option; must be a version"
    echo "            string that apt-get understands"
    echo ""
    echo "Examples:"
    echo "   $0 update"
    echo "   $0 rollback 1.652"
    echo ""
    exit 1
}

function toLog () {
    # usage: call this function with one of these parameters:
    # -S Indicates the message type is SUCCESS
    # -E Indicates the message type is ERROR
    # -I Indicates the message type is INFO
    # -A Indicates the message type is ACTION
    # Example:
    #    toLog -E "message"
    #  will create a line in the log file like this:
    # 20160331 211001 ERROR message
    #
    log_file="$(basename $0).log"
    dt=$(date +"%Y%m%d")
    ts=$(date +"%H%M%S")
    if [ $# -eq 2 ]; then
        msg_type_indicator="$1"
        msg_body="$2"
        case ${msg_type_indicator} in
            -S)
                msg_type="SUCCESS";;
            -E)
                msg_type="ERROR";;
            -I)
                msg_type="INFO";;
            -A)
                msg_type="ACTION";;
             *)
                echo "Error calling toLog function. Exiting..."
                exit 1
        esac
        if [ ! -f $log_file ]; then
           echo "$dt $ts INFO File created." > "$log_file"
        fi
        if [ "$print_log_messages_on_screen" == "yes" ]; then
           echo "$dt $ts $msg_type $msg_body" | tee -a "$log_file"
        else
           echo "$dt $ts $msg_type $msg_body" >> "$log_file"
        fi
    else
        echo "Error calling toLog function. Exiting..."
        exit 1
    fi
}

function getJenkinsRunningVersion () {
    local current_version=$(dpkg-query --show jenkins | awk '{print $2}')
    if [ "$current_version" != "" ]; then
        echo "$current_version"
    fi
}

function getJenkinsAvailableVersion () {
    # apt-cache policy jenkins | grep "Installed:" | awk '{print $2}'
    local available_version=$(apt-cache policy jenkins | grep "Candidate:" | awk '{print $2}')
    if [ "$available_version" != "" ]; then
        echo "$available_version"
    fi
}

function getJenkinsStatus () {
    local status=$(service jenkins status)
    echo "$status"
}

function stopJenkinsService () {
    local status=$(service jenkins stop)
    sleep 3
    echo "$status"
}

function startJenkinsService () {
    local status=$(service jenkins start)
    sleep 3
    echo "$status"
}

function getOldJenkinsPackage () {
    version=$1
    package_name="jenkins_${version}_all.deb"
    wget -q http://pkg.jenkins-ci.org/debian/binary/$package_name
    if [ $? -eq 0 ]; then
        echo "0"
    else
        echo "1"
    fi
}

function rollbackJenkins () {
    local version=$1
    local package_name="jenkins_${version}_all.deb"
    dpkg -i $package_name
    installed=$(apt-cache policy jenkins | grep "Installed:" | awk '{print $2}')
    if [ "$installed" == "${version}" ]; then
        let rollback_status="0"
    else
        let rollback_status="1"
    fi
}

function updateJenkins () {
    running_version=$(getJenkinsRunningVersion)
    toLog -I "Running version is: $running_version"
    available_version=$(getJenkinsAvailableVersion)
    toLog -I "Available version is: $available_version"
    if [ "$running_version" != "$available_version" ]; then
        toLog -A "Upgrading Jenkins:"
        toLog -I " - stopping Jenkins service:"
        stopJenkinsService
        toLog -I " - running apt-get:"
        apt-get install --only-upgrade jenkins
    else
        toLog -I "Nothing to do."
        toLog -I "The current running version is the latest available."
    fi
}

function backupJenkins () {
    cur_dir=$(pwd)
    local package_name="jenkins*.deb"
    if [ ! -d backups ]; then
        mkdir backups
    fi
    cp -u --preserve=all /var/cache/apt/archives/$package_name $cur_dir/backups/
    if [ $? -eq 0 ]; then
        echo "0"
    else
        echo "1"
    fi
}

# SCRIPT BODY
toLog -I "================================"
toLog -I "New run:"
running_version=$(getJenkinsRunningVersion)
if [ $# -eq 1 ]; then
    if [ "$1" == "update" ]; then
        toLog -A "  Backing up current Jenkins package:"
        backup_status=$(backupJenkins)
        if [ "$backup_status" == "0" ]; then
            toLog -S "  - Current Jenkins deb package was copied to backup."
        elif [ "$backup_status" == "1" ]; then
            toLog -E "  - Unable to copy the current Jenkins deb package to backup. Exiting..."
            exit 1
        fi
        toLog -A "  Performing update:"
        apt-get -q update > /dev/null
        update_status=$(updateJenkins)
        if [ "$update_status" == "0" ]; then
            toLog -S "  - Jenkins has been updated to $running_version"
        elif [ "$update_status" == "1" ]; then
            toLog -E "  - Unable to update Jenkins. Exiting..."
            exit 1
        fi
        toLog -A " Checking Jenkins service status:"
        status=$(getJenkinsStatus)
        toLog -I "  $status"
        jenkins_status=$(echo $status | awk '{print $6}')
        if [ "$jenkins_status" == "running" ]; then
            toLog -S "  - Jenkins server is running!"
        else
            toLog -E "  - Jenkins server is NOT running!"
            exit 1
        fi
        toLog -I "DONE!"
    else
        toLog -E "Parameter(s) is/are wrong. Exiting..."
        usage
    fi
elif [ $# -eq 2 ]; then
    if [ "$1" == "rollback" ]; then
        version_for_rollback=$2
        toLog -A "  Performing roll back to $version_for_rollback:"
        get_old_package_status=$(getOldJenkinsPackage "${version_for_rollback}")
        if [ "$get_old_package_status" == "0" ]; then
            toLog -S "  - Jenkins package for roll back retrieved."
        else
            toLog -E "  - Unable to retrieve package from http://pkg.jenkins-ci.org/debian/binary/. Exiting..."
            exit 1
        fi
        rollbackJenkins "${version_for_rollback}"
        if [ "$rollback_status" == "0" ]; then
            toLog -S "  - Jenkins has been rolled back to ${version_for_rollback}"
        else
            toLog -E "  - Unable to roll back Jenkins. Exiting..."
            exit 1
        fi
        toLog -A " Checking Jenkins service status:"
        status=$(getJenkinsStatus)
        toLog -I "  $status"
        jenkins_status=$(echo $status | awk '{print $6}')
        if [ "$jenkins_status" == "running" ]; then
            toLog -S "  - Jenkins server is running!"
        else
            toLog -E "  - Jenkins server is NOT running!"
            exit 1
        fi
        toLog -I "DONE!"
    else
       toLog -E "Parameter(s) is/are wrong. Exiting..."
       usage
    fi
else
    toLog -E "Parameter(s) is/are wrong. Exiting..."
    usage
fi

# END of script
