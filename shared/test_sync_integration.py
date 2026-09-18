import argparse
import base64
import json
import pathlib
import socket
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
import os
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
from cryptography.hazmat.primitives.ciphers.aead import AESGCM


def encode(value):
    return json.dumps(value, separators=(",", ":")).encode()


def b64(value):
    return base64.b64encode(value).decode()


def encrypt(value, key, aad):
    nonce = os.urandom(12)
    cipher = AESGCM(key).encrypt(nonce, encode(value), aad.encode())
    return {"nonce": b64(nonce), "ciphertext": b64(cipher[:-16]), "tag": b64(cipher[-16:])}


def decrypt(envelope, key, aad):
    return json.loads(AESGCM(key).decrypt(base64.b64decode(envelope["nonce"], validate=True), base64.b64decode(envelope["ciphertext"], validate=True) + base64.b64decode(envelope["tag"], validate=True), aad.encode()))


def post(url, body):
    request = urllib.request.Request(url, encode(body), {"Content-Type": "application/json"}, method="POST")
    try:
        with urllib.request.urlopen(request, timeout=5) as response:
            return response.status, json.load(response)
    except urllib.error.HTTPError as response:
        return response.code, json.load(response)


def raw(port, data):
    with socket.create_connection(("127.0.0.1", port), timeout=5) as connection:
        connection.sendall(data)
        return int(connection.recv(1024).split(b" ")[1])


