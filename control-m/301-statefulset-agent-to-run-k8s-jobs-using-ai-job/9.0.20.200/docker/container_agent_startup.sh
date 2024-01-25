#!/bin/bash 

echo "parameters: $argv"
AG_NODE_ID=$HOSTNAME
PERSISTENT_VOL=$PERSISTENT_VOL/$AG_NODE_ID
AAPI_END_POINT=$AAPI_END_POINT
AAPI_TOKEN=$AAPI_TOKEN
AAPI_USER=$AAPI_USER
AAPI_PSWD=$AAPI_PSWD
CTM_SERVER_NAME=$CTM_SERVER_NAME
AGENT_HOSTGROUP_NAME=$AGENT_HOSTGROUP_NAME
AGENT_TAG=$AGENT_TAG
FOLDERS_EXISTS=false
AGENT_REGISTERED=false
OSACCOUNT="ctmag"
HOMEDIR="/home/ctmag"
export CONTROLM=$HOMEDIR/ctm

function sigusr1Handler() {
    $HOMEDIR/decommission_controlm.sh
    return 0
}
function sigtermHandler() {
    $HOMEDIR/decommission_controlm.sh
    return 0
}

# create if needed, and map agent persistent data folders
echo 'mapping persistent volume'
cd $HOMEDIR

echo PATH="${PATH}:$HOMEDIR/bmcjava/bmcjava-V3/bin:$HOMEDIR/ctm/scripts:$HOMEDIR/ctm/exe">>~/.bash_profile
echo export PATH>>~/.bash_profile

source ~/.bash_profile
trap 'sigusr1Handler' SIGUSR1
trap 'sigtermHandler' SIGTERM

if [ ! -d $PERSISTENT_VOL/pid ];
then
        echo 'first time the agent is using the persistent volume, moving folders to persistent volume'
        # no agent files exist in PV, copy the current agent files to PV
        mkdir $PERSISTENT_VOL
		mv $CONTROLM/backup $CONTROLM/capdef $CONTROLM/dailylog $CONTROLM/data $CONTROLM/measure $CONTROLM/onstmt $CONTROLM/pid $CONTROLM/procid $CONTROLM/status $CONTROLM/sysout $CONTROLM/cm -t $PERSISTENT_VOL
		

else
        echo 'this is not the first time an agent is running using this persistent volume, mapping folder to existing persistent volume'
        FOLDERS_EXISTS=true
		rm -Rf $CONTROLM/backup $CONTROLM/capdef $CONTROLM/dailylog $CONTROLM/data $CONTROLM/measure $CONTROLM/onstmt $CONTROLM/pid $CONTROLM/procid $CONTROLM/status $CONTROLM/sysout $CONTROLM/cm
		sed '/CM_LIST_SENT2CTMS/d' $PERSISTENT_VOL/data/CONFIG.dat
fi
# create link to persistent volume
ln -s $PERSISTENT_VOL/backup    $CONTROLM/backup
ln -s $PERSISTENT_VOL/capdef    $CONTROLM/capdef
ln -s $PERSISTENT_VOL/dailylog  $CONTROLM/dailylog
ln -s $PERSISTENT_VOL/data      $CONTROLM/data
ln -s $PERSISTENT_VOL/measure   $CONTROLM/measure
ln -s $PERSISTENT_VOL/onstmt    $CONTROLM/onstmt
ln -s $PERSISTENT_VOL/pid       $CONTROLM/pid
ln -s $PERSISTENT_VOL/procid    $CONTROLM/procid
ln -s $PERSISTENT_VOL/sysout    $CONTROLM/sysout
ln -s $PERSISTENT_VOL/status    $CONTROLM/status
ln -s $PERSISTENT_VOL/cm        $CONTROLM/cm



# echo using new AAPI configuration, not the default build time configuration
if $AAPI_PSWD ; then
        ctm env add myenv $AAPI_END_POINT $AAPI_USER $AAPI_PSWD
if $AAPI_TOKEN ; then
        ctm env add myenv $AAPI_END_POINT $AAPI_TOKEN
ctm env set myenv

# check if Agent exists in the Control-M Server
if $FOLDERS_EXISTS ; then
       ctm config server:agents::get $CTM_SERVER_NAME $AG_NODE_ID | grep $AG_NODE_ID
       if [[ $? == "0" ]] ;  then
	       echo 'agent already exists'
               AGENT_REGISTERED=true
       fi
fi

if $FOLDERS_EXISTS && $AGENT_REGISTERED ; then
        # start the Agent
        echo 'starting the Agent'
        start-ag -u $OSACCOUNT -p ALL
else    # configuring and registering the agent
        echo 'configuring and registering the agent'
	jq -n --argjson connectionInitiator '"AgentToServer"' --argjson serverHostName '"'"$SERVER_HOST"'"' --argjson tag '"'"$AGENT_TAG"'"' \
           '{connectionInitiator: $connectionInitiator, serverHostName: $serverHostName, tag: $tag} | with_entries(select(.value != null and .value != ""))' > agent_configuration.json
        cat agent_configuration.json
        ctm provision agent::setup $CTM_SERVER_NAME $AG_NODE_ID $AGENT_PORT -f agent_configuration.json
fi

echo 'checking Agent communication with Control-M Server'
ag_diag_comm

# adding the Agent to Host Group
echo 'adding the Agent to Host Group'
jq -n --argjson tag '"'"$AGENT_TAG"'"' '{tag: $tag} | with_entries(select(.value != null and .value != ""))' > agent_hostgroup.json
cat agent_hostgroup.json
ctm config server:hostgroup:agent::add $CTM_SERVER_NAME $AGENT_HOSTGROUP_NAME $AG_NODE_ID -f agent_hostgroup.json

# deploying agent to KUBERNETES ai job type
echo 'deploying agent to KUBERNETES ai job type'
x=1
ctm deploy ai:jobtype  $CTM_SERVER_NAME $AG_NODE_ID KUBERNETES | grep "successful" > res.txt

while [ ! -s res.txt ]
do
   echo "try $x times"
   ctm deploy ai:jobtype  $CTM_SERVER_NAME $AG_NODE_ID KUBERNETES | grep "successful" > res.txt
	x=$(( $x + 1 ))
   sleep 20
done

echo 'deploying agent to KUBERNETES ai job type successed'
rm res.txt

# running in agent container and keeping it alive
echo 'running in agent container and keeping it alive'
./ctmhost_keepalive.sh
