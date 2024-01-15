FROM almalinux:8

ARG AAPI_END_POINT
ARG AAPI_USER
ARG AAPI_PASS
ARG AGENT_IMAGE_NAME

#Environment setting
ENV OSACCOUNT="ctmag"
ENV OSPASSWORD="ctmag"
ENV HOMEDIR="/home/ctmag"

LABEL Description="This is a Control-M/Agent image that planned to run in K8s env"

WORKDIR /root

# install basic packages
RUN  yum -y update \
	&& yum -y install wget \
	&& yum -y install unzip \
	&& yum -y install psmisc  \
	&& yum -y install net-tools \
	&& yum -y install bc \
    && yum -y install which \
	&& yum -y install procps \
	&& yum -y install jq \
# install libnsl
	&& wget https://vault.centos.org/centos/8/BaseOS/x86_64/os/Packages/libnsl-2.28-164.el8.x86_64.rpm \
    && rpm -ivh libnsl-2.28-164.el8.x86_64.rpm --force --nodeps \
# install nodejs
	&& curl --silent --location https://rpm.nodesource.com/setup_16.x | bash - \
	&& yum -y install nodejs \
	&& node -v \
	&& npm -v \
# install java 11
	&& yum -y install java-11-openjdk \
	&& java -version \
# install aapi CLI
	&& wget --no-check-certificate $AAPI_END_POINT/ctm-cli.tgz \
	&& npm install -g ctm-cli.tgz \
	&& ctm -v \
	&& rm -rf $AAPI_END_POINT/ctm-cli.tgz \
# create controlm useruser
	&& useradd -d $HOMEDIR -s /bin/bash -p $OSPASSWORD -m $OSACCOUNT \
	&& chmod -R 755 $HOMEDIR \
	&& yum clean all \
	&& rm -rf /var/cache/yum

USER $OSACCOUNT
WORKDIR $HOMEDIR

# entry point scripts
COPY container_agent_startup.sh /tmp
COPY agent_configuration.json /tmp
COPY ctmhost_keepalive.sh /tmp
COPY decommission_controlm.sh /tmp

RUN cp /tmp/*.sh /$HOMEDIR \
	&& chmod +x *.sh \
# Create AAPI env
	&& ctm env add myenv $AAPI_END_POINT $AAPI_USER $AAPI_PASS \
# install agent, setup will be done during statup
	&& ctm provision image $AGENT_IMAGE_NAME && echo installation ended successfully \
	&& ctm env delete myenv \
# Persistent connection : internal AR keep-alive and configure agent parameters
	&& echo "AR_PING_TO_SERVER_IND Y" >> $HOMEDIR/ctm/data/CONFIG.dat \
	&& echo "AR_PING_TO_SERVER_INTERVAL 30" >> $HOMEDIR/ctm/data/CONFIG.dat \
	&& echo "AR_PING_TO_SERVER_TIMEOUT 60" >> /$HOMEDIR/ctm/data/CONFIG.dat \
	&& echo "DISABLE_CM_SHUTDOWN Y" >> $HOMEDIR/ctm/data/CONFIG.dat \
    && touch $HOMEDIR/ctm/data/DISABLE_CM_SHUTDOWN_Y.cfg \
# I18N (Foreign Language Support)default LATIN-1
	&& sed -i "s/LATIN-1/CJK/g" $HOMEDIR/ctm/data/CONFIG.dat \
	&& sed -i "s/UTTIMEOUT\s\+120/UTTIMEOUT 360/g" $HOMEDIR/ctm/data/CONFIG.dat \
	&& sed -i "s/LOGKEEPDAYS\s\+1/LOGKEEPDAYS 14/g" $HOMEDIR/ctm/data/CONFIG.dat \
# APPLICATION_LOCALE (CJK Encoding) default null. Alternative to UTF-8 is BIG5
	&& echo "APPLICATION_LOCALE  UTF-8" >> $HOMEDIR/ctm/data/OS.dat \
	&& sed -i "s/MEMNAME/JOBNAME/g" $HOMEDIR/ctm/data/OS.dat \
# Delete redundant files to reduce image size
	&& rm -rf $HOMEDIR/bmcperl/man \
	&& rm -rf $HOMEDIR/BMCINSTALL \
	&& rm -rf $HOMEDIR/ctm/temp/*.BIN \
    && rm -rf $HOMEDIR/bmcperl/bmcperl_V1/man \
	&& rm -fr $HOMEDIR/ctm/toolbox/Usage_Measurement.jar \
    && rm -f $HOMEDIR/ctm/exe_9.0.20.200/jars/sshd-common-2.6.001-CTMAG.jar \
# enable controlm agent utilities
	&& echo "source $HOMEDIR/.bash_profile" >> $HOMEDIR/.bashrc \
# install kubectl
	&& curl -sLO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
	&& chmod +x kubectl \
	&& mkdir -p ~/.local/bin \
	&& mv ./kubectl ~/.local/bin/kubectl \
	&& echo PATH="$PATH:~/.local/bin/">>~/.bash_profile \
	&& echo export PATH>>~/.bash_profile

CMD ["./container_agent_startup.sh"]
