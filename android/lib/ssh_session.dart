import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';

import 'models.dart';
import 'ssh_client.dart';
import 'security_gate.dart';
import 'interactive_terminal.dart';

class Connection extends ChangeNotifier {
  Connection(this.host) {
    terminal.onControlChanged = changed;
  }
  final Host host;
  final InteractiveTerminal terminal = InteractiveTerminal(
    onActivity: noteInteraction,
  );
  SSHClient? client;
  SSHSession? shell;
  ConnectionStage stage = ConnectionStage.openingSocket;
  ConnectionStage? failedAt;
  String? problem;
  String serverMessage = '';
  bool started = false;
  bool closed = false;
  bool disposed = false;
  final subscriptions = <StreamSubscription<dynamic>>[];

  String get status => switch (stage) {
    ConnectionStage.openingSocket => 'Reaching server',
    ConnectionStage.verifyingHost => 'Verifying host key',
    ConnectionStage.authenticating => 'Authenticating',
    ConnectionStage.openingShell => 'Opening shell',
    ConnectionStage.connected => 'Connected',
    ConnectionStage.failed => problem ?? 'Connection failed',
    ConnectionStage.disconnected => 'Session ended',
  };
  bool get controlNext => terminal.controlNext;
  set controlNext(bool value) => terminal.controlNext = value;

  void changed() {
    if (!disposed) notifyListeners();
  }

  void advance(ConnectionStage next) {
    if (closed || next.index < stage.index) return;
    stage = next;
    changed();
  }

  void receiveServerMessage(String message) {
    if (closed) return;
    final plain = message.replaceAll(
      RegExp(r'\x1b(?:\[[0-?]*[ -/]*[@-~]|\][^\x07\x1b]*(?:\x07|\x1b\\)|.)'),
      '',
    );
    final clean = String.fromCharCodes(
      plain.runes.where(
        (rune) =>
            rune == 10 ||
            (rune >= 32 &&
                rune != 127 &&
                (rune < 0x80 || rune > 0x9f) &&
                (rune < 0x202a || rune > 0x202e) &&
                (rune < 0x2066 || rune > 0x2069)),
      ),
    ).trim();
    if (clean.isEmpty || serverMessage.length >= 2048) return;
    serverMessage = '$serverMessage${serverMessage.isEmpty ? '' : '\n'}$clean';
    if (serverMessage.length > 2048) {
      serverMessage = serverMessage.substring(0, 2048);
    }
    changed();
  }

  void endSession() {
    if (closed) return;
    stage = ConnectionStage.disconnected;
    close();
    changed();
  }

  Future<void> connect() async {
    if (started || closed) return;
    started = true;
    advance(ConnectionStage.openingSocket);
    var socketStarted = false;
    try {
      client = await connectSSH(
        host,
        onStage: (next) {
          if (next == ConnectionStage.openingSocket) socketStarted = true;
          advance(next);
        },
        onServerMessage: receiveServerMessage,
        onClient: (value) {
          client = value;
          if (closed) value.close();
        },
      );
      if (closed) {
        client!.close();
        return;
      }
      advance(ConnectionStage.openingShell);
      shell = await client!
          .shell(
            pty: SSHPtyConfig(
              type: 'xterm-256color',
              width: terminal.viewWidth,
              height: terminal.viewHeight,
            ),
          )
          .timeout(const Duration(seconds: 15));
      if (closed) {
        client!.close();
        return;
      }
      terminal.onOutput = send;
      terminal.onResize = (width, height, pixelWidth, pixelHeight) =>
          shell?.resizeTerminal(width, height, pixelWidth, pixelHeight);
      shell!.resizeTerminal(terminal.viewWidth, terminal.viewHeight);
      subscriptions.add(
        shell!.stdout
            .cast<List<int>>()
            .transform(const Utf8Decoder(allowMalformed: true))
            .listen(terminal.write, onError: (Object _) => endSession()),
      );
      subscriptions.add(
        shell!.stderr
            .cast<List<int>>()
            .transform(const Utf8Decoder(allowMalformed: true))
            .listen(terminal.write, onError: (Object _) => endSession()),
      );
      advance(ConnectionStage.connected);
      await shell!.done;
      endSession();
    } catch (error) {
      client?.close();
      if (closed) return;
      failedAt = error is HostKeyException
          ? socketStarted
                ? ConnectionStage.verifyingHost
                : null
          : stage;
      problem = error is HostKeyException
          ? error.message.toString()
          : switch (failedAt) {
              ConnectionStage.openingSocket =>
                error is SocketException || error is TimeoutException
                    ? 'Server unreachable. Check your network or private VPN.'
                    : 'Could not start SSH. Review this host on your desktop, then sync.',
              ConnectionStage.verifyingHost =>
                'Could not verify this server key. Check it on your desktop, then sync.',
              ConnectionStage.authenticating =>
                host.auth == 'none'
                    ? 'Server rejected password-free access. Check your Tailscale SSH policy and username on your desktop.'
                    : 'Authentication failed. Review the username and credentials on your desktop, then sync.',
              ConnectionStage.openingShell =>
                'The server did not open a shell. Check this account on your desktop.',
              _ =>
                'Connection failed. Review this host on your desktop, then sync.',
            };
      advance(ConnectionStage.failed);
    }
  }

  void send(String input) =>
      shell?.write(Uint8List.fromList(utf8.encode(input)));

  void close() {
    closed = true;
    for (final subscription in subscriptions) {
      unawaited(subscription.cancel());
    }
    subscriptions.clear();
    shell?.close();
    client?.close();
  }

  @override
  void dispose() {
    if (disposed) return;
    disposed = true;
    close();
    super.dispose();
  }
}
