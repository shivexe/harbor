import argparse
import asyncio
import codecs
import fcntl
import json
import os
import pathlib
import signal
import struct
import subprocess
import termios
import uuid
import asyncssh


class Server(asyncssh.SSHServer):
    def __init__(self, public_key):
        self.public_key = public_key

    def begin_auth(self, username):
        return username != "noauth"

    def password_auth_supported(self):
        return True

    def public_key_auth_supported(self):
        return True

    def validate_password(self, username, password):
        return username == "harbor" and password == "fixture-password"

    def validate_public_key(self, username, key):
        return username == "harbor" and key == self.public_key

    def session_requested(self):
        return Session()


class Session(asyncssh.SSHServerSession):
    def connection_made(self, channel):
        self.channel = channel
        self.master = None
        self.process = None
        self.size = (80, 24)
        self.command = None
        self.pty = False
        self.exec_process = None
        self.decoder = codecs.getincrementaldecoder("utf-8")("replace")

    def pty_requested(self, terminal_type, terminal_size, terminal_modes):
        self.pty = True
        self.size = terminal_size[:2]
        return True

    def terminal_size_changed(self, width, height, pixel_width, pixel_height):
        self.size = (width, height)
        if self.master is not None:
            fcntl.ioctl(self.master, termios.TIOCSWINSZ, struct.pack("HHHH", height, width, 0, 0))

    def shell_requested(self):
        return True

    def exec_requested(self, command):
        self.command = command
        return True

    async def execute(self):
        self.exec_process = await asyncio.create_subprocess_exec("/bin/bash", "--noprofile", "--norc", "-c", self.command, stdin=asyncio.subprocess.DEVNULL, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE, start_new_session=True)
        output, errors = await self.exec_process.communicate()
        if output:
            self.channel.write(output.decode("utf-8", "replace"))
        if errors:
            self.channel.write_stderr(errors.decode("utf-8", "replace"))
        self.channel.exit(self.exec_process.returncode)
        self.exec_process = None

    def session_started(self):
        if self.command is not None and not self.pty:
            asyncio.create_task(self.execute())
            return
        self.master, slave = os.openpty()
        width, height = self.size
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", height, width, 0, 0))
        environment = {"PATH": "/usr/bin:/bin", "TERM": "xterm-256color", "LANG": "C.UTF-8", "PS1": "harbor-fixture $ "}
        arguments = ["/bin/bash", "--noprofile", "--norc", "-i"] if self.command is None else ["/bin/bash", "--noprofile", "--norc", "-c", self.command]
        self.process = subprocess.Popen(arguments, stdin=slave, stdout=slave, stderr=slave, env=environment, start_new_session=True)
        os.close(slave)
        os.set_blocking(self.master, False)
        asyncio.get_running_loop().add_reader(self.master, self.read)

    def read(self):
        try:
            output = os.read(self.master, 65536)
            if output:
                self.channel.write(self.decoder.decode(output))
                return
        except BlockingIOError:
            return
        except OSError:
            pass
        status = self.process.poll() if self.process else 0
        self.cleanup()
        self.channel.exit(status or 0)

    def data_received(self, data, datatype):
        if self.master is not None:
            try:
                os.write(self.master, data.encode())
            except OSError:
                self.cleanup()

    def connection_lost(self, exception):
        self.cleanup()

    def cleanup(self):
        if self.exec_process is not None:
            try:
                os.killpg(self.exec_process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            self.exec_process = None
        if self.master is not None:
            asyncio.get_running_loop().remove_reader(self.master)
            os.close(self.master)
            self.master = None
        if self.process is not None:
            try:
                os.killpg(self.process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            self.process = None


async def run(args):
    directory = pathlib.Path(args.directory)
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(directory, 0o700)
    def fixture_key(filename, algorithm="ssh-ed25519"):
        path = directory / filename
        if path.exists():
            return asyncssh.read_private_key(str(path))
        key = asyncssh.generate_private_key(algorithm)
        path.write_bytes(key.export_private_key("openssh"))
        os.chmod(path, 0o600)
        return key
    host_key = fixture_key("server.key", "ssh-rsa" if args.host_key_type == "rsa" else "ssh-ed25519")
    client_key = fixture_key("client.key")
    previous = directory / "hosts.json"
    old_ids = {host["name"]: host["id"] for host in json.loads(previous.read_text())} if previous.exists() else {}
    plain_key = client_key.export_private_key("openssh").decode()
    encrypted_key = client_key.export_private_key("openssh", passphrase="fixture-key-passphrase").decode()
    server = await asyncssh.create_server(lambda: Server(client_key.convert_to_public()), "127.0.0.1", args.port, server_host_keys=[host_key], line_editor=False)
    port = server.get_port()
    public_key = host_key.export_public_key("openssh").decode().strip().split(" ")[:2]
    pinned = " ".join(public_key)
    hosts = []
    for name, auth, key, passphrase in (("Password fixture", "password", "", ""), ("Private-key fixture", "key", plain_key, ""), ("Encrypted-key fixture", "key", encrypted_key, "fixture-key-passphrase"), ("No-auth fixture", "none", "", "")):
        hosts.append({"id": old_ids.get(name, str(uuid.uuid4())), "name": name, "hostname": "127.0.0.1", "port": port, "username": "noauth" if auth == "none" else "harbor", "group": "Integration lab", "authType": auth, "password": "fixture-password" if auth == "password" else "", "privateKey": key, "passphrase": passphrase, "hostKey": pinned, "notes": "Disposable local SSH test server; credentials have no external access."})
    for filename, host in zip(("password.json", "key.json", "encrypted-key.json", "none.json"), hosts):
        single = directory / filename
        single.write_text(json.dumps(host, indent=2) + "\n")
        os.chmod(single, 0o600)
    fixture = directory / "hosts.json"
    fixture.write_text(json.dumps(hosts, indent=2) + "\n")
    os.chmod(fixture, 0o600)
    print(json.dumps({"port": port, "hostsFile": str(fixture)}), flush=True)
    try:
        await asyncio.Future()
    finally:
        server.close()
        await server.wait_closed()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--directory", required=True)
    parser.add_argument("--host-key-type", choices=("ed25519", "rsa"), default="ed25519")
    parser.add_argument("--port", type=int, default=0)
    asyncio.run(run(parser.parse_args()))
