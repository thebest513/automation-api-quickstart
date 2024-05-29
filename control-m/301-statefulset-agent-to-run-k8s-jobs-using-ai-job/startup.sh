#!/bin/bash
cd "$(dirname "$0")" || exit 1
function log() { echo -e "\n$(date +%F" "%H:%M:%S) = $0 = $1 \n"; }
function printEnvVar() {
  echo "$1=${!1}"
  if [[ $2 == true && -z ${!1} ]]; then
    echo "Environment variable $1 should be defined"
    exit 1
  fi
}
function setArbitraryUser() {
if ! whoami &> /dev/null; then
  if [ -w /etc/passwd ]; then
    echo "Setting etc passwd entry for $(id -u)"
    echo "oci-user:x:$(id -u):0:Arbitrary user:/home/controlm:/bin/bash" >> /etc/passwd
    if [ $? -eq 0 ]; then
      exec ./$0 $@
    else
      echo "Failed to update etc users"
    fi
  fi
fi
echo "Running container as $(whoami)"
}

setArbitraryUser

log "Initializing shell environment and logging"

AGENT_HOST=$(hostname)
USER=controlm
HOME="/home/${USER}"
CONTROLM_ROOT="$CONTROLM/.."
PERSISTENT_VOL="$CONTROLM_ROOT/persistent_folder/$AGENT_HOST"
FOLDERS_EXISTS=false
AGENT_REGISTERED=false

# Initialize logging
if [ ! -d "$PERSISTENT_VOL"/proclog ]; then
  LOG_DEST="$CONTROLM_ROOT/persistent_folder/${AGENT_HOST}_init_$(date '+%Y-%m-%d_%H%M%S').log"
else
  LOG_DEST="$PERSISTENT_VOL/proclog/container_$(date '+%Y-%m-%d_%H%M%S').log"
fi
# Save original stdout and stderr
exec 8>&1
exec 9>&2
# Redirect stdout+stderr to tee
exec &> >(tee -ia $LOG_DEST)

log "Initializing Agent container"

log "Container environment:"
printEnvVar "AGENT_NFS_MODE" false
printEnvVar "AGENT_PORT" true
printEnvVar "AGENT_TOKEN_TAG" false
printEnvVar "AAPI_ENDPOINT" true
printEnvVar "SERVER_HOST" true
printEnvVar "SERVER_PORT" true
printEnvVar "SERVER_HOSTGROUP_NAME" true
printEnvVar "SERVER_NAME" true
printEnvVar "SECONDARY_SERVER_HOST" false
printEnvVar "PERSISTENT_VOL" true
printEnvVar "BMC_INST_JAVA_HOME" true
printEnvVar "CONTROLM" true
printEnvVar "TRACE" false
printEnvVar "SSL" false
printEnvVar "DEL_AI_LOGS" false

log "Print image version"
cat /home/controlm/VERSION

log "Print OS version"
cat /etc/almalinux-release
uname -a

log "Print java version"
"$BMC_INST_JAVA_HOME"/bin/java -version

log "Print Agent installed-versions"
cat /home/controlm/installed-versions.txt

log "Print Agent dll ver"
ctmdllver

timeout=5
log "Adding Automation API endpoint configuration: $AAPI_ENDPOINT"
if [[ -e /etc/secrets/apiToken ]]; then
  AAPI_TOKEN=$(cat /etc/secrets/apiToken)
  ctm env add default "$AAPI_ENDPOINT" "$AAPI_TOKEN"
else
  AAPI_PASS=$(cat /etc/secrets/apiPass)
  ctm env add default "$AAPI_ENDPOINT" "$AAPI_USER" "$AAPI_PASS"
fi
ctm env set default

if [[ $TRACE == "true" ]]; then
  log "Check connection to Automation API endpoint"
  curl -kf "${AAPI_ENDPOINT}/status"

  log "Check if Control-M/Server ${SERVER_NAME} is connected"
  ctm config servers::get --trace
  ctm config servers::get | jq --arg SERVER_NAME "$SERVER_NAME" --exit-status '.[] | select(.message == "Connected" and .name == $SERVER_NAME)'
fi

