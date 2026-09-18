import 'dart:async';
import 'dart:convert';

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
  String status = 'Connecting';
  bool started = false;
  bool closed = false;
  bool get controlNext => terminal.controlNext;
  set controlNext(bool value) => terminal.controlNext = value;
  bool disposed = false;
  final subscriptions = <StreamSubscription<dynamic>>[];
  void changed() {
    if (!disposed) notifyListeners();
  }

  Future<void> connect() async {
    if (started || closed) return;
    started = true;
    try {
      client = await connectSSH(
        host,
        onClient: (value) {
          client = value;
          if (closed) value.close();
        },
      );
      if (closed) {
        client!.close();
        return;
      }
      shell = await client!.shell(
        pty: SSHPtyConfig(
          type: 'xterm-256color',
          width: terminal.viewWidth,
          height: terminal.viewHeight,
        ),
      );
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
            .listen(
              terminal.write,
              onError: (Object _) {
                status = 'Disconnected';
                close();
                changed();
              },
            ),
      );
      subscriptions.add(
        shell!.stderr
            .cast<List<int>>()
            .transform(const Utf8Decoder(allowMalformed: true))
            .listen(
              terminal.write,
              onError: (Object _) {
                status = 'Disconnected';
                close();
                changed();
              },
            ),
      );
      status = 'Connected';
      changed();
      await shell!.done;
      status = 'Disconnected';
      client?.close();
      changed();
    } catch (error) {
      client?.close();
      status = error is StateError
          ? error.message.toString()
          : 'Connection failed. Check the network and desktop credentials.';
      changed();
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
