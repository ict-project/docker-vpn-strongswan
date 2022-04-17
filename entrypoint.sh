#!/bin/sh

SERVER_PRIVATE_KEY_PATH="/etc/ipsec.d/private/server-key.pem"
SERVER_PUBLIC_CERT_PATH="/etc/ipsec.d/certs/server-cert.pem"
SERVER_PUBLIC_DN_PATH="/etc/ipsec.d/certs/server-dn.txt"
SERVER_SECRETS_PATH="/etc/ipsec.secrets"
SERVER_INTERFACE=$(ip route | grep default | awk '{ print $5 }')
SERVER_UFW_BEFORE_RULES="/etc/ufw/before.rules"
SERVER_UFW_SYSCTL="/etc/ufw/sysctl.conf"

if [[ ! -f "$SERVER_PRIVATE_KEY_PATH" ]]; then
    echo "Private server key is missing!"
    echo "Create file: $SERVER_PRIVATE_KEY_PATH"
    exit 10001
fi

if [[ ! -f "$SERVER_PUBLIC_CERT_PATH" ]]; then
    echo "Public certificate is missing!"
    echo "Create file: $SERVER_PUBLIC_CERT_PATH"
    exit 10002
fi

if [[ ! -f "$SERVER_PUBLIC_DN_PATH" ]]; then
    echo "FQDN is missing!"
    echo "Create file: $SERVER_PUBLIC_DN_PATH"
    exit 10003
fi

if [[ ! -f "$SERVER_SECRETS_PATH" ]]; then
    echo "Secrets file is missing!"
    echo "Create file: $SERVER_SECRETS_PATH"
    exit 10004
fi

if [[ "SUBNET$INTERNAL_SUBNET" == "SUBNET" ]]; then
    INTERNAL_SUBNET="10.10.10.0/24"
fi

if [[ "DNS$DNS_ADDRESS" == "DNS" ]]; then
    DNS_ADDRESS="8.8.8.8,8.8.4.4"
fi

echo "Generating strongswan config:"
echo "INTERNAL_SUBNET=$INTERNAL_SUBNET"
echo "DNS_ADDRESS=$DNS_ADDRESS"

cat << EOF > /etc/ipsec.conf
config setup
    charondebug="ike 1, knl 1, cfg 0"
    uniqueids=no
conn ikev2-vpn
    auto=add
    compress=no
    type=tunnel
    keyexchange=ikev2
    fragmentation=yes
    forceencaps=yes
    dpdaction=clear
    dpddelay=300s
    rekey=no
    left=%any
    leftid=@$(cat $SERVER_PUBLIC_DN_PATH)
    leftcert=server-cert.pem
    leftsendcert=always
    leftsubnet=0.0.0.0/0
    right=%any
    rightid=%any
    rightauth=eap-mschapv2
    rightsourceip=$INTERNAL_SUBNET
    rightdns=$DNS_ADDRESS
    rightsendcert=never
    eap_identity=%identity
    ike=chacha20poly1305-sha512-curve25519-prfsha512,aes256gcm16-sha384-prfsha384-ecp384,aes256-sha1-modp1024-modp2048,aes128-sha1-modp1024-modp2048,3des-sha1-modp1024-modp2048!
    esp=chacha20poly1305-sha512,aes256gcm16-ecp384,aes256-sha256,aes256-sha1,3des-sha1!
EOF
echo "Strongswan config done..."


echo "Configuring firewall:"
echo "SERVER_INTERFACE=$SERVER_INTERFACE"
echo "INTERNAL_SUBNET=$INTERNAL_SUBNET"
echo "SERVER_UFW_BEFORE_RULES=$SERVER_UFW_BEFORE_RULES"
echo "SERVER_UFW_SYSCTL=$SERVER_UFW_SYSCTL"

ufw allow 500,4500/udp

if [[ ! -f "$SERVER_UFW_BEFORE_RULES.old" ]]; then 
    cp $SERVER_UFW_BEFORE_RULES "$SERVER_UFW_BEFORE_RULES.old"
fi

echo > $SERVER_UFW_BEFORE_RULES

cat << EOF >> $SERVER_UFW_BEFORE_RULES
*nat
-A POSTROUTING -s $INTERNAL_SUBNET -o $SERVER_INTERFACE -m policy --pol ipsec --dir out -j ACCEPT
-A POSTROUTING -s $INTERNAL_SUBNET -o $SERVER_INTERFACE -j MASQUERADE
COMMIT

*mangle
-A FORWARD --match policy --pol ipsec --dir in -s $INTERNAL_SUBNET -o $SERVER_INTERFACE -p tcp -m tcp --tcp-flags SYN,RST SYN -m tcpmss --mss 1361:1536 -j TCPMSS --set-mss 1360
COMMIT

EOF

cat "$SERVER_UFW_BEFORE_RULES.old" | sed "s/^COMMIT$//" >> $SERVER_UFW_BEFORE_RULES

cat << EOF >> $SERVER_UFW_BEFORE_RULES

-A ufw-before-forward --match policy --pol ipsec --dir in --proto esp -s $INTERNAL_SUBNET -j ACCEPT
-A ufw-before-forward --match policy --pol ipsec --dir out --proto esp -d $INTERNAL_SUBNET -j ACCEPT

COMMIT

EOF

if [[ ! -f "$SERVER_UFW_SYSCTL.old" ]]; then
    cp $SERVER_UFW_SYSCTL "$SERVER_UFW_SYSCTL.old"
fi

echo > $SERVER_UFW_SYSCTL

cat "$SERVER_UFW_SYSCTL.old" >> $SERVER_UFW_SYSCTL

cat << EOF >> $SERVER_UFW_SYSCTL
net/ipv4/ip_forward=1
net/ipv4/conf/all/accept_redirects=0
net/ipv4/conf/all/send_redirects=0
net/ipv4/ip_no_pmtu_disc=1

EOF

ufw disable
ufw enable

echo "Strongswan is about to start..."
exec /usr/sbin/ipsec start --nofork
EXIT_CODE=$?
echo "Strongswan has ended ($EXIT_CODE)..."
exit $EXIT_CODE
