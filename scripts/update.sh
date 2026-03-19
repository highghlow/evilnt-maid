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

pcrs_str=$(cat "$bootinfo/pcrs.txt")
cp "$updinfo/signing_key_public.pem" "$scratch/"
cp "$updinfo/signing_key_private.pem" "$scratch/"

pushd "$scratch"

set -x

tpm2_startauthsession -S session.ctx
tpm2_policypcr -Q -S session.ctx -l "sha256:$pcrs_str" -L new.pcr.policy
tpm2_flushcontext session.ctx

openssl dgst -sha256 -sign signing_key_private.pem -out new.pcr.signature new.pcr.policy

tpm2_loadexternal -G rsa -C o -u signing_key_public.pem -c signing_key.ctx -n signing_key.name
tpm2_verifysignature -c signing_key.ctx -g sha256 -m new.pcr.policy -s new.pcr.signature -t verification.tkt -f rsassa

popd

cp "$scratch/new.pcr.policy" "$bootinfo/pcr.policy"
cp "$scratch/verification.tkt" "$bootinfo/"
echo
echo OK