ACTIVE_SERVER_HOST=$SERVER_HOST # defines active server host
log "Check connection to Control-M/Server ${SERVER_NAME}"
until
  curl -t '' --connect-timeout 2 -s telnet://"${ACTIVE_SERVER_HOST}:$SERVER_PORT" </dev/null
  [ $? -eq 49 ]
do
  log "No connection to the Control-M/Server hosted on ${ACTIVE_SERVER_HOST}:$SERVER_PORT, will retry in $timeout seconds"
  sleep $timeout
  if [[ -n "${SECONDARY_SERVER_HOST}" && "${ACTIVE_SERVER_HOST}" != "${SECONDARY_SERVER_HOST}" ]]; then
    ACTIVE_SERVER_HOST="${SECONDARY_SERVER_HOST}"
  else
    ACTIVE_SERVER_HOST="${SERVER_HOST}"
  fi
done
log "Active Control-M/Server ${SERVER_NAME} hosted on ${ACTIVE_SERVER_HOST}:$SERVER_PORT"

log 'Map Agent data folders to persistent volume.'
if [ ! -d "$PERSISTENT_VOL"/status ]; then
  log "Persistent connection : internal AR keep-alive"
  {
    echo "AR_PING_TO_SERVER_IND Y"
    echo "AR_PING_TO_SERVER_INTERVAL 30"
    echo "AR_PING_TO_SERVER_TIMEOUT 60"
    echo "DISABLE_CM_SHUTDOWN Y"
  } >>"$CONTROLM"/data/CONFIG.dat

  log "Update Agent configuration file with current hostname"
  ctmcfg -table CONFIG -action update -parameter INSTALL_HOSTNAME -value "${AGENT_HOST}"
  ctmcfg -table CONFIG -action update -parameter LOCALHOST -value "${AGENT_HOST}"
  ctmcfg -table CONFIG -action update -parameter PHYSICAL_UNIQUE_AGENT_NAME -value "${AGENT_HOST}" # relevant on for Helix
  ctmcfg -table CONFIG -action update -parameter AGENT_OWNER -value "$(whoami)"  # in case of arbitrary container user

  if [[ -n $AGENT_NFS_MODE && $AGENT_NFS_MODE == "true" ]]; then
    log "Treat PVC as NFS when updating files"
    ctmcfg -table CONFIG -action update -parameter NFS_PVC -value "Y"
  fi

  log 'The first time the Agent is using the persistent volume, moving folders to persistent volume'
  # no agent files exist in PV, copy the current agent files to PV
  mkdir "$PERSISTENT_VOL"
  chgrp root "$PERSISTENT_VOL"
  mv "$CONTROLM/"backup "$CONTROLM/"capdef "$CONTROLM/"dailylog "$CONTROLM/"data "$CONTROLM/"measure "$CONTROLM/"onstmt "$CONTROLM/"procid "$CONTROLM/"proclog "$CONTROLM/"status "$CONTROLM/"sysout "$CONTROLM/"temp -t "$PERSISTENT_VOL"
  mkdir -p "$PERSISTENT_VOL"/cm/AI
  chgrp root "$PERSISTENT_VOL"/cm/AI
  mv "$CONTROLM/"cm/AI/ccp_cache "$CONTROLM"/cm/AI/CustomerLogs "$CONTROLM"/cm/AI/data -t "$PERSISTENT_VOL"/cm/AI
else
  log 'This is not the first time the Agent is running using this persistent volume, mapping folder to existing persistent volume'
  FOLDERS_EXISTS=true
  rm -Rf "$CONTROLM/"backup "$CONTROLM/"capdef "$CONTROLM/"dailylog "$CONTROLM/"data "$CONTROLM/"measure "$CONTROLM/"onstmt "$CONTROLM/"procid "$CONTROLM/"proclog "$CONTROLM/"status "$CONTROLM/"sysout "$CONTROLM/"temp "$CONTROLM/"cm/AI/ccp_cache "$CONTROLM/"cm/AI/CustomerLogs "$CONTROLM/"cm/AI/data
  sed '/CM_LIST_SENT2CTMS/d' "$PERSISTENT_VOL"/data/CONFIG.dat
fi

