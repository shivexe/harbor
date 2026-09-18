# Third-party software

Harbor for Linux links against the following system libraries; the Debian package declares dependencies instead of bundling them.

- Qt 6: The Qt Company and contributors. LGPL-3.0/GPL-3.0 or commercial licenses. https://www.qt.io/licensing/
- QTermWidget 6: LXQt team and contributors, derived from Konsole. The overall source contains GPL-2.0-or-later components and LGPL-2.1-or-later components. https://github.com/lxqt/qtermwidget
- OpenSSL 3: OpenSSL Project and contributors. Apache-2.0. https://www.openssl.org/source/license.html
- libqrencode: Kentaro Fukuchi and contributors. LGPL-2.1-or-later. https://fukuchi.org/works/qrencode/
- utf8proc: Julia contributors and the utf8proc contributors. MIT/Unicode license. https://github.com/JuliaStrings/utf8proc
- OpenSSH: OpenBSD and OpenSSH contributors. BSD and other permissive licenses. https://www.openssh.com/

Use the installed distribution copyright notices for the exact dependency versions and full copyright attribution, normally `/usr/share/doc/libqtermwidget6-2/copyright` and the respective library documentation directories. QTermWidget redistribution has GPL obligations; do not treat the linked Linux desktop as a permissively licensed standalone binary without resolving those obligations. Harbor source is supplied beside the local build artifact. No dependency license is changed by this project.
