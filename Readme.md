# Simple VPN (strongswan) configuration in Docker

## Usage

In order to prepare configuration and build docker image:
* Create file `ipsec.secrets` from `ipsec.secrets.template`.
* Run `./build.sh`. You must provide domain name (FQDN - not IP!) during building.

## Depedences
* OpenSSL
* Docker