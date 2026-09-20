# Harbor architecture flow

Open [the complete dark-mode SVG](harbor-architecture.svg). Read downward, following the labeled arrows. Zoom in as needed; the drawing remains sharp.

The same flow is split into eight smaller SVGs:

1. [Who owns the data and where the apps run](01-ownership.svg)
2. [Save hosts, protect the vault and trust server keys](02-save-vault.svg)
3. [Pair a phone for the first time or switch desktops](03-pair.svg)
4. [Manual sync: every check before replacing data](04-sync.svg)
5. [Connect directly over SSH and end a session](05-ssh.svg)
6. [Android unlock, storage, locking, Unpair and Revoke](06-android-local.svg)
7. [Every key: who holds it and what it protects](07-key-map.svg)
8. [How to draw a system architecture from requirements](08-draw-architecture.svg)

These are standalone SVG files: no HTML, scripts, remote fonts or external images. [Source references and implementation limits](SOURCES.md) explain where the facts were checked. The diagrams describe app code at `7e43af9`, rather than promised future behavior.

To regenerate after editing the diagram source, run from the repository root:

```sh
python3 docs/architecture/generate.py
```
