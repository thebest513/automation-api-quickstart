#------------------------------------
# Control-M/Agent docker container
#------------------------------------

FROM redhat/ubi8:latest as builder

ARG EM_SERVER
ARG EM_PORT
ARG AAPI_USER
ARG AAPI_PASSWORD
ARG AGENT_IMAGE_NAME

#Environment setting
ENV OSACCOUNT="ctmadm"
ENV OSPASSWORD="controlm"
ENV HOMEDIR="/home/ctmadm"
# install basic packages
RUN yum -y update \
	&& yum -y install wget \
	&& yum -y install unzip \
	&& yum -y install sudo \
	&& yum -y install psmisc  \
	&& yum -y install net-tools \
	&& yum -y install bc \
    && yum -y install which \
	&& yum -y install hostname
# install libnsl
RUN wget https://vault.centos.org/centos/8/BaseOS/x86_64/os/Packages/libnsl-2.28-164.el8.x86_64.rpm \
        && rpm -ivh libnsl-2.28-164.el8.x86_64.rpm --force --nodeps
 
# install nodejs
RUN curl --silent --location https://rpm.nodesource.com/setup_16.x | bash - \
	&& yum -y install nodejs \
	&& node -v \
	&& npm -v
# install java 11
RUN yum -y install java-11-openjdk \
	&& java -version

# install ctm-automation-api kit
WORKDIR /root
RUN mkdir ctm-automation-api \
	&& cd ctm-automation-api \
	&& wget https://$EM_SERVER:$EM_PORT/automation-api/ctm-cli.tgz --no-check-certificate \
	&& npm install -g ctm-cli.tgz \
	&& ctm -v \
        && rm -f /usr/lib/node_modules/ctm-cli/node_modules/mockery/package.json

# add controlm user and root to soduers list
RUN useradd -d $HOMEDIR -p $OSPASSWORD -m $OSACCOUNT \
    && chmod 755 $HOMEDIR \
	&& echo "root ALL=(ALL) ALL" >> /etc/sudoers \
	&& echo "$OSACCOUNT ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers 
	
#Add controlm endpoint
USER $OSACCOUNT 
WORKDIR $HOMEDIR 

#Copy run and resiter controlm agent script to container
COPY run_register_controlm.sh /tmp
COPY decommission_controlm.sh /tmp
COPY agent-parameters.json /tmp
COPY keep_alive.sh /tmp

# Create AAPI env
RUN ctm env add endpoint https://$EM_SERVER:$EM_PORT/automation-api $AAPI_USER $AAPI_PASSWORD \
	&& ctm env set endpoint 
	
#Provision controlm agent image
#Agent.Linux image defined rerequired agent installation media, it can includes any plugin
#The image definition is under <$EM_HOME>/ctm_em/etc/emweb/automation-api/downloads/descriptors
RUN cd \
	&& ctm provision image $AGENT_IMAGE_NAME \
#Remove the endpoint during the building
    && ctm environment delete endpoint

#install other packages, put this step after image provision since it will make provision failed
RUN sudo yum -y install procps \
	&& sudo yum -y install jq 

#Enable controlm agent utilities
RUN echo "source $HOMEDIR/.bash_profile" >> $HOMEDIR/.bashrc

#Setup language support CJK, and delete redundant JRE, to make AGENT,MFT use same. Remove OS JRE installed, and delete Agent JRE, this is to make Container image size smaller

RUN cp /tmp/run_register_controlm.sh /$HOMEDIR \
	&& cp /tmp/decommission_controlm.sh $HOMEDIR \
	&& cp /tmp/agent-parameters.json $HOMEDIR \
    && cp /tmp/keep_alive.sh $HOMEDIR \
	&& chmod +x run_register_controlm.sh \
	&& chmod +x decommission_controlm.sh \
    && chmod +x keep_alive.sh \
	&& echo "AR_PING_TO_SERVER_IND Y" >> $HOMEDIR/ctm/data/CONFIG.dat \
	&& echo "AR_PING_TO_SERVER_INTERVAL 30" >> $HOMEDIR/ctm/data/CONFIG.dat \
	&& echo "AR_PING_TO_SERVER_TIMEOUT 60" >> $HOMEDIR/ctm/data/CONFIG.dat \	
    && sed -i 's/LATIN-1/CJK/g' $HOMEDIR/ctm/data/CONFIG.dat   \
	&& echo "APPLICATION_LOCALE  UTF-8"   >> $HOMEDIR/ctm/data/OS.dat \
	&& sed -i 's/UTTIMEOUT                           120/UTTIMEOUT                           360/g' $HOMEDIR/ctm/data/CONFIG.dat   \
    && sudo yum clean all \
	&& sudo yum -y autoremove java-11-openjdk \
    && sudo ln -s $HOMEDIR/bmcjava/bmcjava-V3/bin/java /bin/java \
	&& rm -rf $HOMEDIR/bmcperl/man \
	&& rm -rf $HOMEDIR/BMCINSTALL \
	&& rm -rf $HOMEDIR/bmcperl/bmcperl_V1/man \
        && rm -fr $HOMEDIR/ctm/toolbox/Usage_Measurement.jar \
        && rm -f $HOMEDIR/ctm/exe_9.0.20.200/jars/sshd-common-2.6.001-CTMAG.jar \
        && sudo rm -fr /usr/lib/python3.6 \
        && sudo rm /var/lib/rpm/Packages \
        && sudo rm /usr/lib/node_modules/ctm-cli/node_modules/winston/node_modules/async/package.json \
	&& sudo rm -rf /var/cache/yum

#EXPOSE 7000-8000

FROM builder AS builderbase

RUN sudo rm -rf /home \
       && sudo rm -rf /tmp/*

FROM scratch AS leanimage
ENV OSACCOUNT="ctmadm"
ENV HOMEDIR="/home/ctmadm"
COPY --from=builderbase / /
COPY --from=builder --chown=${OSACCOUNT}:${OSACCOUNT} /home /home
USER $OSACCOUNT
WORKDIR $HOMEDIR

CMD ["./run_register_controlm.sh"]

