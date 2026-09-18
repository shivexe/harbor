import base64
import hashlib
import json
import pathlib
import sys
from cryptography.exceptions import InvalidSignature, InvalidTag
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey, Ed25519PublicKey
from cryptography.hazmat.primitives.ciphers.aead import AESGCM


def b64(value):
    return base64.b64encode(value).decode()


def compact(value):
    return json.dumps(value, separators=(",", ":"), ensure_ascii=False).encode()


def encrypted(plain, key, nonce, aad):
    cipher = AESGCM(key).encrypt(nonce, plain, aad.encode())
    return {"nonce": b64(nonce), "ciphertext": b64(cipher[:-16]), "tag": b64(cipher[-16:])}


def generate():
    key = bytes(range(32))
    seed = bytes(range(32, 64))
    secret = bytes(range(64, 96))
    client_nonce = bytes(range(96, 128))
    pair_id = "11111111-1111-4111-8111-111111111111"
    device_id = "22222222-2222-4222-8222-222222222222"
    vault_id = "33333333-3333-4333-8333-333333333333"
    request_id = b64(bytes(range(128, 160)))
    host = {"id": "44444444-4444-4444-8444-444444444444", "name": "Fixture", "hostname": "127.0.0.1", "port": 2222, "username": "harbor", "group": "Fixtures", "authType": "password", "password": "fixture-only", "privateKey": "", "passphrase": "", "hostKey": "", "notes": "Unicode ✓"}
    snapshot = {"version": 1, "vaultId": vault_id, "revision": 7, "generatedAt": 1800000000, "requestId": request_id, "hosts": [host]}
    payload = b64(compact(snapshot))
    signer = Ed25519PrivateKey.from_private_bytes(seed)
    signature = b64(signer.sign(b"harbor.snapshot.v1\n" + payload.encode()))
    messages = [
        ("pairRequest", secret, {"deviceId": device_id, "deviceName": "Fixture phone", "clientNonce": b64(client_nonce)}, "harbor/pair-request/v1/" + pair_id),
        ("pairResponse", secret, {"version": 1, "deviceId": device_id, "vaultId": vault_id, "syncKey": b64(key), "desktopName": "Fixture desktop"}, "harbor/pair-response/v1/" + pair_id),
        ("syncRequest", key, {"version": 1, "vaultId": vault_id, "requestId": request_id}, "harbor/sync-request/v1/" + device_id),
        ("syncResponse", key, {"payload": payload, "signature": signature}, "harbor/sync-response/v1/" + device_id),
    ]
    result = {"version": 1, "signingSeed": b64(seed), "publicKey": b64(signer.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)), "secret": b64(secret), "clientNonce": b64(client_nonce), "comparisonCode": str(int.from_bytes(hashlib.sha256(secret + client_nonce).digest()[:4], "big") % 1000000).zfill(6), "snapshot": snapshot, "payload": payload, "signature": signature, "messages": []}
    for i, (name, message_key, plain, aad) in enumerate(messages):
        nonce = bytes(range(i * 12, (i + 1) * 12))
        raw = compact(plain)
        result["messages"].append({"name": name, "key": b64(message_key), "aad": aad, "plaintext": raw.decode(), "envelope": encrypted(raw, message_key, nonce, aad)})
    salt = bytes(range(16))
    password = "fixture master passphrase"
    result["pbkdf2"] = {"password": password, "salt": b64(salt), "rounds": 600000, "key": b64(hashlib.pbkdf2_hmac("sha256", password.encode(), salt, 600000, 32))}
    return result


def verify(vectors):
    for message in vectors["messages"]:
        env = message["envelope"]
        nonce = base64.b64decode(env["nonce"], validate=True)
        cipher = base64.b64decode(env["ciphertext"], validate=True) + base64.b64decode(env["tag"], validate=True)
        key = base64.b64decode(message["key"], validate=True)
        aad = message["aad"].encode()
        assert AESGCM(key).decrypt(nonce, cipher, aad).decode() == message["plaintext"]
        for broken_cipher, broken_aad in ((cipher[:-1] + bytes([cipher[-1] ^ 1]), aad), (cipher, aad + b"x")):
            try:
                AESGCM(key).decrypt(nonce, broken_cipher, broken_aad)
                raise AssertionError("Tampering accepted")
            except InvalidTag:
                pass
    public_key = Ed25519PublicKey.from_public_bytes(base64.b64decode(vectors["publicKey"]))
    signature = base64.b64decode(vectors["signature"])
    signed = b"harbor.snapshot.v1\n" + vectors["payload"].encode()
    public_key.verify(signature, signed)
    try:
        public_key.verify(signature, signed + b"x")
        raise AssertionError("Altered signature payload accepted")
    except InvalidSignature:
        pass
    kdf = vectors["pbkdf2"]
    assert b64(hashlib.pbkdf2_hmac("sha256", kdf["password"].encode(), base64.b64decode(kdf["salt"]), kdf["rounds"], 32)) == kdf["key"]
    assert vectors == generate()
    print("Protocol vectors passed: AES-GCM, AAD/tampering, Ed25519, comparison code and PBKDF2")


if __name__ == "__main__":
    path = pathlib.Path(__file__).with_name("protocol-vectors.json")
    if "--write" in sys.argv:
        path.write_text(json.dumps(generate(), indent=2, ensure_ascii=False) + "\n")
    verify(json.loads(path.read_text()))
