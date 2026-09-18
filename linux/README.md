# Harbor for Linux

Qt 6 desktop app with QTermWidget terminals and system OpenSSH.

## Build and run

On Ubuntu 26.04, run from this directory:

```sh
sudo apt install build-essential cmake qt6-base-dev libqtermwidget6-2-dev libutf8proc-dev libssl-dev libqrencode-dev openssh-client fontconfig fonts-dejavu-core
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
./build/harbor
```

Other distributions need Qt 6.4 or later, QTermWidget 6, OpenSSL, libqrencode, and OpenSSH.

## Install and test

```sh
cmake --install build --prefix "$HOME/.local"
ctest --test-dir build --output-on-failure
```

Keep `harbor` and `harbor-askpass` together; both are installed by CMake.

## Use

Create a vault with a master passphrase of at least 12 characters. Add a host, verify its server fingerprint, and connect. Use **Devices → Pair Android** to pair your phone over a local network or private VPN.

Locking the vault closes SSH sessions and stops sharing. The master passphrase is required to recover an encrypted vault backup.

See [third-party notices](THIRD_PARTY_NOTICES.md) for Linux dependencies.
