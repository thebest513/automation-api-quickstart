#!/bin/bash

CTM_ENV=myenv
ALIAS=$HOSTNAME
CTM_SERVER_NAME=$CTM_SERVER_NAME
AGENT_HOSTGROUP_NAME=$AGENT_HOSTGROUP_NAME

echo delete or remove a controlm hostgroup [$AGENT_HOSTGROUP_NAME] with contorlm agent [$ALIAS]
ctm config server:hostgroup:agent::delete $CTM_SERVER_NAME $AGENT_HOSTGROUP_NAME $ALIAS -e $CTM_ENV

echo stop and unregister controlm agent [$ALIAS] with controlm [$CTM_SERVER_NAME], environment [$CTM_ENV]
ctm config server:agent::delete $CTM_SERVER_NAME $ALIAS -e $CTM_ENV

exit 0
