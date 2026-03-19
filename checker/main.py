#!/usr/bin/env python

from flask import Flask, send_from_directory, request
import os
import cryptography.exceptions
from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import padding, ec
from cryptography.hazmat.primitives.serialization import load_pem_public_key
from cryptography.exceptions import InvalidSignature
import base64
import io
import hashlib

with open('auth_key_public.pem', 'rb') as f:
    public_key = load_pem_public_key(f.read(), default_backend())
print("Loaded key:", public_key)

app = Flask(__name__)

if "EVM_ASSETS" in os.environ:
    filedir = os.environ["EVM_ASSETS"]
else:
    filedir = os.path.join(os.path.dirname(__file__), "assets")
print("Serving from:", filedir)

ESCAPE = b'~'
ZERO = b'0'

def nzcdecode(inb):
    inf = io.BytesIO(inb)
    outf = io.BytesIO()
    while True:
        bt = inf.read(1)
        if bt == b'':
            break
        out = bt
        if bt == ESCAPE:
            bt2 = inf.read(1)
            if bt2 == b'':
                break
            out = b'\0'
            if bt2 == ESCAPE:
                out = ESCAPE
        outf.write(out)
    return outf.getvalue()

@app.route("/verify", methods=["POST"])
def verify():
    signature = nzcdecode(base64.b64decode(request.json["data"].encode("utf-8")))
    payload_contents = (request.json["seed"]).encode("utf-8")

    print(hashlib.sha256(signature).hexdigest())
    print(hashlib.sha256(payload_contents).hexdigest())
    try:
        public_key.verify(
            signature,
            payload_contents,
            ec.ECDSA(hashes.SHA256()),
        )
    except InvalidSignature:
        print("FAIL")
        return ("signfail!", 499)
    print("OK")
    return "ok"

@app.route("/", defaults={'path': 'index.html'})
@app.route("/<path:path>")
def get_file(path):
    return send_from_directory(filedir, path)

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=1256)
