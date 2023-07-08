#!/bin/bash

#CTM_ENV=endpoint
#CTM_SERVER=controlm
#CTM_HOSTGROUP=app0
CTM_AGENT_PORT=`cat ~/ctm/data/CONFIG.dat |grep "AGCMNDATA"|awk '{print $2}'`
ALIAS=$(hostname)

#cd
#source .bash_profile

echo delete or remove a controlm hostgroup [$CTM_HOSTGROUP] with controlm agent [$ALIAS]
ctm config server:hostgroup:agent::delete $CTM_SERVER $CTM_HOSTGROUP $ALIAS -e $CTM_ENV

#Check if the agent in Discovering state, then disable it first before delete it
#agentstate=`ctm config server:agents::get $CTM_SERVER $ALIAS|grep Discovering | awk '{print $2}'`
#if [ -n agentstate ];then ctm  config server:agent::disable $CTM_SERVER $ALIAS; fi

echo stop and unregister controlm agent [$ALIAS] with controlm [$CTM_SERVER], environment [$CTM_ENV] 
ctm config server:agent::delete $CTM_SERVER $ALIAS -e $CTM_ENV

exit 0
