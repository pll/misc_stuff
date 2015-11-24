#!/bin/bash

# This script shamelessly stolen from Tom Stockton over at CakeSolutions:
# http://www.cakesolutions.net/teamblogs/making-aws-nat-instances-highly-available-without-the-compromises
#
# I have modified it some, but not much.

function log () {
  echo "$(date +"%b %e %T") $@"
  logger -- $(basename $0)" - $@"
}

metadata_svr="http://169.254.169.254/latest"

my_eni_id=$(cat /var/tmp/eni-id.txt)
my_instance_id=$(curl -s $metadata_svr/meta-data/instance-id)

REGION=$(curl -s $metadata_svr/dynamic/instance-identity/document|grep region|awk -F\" '{print $4}')
export AWS_DEFAULT_REGION="$REGION"

ec2cmd="/usr/bin/aws ec2"
eni="--network-interface-id ${my_eni_id}"
instance="--instance-id ${my_instance_id}"

$ec2cmd  attach-network-interface $eni $instance --device-index 1

# disable source destination check
$ec2cmd modify-network-interface-attribute $eni --no-source-dest-check --region $REGION

retcode=$?
[ "$retcode" -eq 0 ] && { log "eni attachment successful" ; exit 0 ; } || { log "eni attachment failed" ; exit 1 ; }
