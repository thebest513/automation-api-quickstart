#!/bin/bash
if [ "$(id -u)" -ge 1000 ] ; then
    sed -e "/^controlm:/c controlm:x:$(id -u):$(id -g):controlm:/home/contorlm:/usr/sbin/nologin" /etc/passwd > /tmp/passwd
    cat /tmp/passwd > /etc/passwd
    rm /tmp/passwd
fi
cd "$(dirname "$0")" || exit 1
function log() { echo -e "\n$(date +%F" "%H:%M:%S) = $0 = $1 \n"; }
function printEnvVar() {
  echo "$1=${!1}"
  if [[ $2 == true && -z ${!1} ]]; then
    echo "Environment variable $1 should be defined"
    exit 1
  fi
}
log "Initializing Agent container"
source ~/.bash_profile

AGENT_HOST=$(hostname)
USER=$(whoami)
PERSISTENT_VOL="/home/${USER}/persistent_folder/$AGENT_HOST"
FOLDERS_EXISTS=false
AGENT_REGISTERED=false

log "Container environment:"
printEnvVar "AGENT_NFS_MODE" false
printEnvVar "AGENT_PORT" true
printEnvVar "AGENT_TOKEN_TAG" false
printEnvVar "AAPI_ENDPOINT" true
printEnvVar "SERVER_HOST" false
printEnvVar "SERVER_HOSTGROUP_NAME" true
printEnvVar "SERVER_NAME" true
printEnvVar "SECONDARY_SERVER_HOST" false
printEnvVar "PERSISTENT_VOL" true
printEnvVar "AAPI_JAVA_HOME" true
printEnvVar "BMC_INST_JAVA_HOME" true
printEnvVar "CONTROLM" true
printEnvVar "TRACE" false

log "Print image version"
cat ~/VERSION

log "Print OS version"
cat /etc/almalinux-release
uname -a

log "Print java version"
"$BMC_INST_JAVA_HOME"/bin/java -version

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

if [[ -z "${SERVER_HOST}" ]]; then
  log "Server host is not set, will be detected automatically"
  SERVER_HOST=$(ctm config servers::get | jq --arg SERVER_NAME "$SERVER_NAME" --exit-status -r '.[] | select(.name == $SERVER_NAME) | .host')
  log "Server host set to $SERVER_HOST for $SERVER_NAME"
fi

ACTIVE_SERVER_HOST=$SERVER_HOST # defines active server host
if [[ -n "${SECONDARY_SERVER_HOST}" ]]; then
  log "Check connection to Control-M/Server ${SERVER_NAME}"
  SERVER_PORT=$(ctm config systemsettings:server::get "${SERVER_NAME}" | jq -r '.[] | select(.name == "CTMS_PORT_NUM") | .value')
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
fi

log 'Map Agent data folders to persistent volume.'
if [ ! -d "$PERSISTENT_VOL"/status ]; then
  log "Persistent connection : internal AR keep-alive"
  {
    echo "AR_PING_TO_SERVER_IND Y"
    echo "AR_PING_TO_SERVER_INTERVAL 30"
    echo "AR_PING_TO_SERVER_TIMEOUT 60"
    echo "DISABLE_CM_SHUTDOWN Y"
  } >>"$CONTROLM"/data/CONFIG.dat
  touch "$CONTROLM"/data/DISABLE_CM_SHUTDOWN_Y.cfg

  log "Update Agent configuration file with current hostname"
  ctmcfg -table CONFIG -action update -parameter INSTALL_HOSTNAME -value "${AGENT_HOST}"
  ctmcfg -table CONFIG -action update -parameter LOCALHOST -value "${AGENT_HOST}"
  ctmcfg -table CONFIG -action update -parameter PHYSICAL_UNIQUE_AGENT_NAME -value "${AGENT_HOST}" # relevant on for Helix

  # Agent is set to NFS only for update "*_is_alive" files under temp, the following settings will disable functionality that NFS setting trigger
  # Next version will have one setting in CONFIG instead
  if [[ -n $AGENT_NFS_MODE && $AGENT_NFS_MODE == "true" ]]; then
    log "Enforce NFS mode for Agent"
          ctmcfg -table CONFIG -action update -parameter INSTALL_TYPE -value "NFS"
    ctmcfg -table CONFIG -action update -parameter PERFORM_IO_CHECK -value "N"
    ctmcfg -table CONFIG -action update -parameter SPLIT_DAILYLOG -value "N"
    ctmcfg -table CONFIG -action update -parameter CHECK_NFS_CLOCK -value 0
    sed -i '2i exit 0' "$CONTROLM/"scripts/check_nfs_can_run.sh
    sed -i '448i INSTALL_TYPE=LOCAL' "$CONTROLM/"scripts/set_agent_mode
    sed -i '546i INSTALL_TYPE=LOCAL' "$CONTROLM/"scripts/shagent
    sed -i '780i INSTALL_TYPE=LOCAL' "$CONTROLM/"scripts/shut-ag
    sed -i '1657i INSTALL_TYPE=LOCAL' "$CONTROLM/"scripts/start-ag
    sed -i '5i INSTALL_TYPE=LOCAL' "$CONTROLM/"scripts/ag_check_jobs
    sed -i '63i INSTALL_TYPE=LOCAL' "$CONTROLM/"scripts/ag_diag_comm
  fi

  log 'The first time the Agent is using the persistent volume, moving folders to persistent volume'
  # no agent files exist in PV, copy the current agent files to PV
  mkdir "$PERSISTENT_VOL"
  mv "$CONTROLM/"backup "$CONTROLM/"capdef "$CONTROLM/"dailylog "$CONTROLM/"data "$CONTROLM/"measure "$CONTROLM/"onstmt "$CONTROLM/"procid "$CONTROLM/"proclog "$CONTROLM/"status "$CONTROLM/"sysout "$CONTROLM/"temp -t "$PERSISTENT_VOL"
  #mkdir -p "$PERSISTENT_VOL"/cm/AI
  #mv "$CONTROLM/"cm/AI/ccp_cache "$CONTROLM"/cm/AI/CustomerLogs "$CONTROLM"/cm/AI/data -t "$PERSISTENT_VOL"/cm/AI
