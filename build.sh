#!/bin/bash

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

if [[ ! -f "$SERVER_SECRETS" ]]; then
    echo "You must create file $SERVER_SECRETS!!!"
    echo "You can use $SERVER_SECRETS.template ..."
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

openssl req -in server-csr.pem  -noout -subject | sed 's/.*CN *= *\([^, ]*\).*/\1/' > $SERVER_PUBLIC_DN

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

openssl x509 -noout -subject -in server-cert.pem | sed 's/.*CN *= *\([^, ]*\).*/\1/' > $SERVER_PUBLIC_DN

echo "Building image..."
docker image build --tag vpn-strongswan:$GIT_VERSION .
echo "Done..."

echo
echo "You should install this CA certificate on your devices ($CA_PUBLIC_CERT):"
cat $CA_PUBLIC_CERT
echo
echo "In order to run interactively use this command:"
echo "docker run --cap-add NET_ADMIN --rm -it -p 4500:4500/udp -p 500:500/udp vpn-strongswan:$GIT_VERSION"
echo
echo "In order to run in normal mode use this command:"
echo "docker run --cap-add NET_ADMIN -d -p 4500:4500/udp -p 500:500/udp vpn-strongswan:$GIT_VERSION"
echo
echo "In order to run as a service use this command:"
echo "docker service create --cap-add NET_ADMIN -d -p 4500:4500/udp -p 500:500/udp vpn-strongswan:$GIT_VERSION"
echo
echo "You can change VPN network subnet adding option: -e INTERNAL_SUBNET=\\\"10.10.10.0/24\\\""
echo "You can change DNS servers adding option: -e DNS_ADDRESS=\\\"8.8.8.8,8.8.4.4\\\""
echo
echo "In order to save image use this command:"
echo "docker save -o vpn-strongswan_$GIT_VERSION.tar vpn-strongswan:$GIT_VERSION"
echo
echo "In order to load image use this command:"
echo "docker load -i vpn-strongswan_$GIT_VERSION.tar"
echo
