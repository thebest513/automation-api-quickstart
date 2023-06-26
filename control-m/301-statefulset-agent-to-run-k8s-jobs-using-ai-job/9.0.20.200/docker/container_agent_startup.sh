#!/bin/bash 

echo "parameters: $argv"
AG_NODE_ID=$HOSTNAME
PERSISTENT_VOL=$PERSISTENT_VOL/$AG_NODE_ID
CTM_SERVER_NAME=$CTM_SERVER_NAME
FOLDERS_EXISTS=false
AGENT_REGISTERED=false
AGENT_HOSTGROUP_NAME=$AGENT_HOSTGROUP_NAME
export CONTROLM=/home/controlm/ctm
agentName=$HOSTNAME

# create if needed, and map agent persistent data folders
echo 'mapping persistent volume'
cd /home/controlm

sudo echo PATH="${PATH}:/home/controlm/bmcjava/bmcjava-V3/bin:/home/controlm/ctm/scripts:/home/controlm/ctm/exe">>~/.bash_profile
sudo echo export PATH>>~/.bash_profile

source ~/.bash_profile

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
        start-ag -u controlm -p ALL
else
        echo 'configuring and registering the agent'
        ctm provision agent::setup $CTM_SERVER_NAME $AG_NODE_ID 7006 -f agent_configuration.json
	sleep 300
	ctm config server:agent:param::set $CTM_SERVER_NAME $AG_NODE_ID LOGKEEPDAYS 14
	ctm config server:agent:param::set $CTM_SERVER_NAME $AG_NODE_ID OUTPUT_NAME JOBNAME
	ctm config server:agent:param::set $CTM_SERVER_NAME $AG_NODE_ID I18N CJK
fi

echo 'checking Agent communication with Control-M Server'
ag_diag_comm

echo 'adding the Agent to Host Group'
ctm config server:hostgroup:agent::add $CTM_SERVER_NAME $AGENT_HOSTGROUP_NAME $AG_NODE_ID

echo 'running in agent container and keeping it alive'
./ctmhost_keepalive.sh
