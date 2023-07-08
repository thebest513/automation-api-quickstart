#!/bin/bash

echo "parameters: $argv"
ALIAS=$(hostname)
PERSISTENT_VOL=$1/$ALIAS
FOLDERS_EXISTS=false
AGENT_REGISTERED=false
OSACCOUNT="ctmadm"
HOMEDIR="/home/ctmadm"
export CONTROLM=$HOMEDIR/ctm
CTM_AGENT_PORT=7006

# create if needed, and map agent persistent data folders
echo 'mapping persistent volume'
cd $HOMEDIR

sudo echo PATH="${PATH}:$HOMEDIR/bmcjava/bmcjava-V3/bin:$CONTROLM/scripts:$CONTROLM/exe">>~/.bash_profile
sudo echo export PATH>>~/.bash_profile

source ~/.bash_profile
#Modify agent configuration
#sed -i "s/LOGICAL_AGENT_NAME.*$/LOGICAL_AGENT_NAME                  $ALIAS/g" $CONTROLM/data/CONFIG.dat
#sed -i "s/LOCALHOST.*$/LOCALHOST                  $ALIAS/g" $CONTROLM/data/CONFIG.dat
#sed -i "s/PERSISTENT_CONNECTION.*$/PERSISTENT_CONNECTION               Y/g" $CONTROLM/data/CONFIG.dat
#sed -i "s/PHYSICAL_UNIQUE_AGENT_NAME.*$/PHYSICAL_UNIQUE_AGENT_NAME               $ALIAS/g" $CONTROLM/data/CONFIG.dat
#sed -i "s/INSTALL_HOSTNAME.*$/INSTALL_HOSTNAME               $ALIAS/g" $CONTROLM/data/CONFIG.dat
#sed -i "s/GCMNDATA.*$/GCMNDATA               $CTM_AGENT_PORT/g" $CONTROLM/data/CONFIG.dat
#sed -i "s/CTMSHOST.*$/CTMSHOST                  $PERM_HOSTS/g" $CONTROLM/data/CONFIG.dat

if [ ! -d $PERSISTENT_VOL/pid ];
then
        echo 'first time the agent is using the persistent volume, moving folders to persistent volume'
        # no agent files exist in PV, copy the current agent files to PV
        mkdir $PERSISTENT_VOL
		mv $CONTROLM/backup $CONTROLM/capdef $CONTROLM/dailylog $CONTROLM/data $CONTROLM/measure $CONTROLM/onstmt $CONTROLM/pid $CONTROLM/procid $CONTROLM/status $CONTROLM/sysout $CONTROLM/temp $CONTROLM/cm -t $PERSISTENT_VOL
		

else
        echo 'this is not the first time an agent is running using this persistent volume, mapping folder to existing persistent volume'
        FOLDERS_EXISTS=true
		rm -Rf $CONTROLM/backup $CONTROLM/capdef $CONTROLM/dailylog $CONTROLM/data $CONTROLM/measure $CONTROLM/onstmt $CONTROLM/pid $CONTROLM/procid $CONTROLM/status $CONTROLM/sysout $CONTROLM/temp $CONTROLM/cm
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
ln -s $PERSISTENT_VOL/temp      $CONTROLM/temp
ln -s $PERSISTENT_VOL/cm        $CONTROLM/cm

# echo using new AAPI configuration, not the default build time configuration
echo run and register controlm agent [$ALIAS] with controlm [$CTM_SERVER], environment [$CTM_ENV] 
ctm env add $CTM_ENV https://$EM_SERVER:$EM_PORT/automation-api $AAPI_USER $AAPI_PASSWORD
ctm env set $CTM_ENV

# check if Agent exists in the Control-M Server
if $FOLDERS_EXISTS ; then
       ctm config server:agents::get $CTM_SERVER $ALIAS | grep $ALIAS
       if [[ $? == "0" ]] ;  then
	       echo 'agent already exists'
               AGENT_REGISTERED=true
       fi
fi

if $FOLDERS_EXISTS && $AGENT_REGISTERED ; then
               # start the Agent
               echo 'starting the Agent'
               start-ag -u $OSACCOUNT -p ALL
               else
               echo 'configuring and registering the agent'
               ctm provision agent::setup $CTM_SERVER $ALIAS $CTM_AGENT_PORT -f agent_configuration.json
		
fi

#if PERM_HOST defined, then update CTMPERMHOSTS
if [ "x${PERM_HOSTS}" != "x" ];then
 echo "Replaced CTMPERMHOSTS to $PERM_HOSTS"
 sed -i "s/CTMPERMHOSTS.*$/CTMPERMHOSTS                  $PERM_HOSTS/g" $CONTROLM/data/CONFIG.dat
fi

start-ag -u $OSACCOUNT -p ALL

echo 'checking Agent communication with Control-M Server'
ag_diag_comm

echo 'adding the Agent to Host Group'
ctm config server:hostgroup:agent::add $CTM_SERVER $CTM_HOSTGROUP $ALIAS

echo 'running in agent container and keeping it alive'
./ctmhost_keepalive.sh