# create link to persistent volume for Agent folders
ln -s "$PERSISTENT_VOL"/backup "$CONTROLM/"backup
ln -s "$PERSISTENT_VOL"/capdef "$CONTROLM/"capdef
ln -s "$PERSISTENT_VOL"/dailylog "$CONTROLM/"dailylog
ln -s "$PERSISTENT_VOL"/data "$CONTROLM/"data
ln -s "$PERSISTENT_VOL"/measure "$CONTROLM/"measure
ln -s "$PERSISTENT_VOL"/onstmt "$CONTROLM/"onstmt
ln -s "$PERSISTENT_VOL"/procid "$CONTROLM/"procid
ln -s "$PERSISTENT_VOL"/proclog "$CONTROLM/"proclog
ln -s "$PERSISTENT_VOL"/sysout "$CONTROLM/"sysout
ln -s "$PERSISTENT_VOL"/status "$CONTROLM/"status
ln -s "$PERSISTENT_VOL"/temp "$CONTROLM/"temp
# create link to persistent volume for CM folders
ln -s "$PERSISTENT_VOL"/cm/AI/ccp_cache "$CONTROLM/"cm/AI/ccp_cache
ln -s "$PERSISTENT_VOL"/cm/AI/CustomerLogs "$CONTROLM/"cm/AI/CustomerLogs
ln -s "$PERSISTENT_VOL"/cm/AI/data "$CONTROLM/"cm/AI/data

