#!/bin/bash

cd
source .bash_profile

ENVNAME=en1
AG_NODE_ID=$HOSTNAME
CTM_SERVER_NAME=$CTM_SERVER_NAME
AGENT_HOSTGROUP_NAME=$AGENT_HOSTGROUP_NAME

echo delete or remove a controlm hostgroup [$AGENT_HOSTGROUP_NAME] with contorlm agent [$AG_NODE_ID]
ctm config server:hostgroup:agent::delete $CTM_SERVER_NAME $AGENT_HOSTGROUP_NAME $AG_NODE_ID -e $ENVNAME

echo stop and unregister controlm agent [$AG_NODE_ID] with controlm [$CTM_SERVER_NAME], environment [$ENVNAME]
ctm config server:agent::delete $CTM_SERVER_NAME $AG_NODE_ID -e $ENVNAME

exit 0
