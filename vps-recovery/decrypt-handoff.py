#!/usr/bin/env python3
"""Decrypt the separately AES-256-GCM encrypted VPS handoff (.enc JSON)."""
import argparse,base64,getpass,json,os,tarfile,tempfile
from pathlib import Path
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.scrypt import Scrypt
p=argparse.ArgumentParser()
p.add_argument("encrypted_file")
p.add_argument("--output",default="vps-ssh-keys.tar.gz")
a=p.parse_args()
j=json.loads(Path(a.encrypted_file).read_text())
if j.get("format")!="vps-bootstrap-v1":
    raise SystemExit("Unsupported format")
password=getpass.getpass("Separate handoff secret: ")
k=Scrypt(salt=base64.b64decode(j["salt"]),length=32,n=2**15,r=8,p=1).derive(password.encode())
plain=AESGCM(k).decrypt(base64.b64decode(j["nonce"]),base64.b64decode(j["ciphertext"]),b"vps-bootstrap-v1")
fd=os.open(a.output,os.O_CREAT|os.O_EXCL|os.O_WRONLY,0o600)
with os.fdopen(fd,"wb") as f: f.write(plain)
print("Decrypted archive:",a.output)
print("Inspect with: tar tzf",a.output)
print("Extract only in a secure directory: umask 077; tar xzf",a.output)