# Run plugin-specific scripts
for prescript in prestart/*.sh; do
  if [ -f $prescript -a -x $prescript ]
  then
    log "Executing prestart script $prescript"
    $prescript
  fi
done

log "Check if Agent exists in the Control-M Server"
if $FOLDERS_EXISTS && ctm config server:agents::get "$SERVER_NAME" "$AGENT_HOST" | grep "$AGENT_HOST"; then
  log "Agent $AGENT_HOST already exists"
  AGENT_REGISTERED=true
  CURRENT_SERVER_HOST=$(ctmcfg -table CONFIG -action DISPLAY -parameter CTMSHOST -quiet_mode Y | awk '{ print $2 }')
  if [[ "$CURRENT_SERVER_HOST" == "BMC-APPDEV-SAMPLE" ]]; then
    AGENT_REGISTERED=false
  fi
fi

if $AGENT_REGISTERED; then
  log "Starting the Agent"
  # in case of pod restart and Control-M Server updated in High Availability
  ctmcfg -table CONFIG -action update -parameter CTMSHOST -value "${ACTIVE_SERVER_HOST}"
  start-ag -u "${USER}" -p ALL
else
  log "Configuring and registering the agent"
  jq -n --argjson connectionInitiator '"AgentToServer"' --argjson serverHostName '"'"$ACTIVE_SERVER_HOST"'"' --argjson tag '"'"$AGENT_TOKEN_TAG"'"' --argjson serverPort '"'"$SERVER_PORT"'"' \
      '{connectionInitiator: $connectionInitiator, serverHostName: $serverHostName, tag: $tag, serverPort: $serverPort} | with_entries(select(.value != null and .value != ""))' > agent_configuration.json
  cat agent_configuration.json
  ctm provision agent::setup "$SERVER_NAME" "$AGENT_HOST" "$AGENT_PORT" -f agent_configuration.json -a "subject=Provisioning the Agent&description=Provisioning the $AGENT_HOST agent for Managing Kubernetes Workloads"
  rc=$?
  cp /home/controlm/provision*.log "$CONTROLM/"proclog
  if [ $rc -ne 0 ]; then
    echo "Provision failed, please check logs"
    [[ $TRACE == "true" ]] || exit 1
    echo "Trace mode enabled, sleeping"
    sleep infinity
  fi
fi

log "Starting Application Integrator plugin container"
"$CONTROLM"/cm/AI/exe/cm_container start &
log "Check if Application Integrator plugin container has started successfully"
while ! "$CONTROLM"/cm/AI/exe/cm_container status; do
  log "Application Integrator plugin container may be down, will retry in $timeout seconds"
  sleep $timeout
done

log "Checking Agent communication with Control-M Server"
ag_diag_comm
ctmaggetcm

if [[ $TRACE == "true" ]]; then
  log "Check if Control-M/Agent is available"
  ctm config server:agents::get "$SERVER_NAME" "$AGENT_HOST" | jq --arg AGENT_HOST "$AGENT_HOST" --exit-status '.agents[] | select(.status == "Available" and .nodeid == $AGENT_HOST)'
  ctm config server:agent::ping "$SERVER_NAME" "$AGENT_HOST"
fi

log "Adding the Agent to Host Group"
HG_CONF_JSON="hg_configuration.json"
jq -n --argjson agentHost '"'"$AGENT_HOST"'"' --argjson tag '"'"$AGENT_TOKEN_TAG"'"' \
    '{host: $agentHost, tag: $tag} | with_entries(select(.value != null and .value != ""))' > $HG_CONF_JSON
cat $HG_CONF_JSON
TMP_OUTPUT_FILE=add_hg_output.txt
ctm config server:hostgroup:agent::add "$SERVER_NAME" "$SERVER_HOSTGROUP_NAME" "$AGENT_HOST" -f $HG_CONF_JSON -a "subject=Adding the Agent to Host Group&description=Adding the $AGENT_HOST agent to the $SERVER_HOSTGROUP_NAME Host Group for Managing Kubernetes Workloads" >$TMP_OUTPUT_FILE 2>&1
rc=$?
if [ $rc -ne 0 ]; then
  grep -i "already exists in hostgroup" $TMP_OUTPUT_FILE
  rc=$?
  if [ $rc -eq 0 ]; then
    echo "This error can be ignored"
    rm -f $TMP_OUTPUT_FILE
  else
    echo "Adding the Agent to Host Group failed, please check logs"
    [[ $TRACE == "true" ]] || exit 1
    echo "Trace mode enabled, sleeping"
    sleep infinity
  fi
fi

#Handle SSL (helm parameter agent.ssl, only relevant when setting specific agents, not when Server is SSL by default)
if [[ $SSL == "true" ]]; then
  log "Set agent comm to SSL"

  log "Check pre-req: min ctm version is 9.21.215"
  # Another option to get aapi version: curl https://clm-tlv-sxkhkq:8443/automation-api/build_time.txt --insecure
  ctm_ver=$(ctm -v)
  log "Found version:"
  log "$ctm_ver"
  number=$(echo "$ctm_ver" | awk -F'.' '{ printf("%d%02d%03d\n", $1, $2, $3) }')
  log "Convert to number:"
  log "$number"
  if [ "$number" -lt "921215" ]; then
    echo "Set agent comm SSL failed, ensure aapi version is 9.21.215 or later"
    [[ $TRACE == "true" ]] || exit 1
    echo "Trace mode enabled, sleeping"
    sleep infinity
  fi

  log "Calling config to register Agent as SSL on the server:"
  ctm config server:agent::update "$SERVER_NAME" "$AGENT_HOST" sslState Enabled
  rc=$?
  if [ $rc -ne 0 ]; then
    echo "Set agent comm SSL failed (error rc), please check logs"
    [[ $TRACE == "true" ]] || exit 1
    echo "Trace mode enabled, sleeping"
    sleep infinity
  fi
  #This may be redundant as it's already updated in the docker image
  log "Verify agent has updated comm to SSL:"
  SSL_MODE=$(ctmcfg -table CONFIG -action DISPLAY -parameter COMMOPT -quiet_mode Y | awk '{ print $2 }')
  log "SSL_MODE: "
  log "$SSL_MODE"
  if [ "$SSL_MODE" != "SSL=Y" ]; then
      echo "Set agent comm SSL failed (CONFIG.dat not updated), please check logs"
      [[ $TRACE == "true" ]] || exit 1
      echo "Trace mode enabled, sleeping"
      sleep infinity
  fi

fi

log 'Print CONFIG.dat content'
cat "$CONTROLM"/data/CONFIG.dat

log "Ready for Managing Kubernetes Workloads with Control-M"
touch /tmp/healthy

# Restore stdout and stderr
exec >&8-
exec 2>&9-

# Cleanup: terminate (gracefully) tee process
pkill -TERM -o tee

exec ./server_keep_alive.sh
