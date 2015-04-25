FROM debian:jessie
MAINTAINER TQ Hirsch <thequux@thequux.com>
# create the user first for a stable UID/GID
RUN addgroup --system openldap && \
    adduser --quiet --system --home /var/lib/ldap --shell /bin/false \
		    --ingroup openldap --disabled-password --disabled-login \
		    --gecos "OpenLDAP Server Account" openldap

# TODO: Rig up snapshot.debian.org.
# http://snapshot.debian.org/archive/debian/20150424T213452Z/ is where
# the scripts were written

# grab gosu for easy step-down from root, taken from
# https://github.com/docker-library/postgres/blob/e616341507a7beec3a161b0a366ba0d3400328fd/9.4/Dockerfile
RUN gpg --keyserver pool.sks-keyservers.net --recv-keys B42F6819007F00F88E364FD4036A9C25BF357DD4
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/* \
	&& curl -o /usr/local/bin/gosu -SL "https://github.com/tianon/gosu/releases/download/1.4/gosu-$(dpkg --print-architecture)" \
	&& curl -o /usr/local/bin/gosu.asc -SL "https://github.com/tianon/gosu/releases/download/1.4/gosu-$(dpkg --print-architecture).asc" \
	&& gpg --verify /usr/local/bin/gosu.asc \
	&& rm /usr/local/bin/gosu.asc \
	&& chmod +x /usr/local/bin/gosu \
	&& apt-get purge -y --auto-remove curl

# Disable configuration of SLAPD; we do the initialization at runtime.
RUN echo "slapd	slapd/no_configuration	boolean	true" |debconf-set-selections
RUN apt-get update && apt-get -y install slapd ldap-utils python3.4 python3-pip

ADD scripts /scripts
RUN pip3 install -r scripts/requirements.txt
ENV LC_ALL C.UTF-8
ENV LANG C.UTF-8
VOLUME ["/data/db", "/data/cfg"]
EXPOSE 389 636
ENTRYPOINT ["/scripts/entrypoint"]
CMD ["run"]
