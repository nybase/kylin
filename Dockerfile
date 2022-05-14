FROM apache/skywalking-java-agent:8.10.0-alpine as skywalking
FROM bitnami/jmx-exporter:latest as jmx-exporter
FROM docker.io/library/consul:latest as consul
FROM docker.io/hashicorp/consul-template:latest  as consul-template 
#FROM docker.io/tomcat:9-jdk17-temurin as tomcat
#FROM eclipse-temurin:17-jdk-centos7 as jdk17

FROM quay.io/centos/centos:stream8 as builder
ENV ver=2.1.2
WORKDIR /package
RUN yum install -y dnf-plugins-core || true ; yum install -y yum-utils || true ; \
    yum config-manager --enable PowerTools || true;yum config-manager --set-enabled powertools || true ; \
    yum config-manager --enable crb || true;\
    yum update -y ; yum repolist; yum install -y wget make gcc glibc-static ;\
    wget -c  http://smarden.org/runit/runit-$ver.tar.gz && tar zxf runit-$ver.tar.gz && cd admin/runit-$ver && ./package/install ;\
    cp -rf /package/admin/runit/command/* /usr/local/sbin/ ;
    

FROM nybase/kylin:v10

ENV TZ=Asia/Shanghai LANG=C.UTF-8 UMASK=0022 CATALINA_HOME=/usr/local/tomcat CATALINA_BASE=/app/tomcat 
ENV PATH=$CATALINA_HOME/bin:/usr/java/latest/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

COPY --from=skywalking  /skywalking/agent/          /app/skywalking/
COPY --from=jmx-exporter /opt/bitnami/jmx-exporter/ /app/jmx-exporter/
COPY --from=builder /package/admin/runit/command/ /usr/local/bin/
COPY --from=consul  /bin/consul  /usr/local/bin/
COPY --from=consul-template  /bin/consul-template /usr/local/bin/
COPY --from=tomcat  /usr/local/tomcat/ /usr/local/tomcat/
#COPY --from=jdk17  /opt/java/openjdk/ /usr/lib/jvm/java-17/

# yum only: yum-utils createrepo crontabs curl-minimal dejavu-sans-fonts iproute java-11-openjdk-devel java-17-openjdk-devel telnet traceroute pcre-devel pcre2-devel 
# alpine: openjdk8 openjdk11-jdk openjdk17-jdk font-noto-cjk consul vim

# JAVA_HOME /usr/lib/jvm/java-1.8.0 /usr/lib/jvm/java-11 /usr/lib/jvm/java-17
# google-noto-sans-cjk-ttc-fonts
RUN set -eux; mkdir -p /var/run; useradd --create-home --uid 8080 --shell /bin/bash app;\
    echo -e 'export PATH=$JAVA_HOME/bin:$PATH\n' | tee /etc/profile.d/91-env.sh ;\
    yum install -y bash ca-certificates curl wget procps psmisc iproute iputils telnet strace tzdata less tar unzip \
        tcpdump  net-tools socat  traceroute jq mtr vim createrepo logrotate crontabs dejavu-sans-fonts  pcre-devel pcre2-devel \
        gnupg libcap openssl openssh-clients   iptables  luajit  iperf3 htop rsyslog  \
        java-11-openjdk-devel java-1.8.0-openjdk-devel ; \
    yum install -y iftop runit yum-utils java-17-openjdk-devel iftop busybox-extras iproute2 runit dumb-init tini su-exec libc6-compat \
         consul consul-template font-noto-cjk wrk atop  iftop openssh-client-default luarocks pcre-dev pcre2-dev tomcat-native || true; \
    test -f /etc/pam.d/cron && sed -i '/session    required     pam_loginuid.so/c\#session    required   pam_loginuid.so' /etc/pam.d/cron ;\
    sed -i 's/^module(load="imklog"/#module(load="imklog"/g' /etc/rsyslog.conf || true;\
    mkdir -p /etc/service/cron /etc/service/syslog ;\
    bash -c 'echo -e "#!/bin/bash\nexec /usr/sbin/rsyslogd -n" > /etc/service/syslog/run' ;\
    bash -c 'echo -e "#!/bin/bash\nexec /usr/sbin/cron -f" > /etc/service/cron/run' ;\
    chmod 755 /etc/service/cron/run /etc/service/syslog/run ;\
    TOMCAT_VER=`wget -q https://mirrors.tuna.tsinghua.edu.cn/apache/tomcat/tomcat-9/ -O -|grep -v M| grep v9 |tail -1| awk '{split($5,c,">v") ; split(c[2],d,"/") ; print d[1]}'` ;\
    echo $TOMCAT_VER; wget -q -c https://mirrors.tuna.tsinghua.edu.cn/apache/tomcat/tomcat-9/v${TOMCAT_VER}/bin/apache-tomcat-${TOMCAT_VER}.tar.gz -P /tmp ;\
    mkdir -p /logs /usr/local/tomcat /app/war /app/tomcat/conf /app/tomcat/logs /app/tomcat/work /app/tomcat/bin ; tar zxf /tmp/apache-tomcat-${TOMCAT_VER}.tar.gz -C /usr/local/tomcat --strip-components 1 ;\
    rm -rf /usr/local/tomcat/webapps/* || true;\ 
    cp -rv /usr/local/tomcat/conf/server.xml /app/tomcat/conf/ ;\
    sed -i -e 's@webapps@/app/war@g' -e 's@SHUTDOWN@_SHUTUP_8080@g' /app/tomcat/conf/server.xml ;\
    mkdir -p /app/jar/conf /app/jar/lib /app/jar/tmp  /app/jar/bin ;\
    chown app:app -R /usr/local/tomcat /app /logs; \
    yum clean all; rm -rf /tmp/*

EXPOSE 8080
USER   8080
CMD ["catalina.sh", "run"]
