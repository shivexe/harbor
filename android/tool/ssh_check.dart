import 'dart:convert';
import 'dart:io';

import 'package:harbor/models.dart';
import 'package:harbor/ssh_client.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    throw ArgumentError('Provide a protected host record file');
  }
  final host = Host.fromJson(
    Map<String, dynamic>.from(
      jsonDecode(await File(args.single).readAsString()),
    ),
  );
  final client = await connectSSH(host);
  try {
    final session = await client.execute("printf 'harbor-ssh-ok\\n'");
    final output = await utf8.decoder.bind(session.stdout).join();
    await session.done;
    if (output != 'harbor-ssh-ok\n' || session.exitCode != 0) {
      throw StateError('SSH command failed');
    }
    final shell = await client.shell();
    shell.resizeTerminal(100, 40);
    shell.write(utf8.encode("stty size; printf 'harbor-pty-ok\\n'; exit\n"));
    final shellOutput = await utf8.decoder.bind(shell.stdout).join();
    await shell.done;
    if (!shellOutput.contains('harbor-pty-ok') ||
        !shellOutput.contains('40 100')) {
      throw StateError('SSH PTY failed');
    }
    stdout.writeln(
      'Verified direct SSH authentication, command, interactive PTY and resize.',
    );
  } finally {
    client.close();
  }
}
