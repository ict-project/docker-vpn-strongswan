 
FROM alpine:latest
LABEL maintaner="Mariusz Ornowski <mariusz.ornowski@ict-project.pl>"
LABEL description="VPN server (strongswan)"

VOLUME [ "/etc/ipsec.d/certs", "/etc/ipsec.d/private" ]

ADD server-key.pem /etc/ipsec.d/private/server-key.pem
ADD server-cert.pem /etc/ipsec.d/certs/server-cert.pem
ADD server-dn.txt /etc/ipsec.d/certs/server-dn.txt
ADD ipsec.secrets /etc/ipsec.secrets
ADD entrypoint.sh /root/entrypoint.sh

RUN apk add --update strongswan ufw iproute2 && \
    rm -rf /var/cache/apk/* && \
    chmod +x /root/entrypoint.sh

EXPOSE 500/udp
EXPOSE 4500/udp

ENTRYPOINT [ "/root/entrypoint.sh" ]
