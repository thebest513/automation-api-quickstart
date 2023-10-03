FROM controlm/agent:9.21.100-k8s-openjdk
USER root
RUN chmod +w /etc/passwd
USER controlm
RUN rm -fr /home/controlm/ctm/cm/* 
COPY ./startup.sh /home/controlm/startup.sh
