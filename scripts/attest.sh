#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

if [ $# -ne 1 ]; then
        echo "usage: setup.sh <bootinfo>";
        exit 1;
fi
bootinfo=$1

scratch=$(mktemp -d -t tmp.XXXXXXXXXX)
function finish {
  rm -rf "$scratch"
}
trap finish EXIT

cd "$bootinfo"

pcrs_str=$(cat pcrs.txt)
IFS="," read -ra pcr_list <<< "$pcrs_str"
pcr1="${pcr_list[0]}"

tpm2_startauthsession --policy-session -S session.ctx
tpm2_policypcr -l sha256:"$pcrs_str" -S session.ctx
tpm2_policyauthorize -S session.ctx -i pcr.policy -n signing_key.name -t verification.tkt
tpm2_unseal -p session:session.ctx -c 0x81010031 > "$scratch"/auth_key_key.bin
tpm2_flushcontext session.ctx 

openssl enc -d -aes-256-cbc -in auth_key.pem.enc -out "$scratch"/auth_key.pem -pbkdf2 --pass file:"$scratch"/auth_key_key.bin

file "$scratch"/auth_key.pem
tpm2_loadexternal -G ecc -C n -r "$scratch"/auth_key.pem -c "$scratch"/auth_key.ctx
rm "$scratch"/auth_key.pem

dd if=/dev/urandom of="$scratch"/random.bin bs=1 count=2048
tpm2_pcrevent "$scratch"/random.bin "$pcr1"

echo -n "Enter random seed: "
read -r seed

echo -n "$seed" > "$scratch"/seed.txt

sha256sum "$scratch"/seed.txt \
        | awk '{ print "000000 " $1 }' \
        | xxd -r -c 32 > "$scratch"/seed.txt.digest
tpm2_sign -c "$scratch"/auth_key.ctx -d -f plain -g sha256 -o "$scratch"/seed.sig "$scratch"/seed.txt.digest

cp "$scratch"/seed.sig sig2.bin
sha256sum "$scratch"/seed.sig
sha256sum "$scratch"/seed.txt
nzc -e "$scratch"/seed.sig > "$scratch"/seed.sig.nzc
(cat "$scratch"/seed.sig.nzc; echo -en '\0') > "$scratch"/seed.sig.nzc.zeroterminated
qrcode -f "$scratch"/seed.sig.nzc.zeroterminated

openssl dgst -verify auth_key_public.pem -keyform pem -sha256 -signature "$scratch"/seed.sig "$scratch"/seed.txt
echo
echo OK
