#!/bin/bash

#EM_SERVER
#CTM_ENV=endpoint
#CTM_SERVER=controlm 
#CTM Server Datacenter Name
#CTM_HOSTGROUP=app0
#CTM_MFT
#CTM_AGENT_PORT=$(shuf -i 7000-8000 -n 1)
CTM_AGENT_PORT=7006
ALIAS=$(hostname)
HOMEDIR="/home/ctmadm"

function sigusr1Handler() {
    $HOMEDIR/decommission_controlm.sh
    return 0
}

function sigtermHandler() {
    $HOMEDIR/decommission_controlm.sh
    return 0
}
#sed -i 's#${PATH}#${PATH}:/home/controlm/ctm/cm/AFT/JRE_11/bin#g' /home/controlm/.bash_profile
source $HOMEDIR/.bash_profile

trap 'sigusr1Handler' SIGUSR1
trap 'sigtermHandler' SIGTERM
echo run and register controlm agent [$ALIAS] with controlm [$CTM_SERVER], environment [$CTM_ENV] 
ctm env add $CTM_ENV https://$EM_SERVER:$EM_PORT/automation-api $AAPI_USER $AAPI_PASSWORD
ctm env set $CTM_ENV

ctm provision agent::setup $CTM_SERVER $ALIAS $CTM_AGENT_PORT -f agent-parameters.json
echo add or create a controlm hostgroup [$CTM_HOSTGROUP] with controlm agent [$ALIAS]
ctm config server:hostgroup:agent::add $CTM_SERVER $CTM_HOSTGROUP $ALIAS -e $CTM_ENV
sleep 5 
#if PERM_HOSTS defined, then update CTMPERMHOSTS
if [ "x${PERM_HOSTS}" != "x" ];then
 sed -i "s/CTMPERMHOSTS.*$/CTMPERMHOSTS                  $PERM_HOSTS/g" $CONTROLM/data/CONFIG.dat
fi
ag_diag_comm

echo "Control-M Agent Available"
echo "Agent Name: $ALIAS"
echo "Agent Idle"

#Call keep alive scripts
$HOMEDIR/keep_alive.sh &

# loop forever
while true
do 
  tail -f /dev/null & wait ${!} 
done

$HOMEDIR/decommission_controlm.sh
echo "Control-M last step"
 
exit 0
