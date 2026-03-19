#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

if [ $# -ne 2 ]; then
        echo "usage: setup.sh <bootinfo> <updinfo>";
        exit 1;
fi
bootinfo=$1
updinfo=$2

scratch=$(mktemp -d -t tmp.XXXXXXXXXX)
function finish {
  rm -rf "$scratch"
  echo "$scratch"
}
trap finish EXIT

echo "Setting up evint-maid..."

echo "Enter the PCR registers to use"
echo "(press Enter for defaults)"
echo -n "> "

IFS=' ' read -ra pcrs

pcrs_str=$(IFS=, ; echo "${pcrs[*]}")

pushd "$scratch"

set -x

tpm2_createprimary -Q -C o -c prim.ctx

# Creating a policy
tpm2_startauthsession -S session.ctx
tpm2_policypcr -Q -S session.ctx -l "sha256:$pcrs_str" -L pcr.policy
tpm2_flushcontext session.ctx

# Creating a policy signing key
openssl genrsa -out signing_key_private.pem 2048
openssl rsa -in signing_key_private.pem -out signing_key_public.pem -pubout

tpm2_loadexternal -G rsa -C o -u signing_key_public.pem -c signing_key.ctx -n signing_key.name

# Signing the policy
tpm2_startauthsession -S session.ctx
tpm2_policyauthorize -S session.ctx -L authorized.policy -n signing_key.name -i pcr.policy
tpm2_flushcontext session.ctx

# Creating the authorization key
openssl ecparam -name prime256v1 -genkey -noout -out auth_key.pem
openssl ec -in auth_key.pem -out auth_key_public.pem -pubout
file auth_key.pem

# Generating an 128 random byte string without zeroes
dd if=/dev/urandom of=auth_key_key.bin.zeroes bs=1 count=128
cat auth_key_key.bin.zeroes | sed 's/\x0/\x1/' > auth_key_key.bin

# Encrypting the authorization key
openssl enc -aes-256-cbc -in auth_key.pem -out auth_key.pem.enc -pbkdf2 --pass file:auth_key_key.bin

# Sealing the authorization key-key
cat auth_key_key.bin | tpm2_create -g sha256 -u auth_pcr_seal_key.pub -r auth_pcr_seal_key.priv -i- -C prim.ctx -L authorized.policy

tpm2_load -Q -C prim.ctx -u auth_pcr_seal_key.pub -r auth_pcr_seal_key.priv -n auth_pcr_seal_key.name -c auth_pcr_seal_key.ctx
tpm2_evictcontrol -c auth_pcr_seal_key.ctx 0x81010031 -C o

openssl dgst -sha256 -sign signing_key_private.pem -out pcr.signature pcr.policy

tpm2_loadexternal -G rsa -C o -u signing_key_public.pem -c signing_key.ctx -n signing_key.name
tpm2_verifysignature -c signing_key.ctx -g sha256 -m pcr.policy -s pcr.signature -t verification.tkt -f rsassa

popd
mkdir -p "$bootinfo"
mkdir -p "$updinfo"
echo -n "$pcrs_str" > "$bootinfo/pcrs.txt"
cp "$scratch/session.ctx" "$bootinfo/"
cp "$scratch/pcr.policy" "$bootinfo/"
cp "$scratch/verification.tkt" "$bootinfo/"
cp "$scratch/signing_key.name" "$bootinfo/"
cp "$scratch/auth_key.pem.enc" "$bootinfo/"
cp "$scratch/signing_key_public.pem" "$bootinfo/"
cp "$scratch/auth_key_public.pem" "$bootinfo/"

cp "$scratch/signing_key_public.pem" "$updinfo/"
cp "$scratch/signing_key_private.pem" "$updinfo/"
echo
echo OK