else
  log 'This is not the first time the Agent is running using this persistent volume, mapping folder to existing persistent volume'
  FOLDERS_EXISTS=true
  rm -Rf "$CONTROLM/"backup "$CONTROLM/"capdef "$CONTROLM/"dailylog "$CONTROLM/"data "$CONTROLM/"measure "$CONTROLM/"onstmt "$CONTROLM/"procid "$CONTROLM/"proclog "$CONTROLM/"status "$CONTROLM/"sysout "$CONTROLM/"temp 
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


PEM_FILE=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
if [[ -f $PEM_FILE ]]; then
  log "Install K8s certificates for AI server"
  KEYSTORE="$CONTROLM/"cm/AI/data/security/apcerts
  KSPASS=appass
  NUM_CERTS=$(grep -c 'END CERTIFICATE' $PEM_FILE)

  for N in $(seq 0 $((NUM_CERTS - 1))); do
    # remove existing certificate to avoid an issue when the CA certificate is renewed
    "$BMC_INST_JAVA_HOME"/bin/keytool -delete -alias "kube-pod-ca-$N" -keystore "$KEYSTORE" -storepass $KSPASS >/dev/null 2>&1
    awk "n==$N { print }; /END CERTIFICATE/ { n++ }" $PEM_FILE |
      "$BMC_INST_JAVA_HOME"/bin/keytool -noprompt -import -trustcacerts -alias "kube-pod-ca-$N" -keystore "$KEYSTORE" -storepass $KSPASS
  done
fi

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
  jq -n --argjson connectionInitiator '"AgentToServer"' --argjson serverHostName '"'"$ACTIVE_SERVER_HOST"'"' --argjson tag '"'"$AGENT_TOKEN_TAG"'"' --argjson sslState '"Disabled"' \
      '{connectionInitiator: $connectionInitiator, serverHostName: $serverHostName, tag: $tag} | with_entries(select(.value != null and .value != ""))' > agent_configuration.json
  cat agent_configuration.json
  ctm provision agent::setup "$SERVER_NAME" "$AGENT_HOST" "$AGENT_PORT" -f agent_configuration.json -a "subject=Provisioning the Agent&description=Provisioning the $AGENT_HOST agent for Managing Kubernetes Workloads"
  rc=$?
  cp ~/provision*.log "$CONTROLM/"proclog
  if [ $rc -ne 0 ]; then
    echo "Provision failed, please check logs"
    [[ $TRACE == "true" ]] || exit 1
    echo "Trace mode enabled, sleeping"
    sleep infinity
  fi
fi

#log "Starting Application Integrator plugin container"
#"$CONTROLM"/cm/AI/exe/cm_container start &
#log "Check if Application Integrator plugin container has started successfully"
#while ! "$CONTROLM"/cm/AI/exe/cm_container status; do
#  log "Application Integrator plugin container may be down, will retry in $timeout seconds"
#  sleep $timeout
#done

log "Checking Agent communication with Control-M Server"
ag_diag_comm
ctmaggetcm

if [[ $TRACE == "true" ]]; then
  log "Check if Control-M/Agent is available"
  ctm config server:agents::get "$SERVER_NAME" "$AGENT_HOST" | jq --arg AGENT_HOST "$AGENT_HOST" --exit-status '.agents[] | select(.status == "Available" and .nodeid == $AGENT_HOST)'
  ctm config server:agent::ping "$SERVER_NAME" "$AGENT_HOST"
fi

log "Adding the Agent to Host Group"
ctm config server:hostgroup:agent::add "$SERVER_NAME" "$SERVER_HOSTGROUP_NAME" "$AGENT_HOST" -a "subject=Adding the Agent to Host Group&description=Adding the $AGENT_HOST agent to the $SERVER_HOSTGROUP_NAME Host Group for Managing Kubernetes Workloads"

log "Ready for Managing Kubernetes Workloads with Control-M"
touch /tmp/healthy

bash ./server_keep_alive.sh
