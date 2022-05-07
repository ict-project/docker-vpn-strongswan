#!/bin/bash

SECRET_PREFIX="$1"
SECRET_SUFFIX="$2"
SECRET_PREFIX_PK="${SECRET_PREFIX}private-key${SECRET_SUFFIX}"
SECRET_PREFIX_PC="${SECRET_PREFIX}public-cert${SECRET_SUFFIX}"
SECRET_PREFIX_DN="${SECRET_PREFIX}public-dn${SECRET_SUFFIX}"
SECRET_PREFIX_SE="${SECRET_PREFIX}secrets${SECRET_SUFFIX}"
PLACEHOLDER="# Placeholder for server"

CA_PRIVATE_KEY="ca-key.pem"
CA_PUBLIC_CERT="ca-cert.pem"
SERVER_PRIVATE_KEY="server-key.pem"
SERVER_PUBLIC_CERT="server-cert.pem"
SERVER_PUBLIC_DN="server-dn.txt"
SERVER_PUBLIC_CSR="server-csr.pem"
SERVER_OPENSSL_CNF="server-openssl.cnf"
SERVER_SECRETS="ipsec.secrets"
GIT_VERSION=$(git describe 2> /dev/null || echo unknown)

if ! command -v openssl &> /dev/null ; then
    echo "openssl tool not found!!!"
    exit 1
fi

if [[ ! -f "Dockerfile" ]]; then
    echo "Dockerfile is mising!!!"
    exit 2
fi

if [[ "PREFIX$SECRET_PREFIX" == "PREFIX" ]]; then
    test -f "$SERVER_PRIVATE_KEY.secret" && mv -f "$SERVER_PRIVATE_KEY.secret" "$SERVER_PRIVATE_KEY"
    test -f "$SERVER_PUBLIC_CERT.secret" && mv -f "$SERVER_PUBLIC_CERT.secret" "$SERVER_PUBLIC_CERT"
    test -f "$SERVER_PUBLIC_DN.secret" && mv -f "$SERVER_PUBLIC_DN.secret" "$SERVER_PUBLIC_DN"
    test -f "$SERVER_SECRETS.secret" && mv -f "$SERVER_SECRETS.secret" "$SERVER_SECRETS"
else
    test -f $SERVER_PRIVATE_KEY && grep -c "$PLACEHOLDER" "$SERVER_PRIVATE_KEY" > /dev/null || mv "$SERVER_PRIVATE_KEY" "$SERVER_PRIVATE_KEY.secret"
    echo "$PLACEHOLDER private key - use docker secret to replace it..." > $SERVER_PRIVATE_KEY
    SERVER_PRIVATE_KEY="$SERVER_PRIVATE_KEY.secret"

    test -f $SERVER_PUBLIC_CERT && grep -c "$PLACEHOLDER" "$SERVER_PUBLIC_CERT" > /dev/null || mv "$SERVER_PUBLIC_CERT" "$SERVER_PUBLIC_CERT.secret"
    echo "$PLACEHOLDER public cert - use docker secret to replace it..." > $SERVER_PUBLIC_CERT
    SERVER_PUBLIC_CERT="$SERVER_PUBLIC_CERT.secret"

    test -f $SERVER_PUBLIC_DN && grep -c "$PLACEHOLDER" "$SERVER_PUBLIC_DN"  > /dev/null || mv "$SERVER_PUBLIC_DN" "$SERVER_PUBLIC_DN.secret"
    echo "$PLACEHOLDER public FQDN - use docker secret to replace it..." > $SERVER_PUBLIC_DN
    SERVER_PUBLIC_DN="$SERVER_PUBLIC_DN.secret"

    test -f $SERVER_SECRETS && grep -c "$PLACEHOLDER" "$SERVER_SECRETS"  > /dev/null || mv "$SERVER_SECRETS" "$SERVER_SECRETS.secret"
    echo "$PLACEHOLDER secrets - use docker secret to replace it..." > $SERVER_SECRETS
    SERVER_SECRETS="$SERVER_SECRETS.secret"
fi

if [[ ! -f "$SERVER_SECRETS" ]]; then
    echo "You must create file $SERVER_SECRETS!!!"
    echo "You can use ipsec.secrets.template ..."
    exit 3
fi

if [[ ! -f "$CA_PRIVATE_KEY" ]]; then
    echo "Generating CA private key ($CA_PRIVATE_KEY)..."
    openssl genrsa -out $CA_PRIVATE_KEY 4096
    chmod 400 $CA_PRIVATE_KEY
    echo "Done..."
fi

if [[ ! -f "$CA_PUBLIC_CERT" ]]; then
    echo "Generating CA public certificate ($CA_PUBLIC_CERT)..."
    openssl req -x509 -new -nodes -key $CA_PRIVATE_KEY -sha256 -days 1826 \
        -out $CA_PUBLIC_CERT -subj '/CN=VPN root CA'
    echo "Done..."
fi

if [[ ! -f "$SERVER_PRIVATE_KEY" ]]; then
    echo "Generating server private key ($SERVER_PRIVATE_KEY)..."
    openssl genrsa -out $SERVER_PRIVATE_KEY 4096
    chmod 400 $SERVER_PRIVATE_KEY
    echo "Done..."
