## How to build docker containers for Control-M

Tutorial on the [product web page](https://docs.bmc.com/docs/display/workloadautomation/Tutorial+-+Building+a+docker+container+for+batch+applications)
that explains how to build a docker container for batch applications.
GSS manual on [CTMAG Docker Container Manual](https://www.notion.so/ctmag-Docker-Container-Manual-ba7b2127898b4405bff141c46945e85c)
that explains how to run Control-M/Agent on a docker container.


To build container image of Control-M/Agent:  
**CTMHOST** - Control-M endpoint host  
**HTTPSPORT** - EM HTTPS port, 8443 or 8446
**USER** - Control-M user account for automation  
**PASSWORD** - Control-M account password for automation  
**AGIMG** - descriptor JSON file name with no file extension name
```bash
SRC_DIR=.
CTMHOST=<Control-M host>
HTTPSPORT=<8443 or 8446>
USER=<user>
PASSWORD=<password>
AGIMG=<descriptor_name>
sudo docker build --tag=ctmag:latest --tag=ctmag:919200 \
  --build-arg CTMHOST=$CTMHOST \
  --build-arg HTTPSPORT=$HTTPSPORT \
  --build-arg USER=$USER \
  --build-arg PASSWORD=$PASSWORD \
  --build-arg AGIMG=$AGIMG $SRC_DIR
```
  
To run & self-register the containerize Control-M/Agent to Control-M:  
**CTM_SERVER** - Control-M/Server host  
**CTM_HOSTGROUP** - Application hostgroup  
**CTM_AGENT_PORT** - Control-M/Agent port number  
```bash
CTM_SERVER=<control-m server>
CTM_HOSTGROUP=<application_hostgroup>
CTM_AGENT_PORT=<port number>
sudo docker run --net host \
  -e CTM_SERVER=$CTM_SERVER \
  -e CTM_HOSTGROUP=$CTM_HOSTGROUP \
  -e CTM_AGENT_PORT=$CTM_AGENT_PORT -dt ctmag:919200
```
To decommission Control-M/Agent container and self-unregister from Control-M:
```bash
sudo docker exec -i -t <docker container> /home/controlm/decommission_controlm.sh
sudo docker stop <docker container>
```

See the [Automation API - Services](https://docs.bmc.com/docs/display/public/workloadautomation/Control-M+Automation+API+-+Services) documentation for more information.  
See the [Automation API - Code Reference](https://docs.bmc.com/docs/display/public/workloadautomation/Control-M+Automation+API+-+Code+Reference) documentation for more information.
