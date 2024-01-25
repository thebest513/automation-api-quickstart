FROM almalinux:8
LABEL Description="This is a Control-M/Agent image that planned to run in K8s env"
ENV HOMEDIR="/home/controlm"

RUN echo "Create controlm user" \
    && useradd -d $HOMEDIR -s /bin/bash -m controlm  \
    && chmod -R 755 $HOMEDIR \
    # && echo "add controlm user and root to soduers list" \
    # && echo 'root ALL=(ALL) ALL' >> /etc/sudoers \
    # && echo 'controlm ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers \
    && echo "Update Centos to the latest version" \
    && yum -y -q update \
    && echo "The next packages used by Control-M/Agent" \
    && echo "   binutils used for strings" \
    && echo "   hostname used for hostname" \
    && echo "   libnsl used for perl" \
    && echo "   ncurses used for installer engine" \
    && echo "   net-tools used for netstat and ss" \
    && echo "   procps used for ps" \
    && echo "   psmisc used for pstree" \
    && echo "   which used for which" \
    && echo "   jq used for creating JSON config files" \
    && echo "   unzip used for unzip" \
    # && echo "   sudo used for sudo" \
    && echo "Install required packages for Control-M/Agent" \
    && yum install -y -q --noplugins --setopt=install_weak_deps=0 \
                    #   java-11-openjdk-headless \
                      net-tools \
                      procps \
                      psmisc \
                      which \
                      jq \
                      unzip \
                    #   sudo \
    # && curl -sLO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
    # && install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl \
    # && kubectl version --client || exit 1 \
    # && java -version || exit 1 \
    # && kubectl version --client || exit 1 \
    && yum clean all

USER controlm
WORKDIR $HOMEDIR

ARG EXT_AUTO_DEPLOY=file:///tmp/
ARG EXT_APPLICATION_ARTIFACTS_JSON_URL=file:///tmp/
# ARG EXT_AUTO_DEPLOY=https://s3.amazonaws.com/bucket_name/installation
# ARG EXT_APPLICATION_ARTIFACTS_JSON_URL=https://s3.amazonaws.com/bucket_name/install-configurations
ARG AGENT_IMAGE_NAME=Agent
ARG NODEJS_VERSION="node-v16.13.0-linux-x64"
ARG JAVA_VERSION="zulu11.70.15-ca-jdk11.0.22-linux_x64"

# ENV BMC_INST_JAVA_HOME=/etc/alternatives/jre_11_openjdk

COPY --chown=controlm:controlm startup.sh /tmp
COPY --chown=controlm:controlm ctmhost_keepalive.sh /tmp
COPY --chown=controlm:controlm decommission_controlm.sh /tmp
COPY --chown=controlm:controlm Agent.Linux.json /tmp
COPY --chown=controlm:controlm DRFZ4.9.0.21.200_Linux-x86_64.tar.Z /tmp
COPY --chown=controlm:controlm AI_Kubernetes.Linux.json /tmp
COPY --chown=controlm:controlm AI_Kubernetes.ctmai /tmp
COPY --chown=controlm:controlm ctm-cli.tgz /tmp
COPY --chown=controlm:controlm ${JAVA_VERSION}.zip /tmp
COPY --chown=controlm:controlm sleep_for_20sec_job.yaml /tmp

RUN cp /tmp/*.sh $HOMEDIR \
    && cp /tmp/sleep_for_20sec_job.yaml $HOMEDIR \
	&& chmod +x *.sh \
    && echo "Install java" \
    && unzip /tmp/${JAVA_VERSION}.zip -d $HOMEDIR \
    && export BMC_INST_JAVA_HOME="$HOMEDIR/$JAVA_VERSION" \
    && echo "Install Node.Js and Automation API CLI" \
    && export NODEJS_HOME="$HOMEDIR/${NODEJS_VERSION}" \
    && export PATH="$PATH:$NODEJS_HOME/bin:$BMC_INST_JAVA_HOME/bin" \
    && curl -so node.tar.xz "https://nodejs.org/dist/v16.13.0/${NODEJS_VERSION}.tar.xz" \
    && xz -d node.tar.xz \
    && tar -xf node.tar \
    && rm node.tar \
    # && curl -sO https://s3-us-west-2.amazonaws.com/controlm-appdev/release/latest/ctm-cli.tgz \
    && npm -g install /tmp/ctm-cli.tgz \
    && echo "Provision Control-M/Agent" \
    && npx ctm env config EXT_AUTO_DEPLOY $EXT_AUTO_DEPLOY \
    && npx ctm env config EXT_APPLICATION_ARTIFACTS_JSON_URL $EXT_APPLICATION_ARTIFACTS_JSON_URL \
    && npx ctm provision image $AGENT_IMAGE_NAME || exit 1 \
    && echo "source .bash_profile" >> .bashrc \
    && echo "Provision Control-M Application Integrator KUBERNETES job type" \
    && ctm provision image AI_Kubernetes \
    && ~/ctm/cm/AI/exe-*/get_plugins | grep KUBERNETES \
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
    && rm -rf install bmcnode/$NODEJS_VERSION $NODEJS_HOME node_modules .npm ctm-cli.tgz package.json package-lock.json ctm/cm/AI/ipp \
    # && cp -r $HOMEDIR/BMCINSTALL/external_java_path* $HOMEDIR/BMCINSTALL/scripts . \
    # && rm -rf $HOMEDIR/BMCINSTALL/* \
    # && mv external_java_path* scripts BMCINSTALL/ \
    && rm -f /tmp/DR*.Z \
    && rm -f /tmp/ctm-cli.tgz \
    && rm -f /tmp/${JAVA_VERSION}.zip \
# install kubectl
    && echo "Install kubectl" \
	&& curl -sLO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
	&& chmod +x kubectl \
	&& mkdir -p $HOMEDIR/.local/bin \
	&& mv ./kubectl $HOMEDIR/.local/bin/kubectl \
	&& echo PATH="$PATH:$HOMEDIR/.local/bin/:$HOMEDIR/ctm/scripts:$HOMEDIR/ctm/exe:$HOMEDIR/ctm_cli">>$HOMEDIR/.bash_profile \
	&& echo export PATH>>$HOMEDIR/.bash_profile \
	&& echo "source $HOMEDIR/.bash_profile" >> $HOMEDIR/.bashrc \
	&& source $HOMEDIR/.bash_profile

CMD ["./startup.sh"]