fi

if [[ ! -f "$SERVER_PUBLIC_CSR" ]]; then
    echo "Generating server CSR ($SERVER_PUBLIC_CSR)..."
    echo "Provide Common Name (FQDN):"
    read SERVER_PUBLIC_FQDN
    openssl req -new  -subj "/CN=$SERVER_PUBLIC_FQDN"  \
        -addext "subjectAltName=DNS:$SERVER_PUBLIC_FQDN" \
        -addext "basicConstraints=CA:FALSE" \
        -addext "extendedKeyUsage=serverAuth,1.3.6.1.5.5.8.2.2"  \
        -key $SERVER_PRIVATE_KEY -out $SERVER_PUBLIC_CSR
    openssl req -in $SERVER_PUBLIC_CSR -text -noout
    echo "Done..."
fi

openssl req -in $SERVER_PUBLIC_CSR -noout -subject | sed 's/.*CN *= *\([^, ]*\).*/\1/' > $SERVER_PUBLIC_DN

if [[ ! -f "$SERVER_PUBLIC_CERT" ]]; then
    echo "Generating server public certificate ($SERVER_PUBLIC_CERT)..."
    cat << EOF >> $SERVER_OPENSSL_CNF
[ v3_req ]
subjectAltName          = DNS:$(cat $SERVER_PUBLIC_DN)
basicConstraints        = CA:FALSE
extendedKeyUsage        = serverAuth,1.3.6.1.5.5.8.2.2
EOF
    openssl x509 -req -in $SERVER_PUBLIC_CSR \
        -CA $CA_PUBLIC_CERT -CAkey $CA_PRIVATE_KEY -out $SERVER_PUBLIC_CERT \
        -CAcreateserial -days 365 -sha256 -extensions v3_req -extfile $SERVER_OPENSSL_CNF
    rm $SERVER_OPENSSL_CNF
    echo "Done..."
    echo
    openssl x509 -noout -text -in $SERVER_PUBLIC_CERT
    echo
fi

openssl x509 -noout -subject -in $SERVER_PUBLIC_CERT | sed 's/.*CN *= *\([^, ]*\).*/\1/' > $SERVER_PUBLIC_DN

echo "Building image..."
docker image build --tag vpn-strongswan:$GIT_VERSION .
echo "Done..."

echo
echo "You should install this CA certificate on your devices ($CA_PUBLIC_CERT):"
cat $CA_PUBLIC_CERT
echo
if [[ "PREFIX$SECRET_PREFIX" == "PREFIX" ]]; then
echo "In order to run interactively use this command:"
echo "docker run --read-only --cap-add NET_ADMIN --rm -it -p 4500:4500/udp -p 500:500/udp vpn-strongswan:$GIT_VERSION"
echo
echo "In order to run in normal mode use this command:"
echo "docker run --read-only --cap-add NET_ADMIN -d -p 4500:4500/udp -p 500:500/udp vpn-strongswan:$GIT_VERSION"
echo
else
echo "In order to create secrets use this commands:"
echo "docker secret create $SECRET_PREFIX_PK $SERVER_PRIVATE_KEY"
echo "docker secret create $SECRET_PREFIX_PC $SERVER_PUBLIC_CERT"
echo "docker secret create $SECRET_PREFIX_DN $SERVER_PUBLIC_DN"
echo "docker secret create $SECRET_PREFIX_SE $SERVER_SECRETS"
echo
SECRETS="$SECRETS --secret source=$SECRET_PREFIX_PK,target=/etc/ipsec.d/private/server-key.pem,mode=0400,uid=100,gid=101"
SECRETS="$SECRETS --secret source=$SECRET_PREFIX_PC,target=/etc/ipsec.d/certs/server-cert.pem,mode=0400,uid=100,gid=101"
SECRETS="$SECRETS --secret source=$SECRET_PREFIX_DN,target=/etc/ipsec.d/certs/server-dn.txt,mode=0400,uid=100,gid=101"
SECRETS="$SECRETS --secret source=$SECRET_PREFIX_SE,target=/etc/ipsec.secrets,mode=0400,uid=100,gid=101"
fi
echo "In order to run as a service use this command:"
echo "docker service create --read-only --cap-add NET_ADMIN -d $SECRETS -p 4500:4500/udp -p 500:500/udp vpn-strongswan:$GIT_VERSION"
echo
echo "You can change VPN network subnet adding option: -e INTERNAL_SUBNET=\"10.10.10.0/24\""
echo "You can change DNS servers adding option: -e DNS_ADDRESS=\"8.8.8.8,8.8.4.4\""
echo "You can force all trafic over NAT adding option: -e NAT_ALL_TRAFFIC=\"true\""
echo
echo "In order to save image use this command:"
echo "docker save -o vpn-strongswan_$GIT_VERSION.tar vpn-strongswan:$GIT_VERSION"
echo
echo "In order to load image use this command:"
echo "docker load -i vpn-strongswan_$GIT_VERSION.tar"
echo