def run(executable):
    with tempfile.TemporaryDirectory(prefix="harbor-sync-check-") as directory:
        root = pathlib.Path(directory)
        host = {"id": "44444444-4444-4444-8444-444444444444", "name": "Disposable", "hostname": "127.0.0.1", "port": 2222, "username": "harbor", "group": "Tests", "authType": "password", "password": "fixture-only", "privateKey": "", "passphrase": "", "hostKey": "", "notes": ""}
        hosts = root / "hosts.json"
        hosts.write_bytes(encode([host]))
        hosts.chmod(0o600)
        invitation_file = root / "invitation.json"
        process = subprocess.Popen([executable, str(hosts), str(invitation_file)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            ready = process.stdout.readline().strip()
            assert ready.startswith("ready "), ready
            invitation = json.loads(invitation_file.read_text())
            url = invitation["url"]
            port = int(ready.split()[1])
            secret = base64.b64decode(invitation["secret"])
            device_id = "22222222-2222-4222-8222-222222222222"
            nonce = os.urandom(32)
            pair_aad = "harbor/pair-request/v1/" + invitation["pairId"]
            pair = encrypt({"deviceId": device_id, "deviceName": "Disposable verifier", "clientNonce": b64(nonce)}, secret, pair_aad)
            status, response = post(url + "/v1/pair/" + invitation["pairId"], pair)
            assert status == 202
            assert process.stdout.readline().startswith("paired ")
            status, response = post(url + "/v1/pair/" + invitation["pairId"], pair)
            assert status == 200
            paired = decrypt(response, secret, "harbor/pair-response/v1/" + invitation["pairId"])
            assert paired["vaultId"] == invitation["vaultId"] and paired["deviceId"] == device_id
            key = base64.b64decode(paired["syncKey"])
            competitor = encrypt({"deviceId": "55555555-5555-4555-8555-555555555555", "deviceName": "Other device", "clientNonce": b64(os.urandom(32))}, secret, pair_aad)
            assert post(url + "/v1/pair/" + invitation["pairId"], competitor)[0] == 403
            assert post(url + "/v1/pair/missing", pair)[0] == 410
            public_key = Ed25519PublicKey.from_public_bytes(base64.b64decode(invitation["publicKey"]))

            def sync():
                request_id = b64(os.urandom(32))
                request = encrypt({"version": 1, "vaultId": paired["vaultId"], "requestId": request_id}, key, "harbor/sync-request/v1/" + device_id)
                request["deviceId"] = device_id
                code, response = post(url + "/v1/sync", request)
                if code != 200:
                    return code, None
                signed = decrypt(response, key, "harbor/sync-response/v1/" + device_id)
                public_key.verify(base64.b64decode(signed["signature"]), b"harbor.snapshot.v1\n" + signed["payload"].encode())
                snapshot = json.loads(base64.b64decode(signed["payload"]))
                assert snapshot["requestId"] == request_id and snapshot["vaultId"] == paired["vaultId"] and snapshot["version"] == 1
                return code, snapshot

            status, snapshot = sync()
            assert status == 200 and snapshot["hosts"] == [host]
            first_revision = snapshot["revision"]
            altered = encrypt({"version": 1, "vaultId": paired["vaultId"], "requestId": b64(os.urandom(32))}, key, "harbor/sync-request/v1/" + device_id)
            altered["deviceId"] = device_id
            altered["tag"] = b64(bytes(16))
            assert post(url + "/v1/sync", altered)[0] == 400
            assert sync()[1]["revision"] == first_revision
            wrong_aad = encrypt({"version": 1, "vaultId": paired["vaultId"], "requestId": b64(os.urandom(32))}, key, "harbor/sync-request/v1/wrong-device")
            wrong_aad["deviceId"] = device_id
            assert post(url + "/v1/sync", wrong_aad)[0] == 400
            wrong_vault = encrypt({"version": 1, "vaultId": "wrong-vault", "requestId": b64(os.urandom(32))}, key, "harbor/sync-request/v1/" + device_id)
            wrong_vault["deviceId"] = device_id
            assert post(url + "/v1/sync", wrong_vault)[0] == 403
            assert raw(port, b"POST /v1/sync HTTP/1.1\r\nHost: local\r\nContent-Length: 0\r\nContent-Length: 0\r\n\r\n") == 400
            assert raw(port, b"POST /v1/sync HTTP/1.1\r\nHost: local\r\nTransfer-Encoding: chunked\r\nContent-Length: 0\r\n\r\n") == 400
            assert raw(port, b"POST /v1/sync HTTP/1.1\r\nHost: local\r\nContent-Length: 524289\r\n\r\n") == 413
            assert raw(port, b"GET /v1/sync HTTP/1.1\r\nHost: local\r\n\r\n") == 405
            assert raw(port, b"POST /v1/sync HTTP/1.1\r\nX: " + b"x" * 17000) == 431
            with socket.create_connection(("127.0.0.1", port), timeout=12) as incomplete:
                incomplete.sendall(b"POST /v1/sync HTTP/1.1\r\nHost: local\r\nContent-Length: 2\r\n\r\n{")
                assert incomplete.recv(1024) == b""
            assert sync()[0] == 200

            def command(value):
                process.stdin.write(json.dumps(value) + "\n")
                process.stdin.flush()
                assert process.stdout.readline().startswith("ok ")

            command({"op": "invite"})
            assert post(url + "/v1/pair/" + invitation["pairId"], pair)[0] == 200
            command({"op": "remove", "id": host["id"]})
            status, snapshot = sync()
            assert status == 200 and snapshot["hosts"] == [] and snapshot["revision"] > first_revision
            command({"op": "upsert", "host": host})
            assert sync()[1]["hosts"] == [host]
            command({"op": "revoke", "id": device_id})
            assert sync()[0] == 403
            command({"op": "lock"})
            try:
                post(url + "/v1/sync", {})
                raise AssertionError("Locked server stayed available")
            except urllib.error.URLError:
                pass
            print("Linux live protocol passed: pairing binding, encryption, pinned Ed25519 signatures, fresh request IDs, tamper rejection, framing bounds, deletion, revocation and lock")
        finally:
            process.terminate()
            process.wait(timeout=5)


def check_nonreading_peer(executable):
    with tempfile.TemporaryDirectory(prefix="harbor-deadline-check-") as directory:
        root = pathlib.Path(directory)
        hosts = []
        for i in range(4):
            hosts.append({"id": f"44444444-4444-4444-8444-{i:012d}", "name": "Large disposable fixture", "hostname": "127.0.0.1", "port": 2222, "username": "harbor", "group": "Tests", "authType": "password", "password": "fixture-only", "privateKey": "", "passphrase": "", "hostKey": "", "notes": "x" * 900000})
        host_file = root / "hosts.json"
        host_file.write_bytes(encode(hosts))
        host_file.chmod(0o600)
        invitation_file = root / "invitation.json"
        process = subprocess.Popen([executable, str(host_file), str(invitation_file)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            ready = process.stdout.readline().strip()
            assert ready.startswith("ready "), ready
            invitation = json.loads(invitation_file.read_text())
            secret = base64.b64decode(invitation["secret"])
            device_id = "22222222-2222-4222-8222-222222222222"
            pair = encrypt({"deviceId": device_id, "deviceName": "Deadline fixture", "clientNonce": b64(os.urandom(32))}, secret, "harbor/pair-request/v1/" + invitation["pairId"])
            path = invitation["url"] + "/v1/pair/" + invitation["pairId"]
            assert post(path, pair)[0] == 202
            assert process.stdout.readline().startswith("paired ")
            code, envelope = post(path, pair)
            assert code == 200
            paired = decrypt(envelope, secret, "harbor/pair-response/v1/" + invitation["pairId"])
            key = base64.b64decode(paired["syncKey"])
            request = encrypt({"version": 1, "vaultId": paired["vaultId"], "requestId": b64(os.urandom(32))}, key, "harbor/sync-request/v1/" + device_id)
            request["deviceId"] = device_id
            body = encode(request)
            peer = socket.socket()
            peer.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 1024)
            peer.connect(("127.0.0.1", int(ready.split()[1])))
            peer.sendall(b"POST /v1/sync HTTP/1.1\r\nHost: local\r\nContent-Length: " + str(len(body)).encode() + b"\r\n\r\n" + body)

            def active():
                process.stdin.write('{"op":"stats"}\n')
                process.stdin.flush()
                result = process.stdout.readline().strip()
                assert result.startswith("active ")
                assert process.stdout.readline().strip() == "ok stats"
                return int(result.split()[1])

            time.sleep(0.5)
            assert active() == 1, "Fixture response did not exceed the kernel send buffer"
            time.sleep(10)
            assert active() == 0, "A nonreading peer retained a connection slot beyond the total deadline"
            peer.close()
            print("Nonreading large-snapshot peer released its connection slot at the total 10-second deadline")
        finally:
            process.terminate()
            process.wait(timeout=5)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("executable")
    executable = parser.parse_args().executable
    run(executable)
    check_nonreading_peer(executable)
