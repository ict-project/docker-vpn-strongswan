#!/bin/sh

SERVER_PRIVATE_KEY_PATH="/etc/ipsec.d/private/server-key.pem"
SERVER_PUBLIC_CERT_PATH="/etc/ipsec.d/certs/server-cert.pem"
SERVER_PUBLIC_DN_PATH="/etc/ipsec.d/certs/server-dn.txt"
SERVER_SECRETS_PATH="/etc/ipsec.secrets"
SERVER_INTERFACE=$(ip route | grep default | awk '{ print $5 }')
SERVER_IPSEC_CONF="/var/run/ipsec.conf"

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
echo "SERVER_IPSEC_CONF=$SERVER_IPSEC_CONF"

cat << EOF > $SERVER_IPSEC_CONF
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

/usr/sbin/ufw enable
/sbin/iptables -t nat -A POSTROUTING -s $INTERNAL_SUBNET -o $SERVER_INTERFACE -m policy --pol ipsec --dir out -j ACCEPT
/sbin/iptables -t nat -A POSTROUTING -s $INTERNAL_SUBNET -o $SERVER_INTERFACE -j MASQUERADE
/sbin/iptables -t mangle -A FORWARD --match policy --pol ipsec --dir in -s $INTERNAL_SUBNET -o $SERVER_INTERFACE -p tcp -m tcp --tcp-flags SYN,RST SYN -m tcpmss --mss 1361:1536 -j TCPMSS --set-mss 1360
/sbin/iptables -t filter -A ufw-before-forward --match policy --pol ipsec --dir in --proto esp -s $INTERNAL_SUBNET -j ACCEPT
/sbin/iptables -t filter -A ufw-before-forward --match policy --pol ipsec --dir out --proto esp -d $INTERNAL_SUBNET -j ACCEPT
/sbin/iptables -t filter -A ufw-user-input -p udp -m multiport --dports 500,4500 -j ACCEPT

echo "Firewall config done..."

echo "Strongswan is about to start..."
exec /usr/sbin/ipsec start --nofork
EXIT_CODE=$?
echo "Strongswan has ended ($EXIT_CODE)..."
exit $EXIT_CODE
