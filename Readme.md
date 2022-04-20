# Simple VPN (strongswan) configuration in Docker

## Usage (regular)

In order to prepare configuration, build docker image and run container/service:
* Create file `ipsec.secrets` from `ipsec.secrets.template`.
* Run `./build.sh`. You must provide domain name (FQDN - not IP!) during building.
* Run container or service using command provided.

## Usage (with Docker secrets)

In order to prepare configuration with Docker secrets (only in Docker swarm mode) and build docker image and run service:
* Create file `ipsec.secrets.secret` from `ipsec.secrets.template`.
* Run `./build.sh vpn-`.The second parameter is a secret names prefix (in this example all secret names will start with *vpn-*). You must provide domain name (FQDN - not IP!) during building.
* Create secrets using command provided.
* Run service using command provided.

## Depedences
* OpenSSL
* Docker