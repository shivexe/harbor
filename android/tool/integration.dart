import 'dart:convert';
import 'dart:io';
import 'package:harbor/sync_client.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty || args.length > 2) {
    throw ArgumentError(
      'Provide an invitation file and optional --interactive',
    );
  }
  final invitation = await File(args.first).readAsString();
  final client = SyncClient();
  final pairing = await client.pair(
    invitation,
    (code, _) => stdout.writeln('Comparison: $code'),
  );
  stdout.writeln('Paired device ${pairing['deviceId']}');
  var snapshot = await client.sync(pairing, 0);
  final repeated = await client.sync(pairing, snapshot['revision']);
  if (snapshot['revision'] != repeated['revision'] ||
      repeated['requestId'] == snapshot['requestId']) {
    throw StateError('Fresh sync failed');
  }
  stdout.writeln(
    'Verified ${repeated['hosts'].length} hosts at revision ${repeated['revision']}.',
  );
  if (args.length == 2 && args[1] == '--interactive') {
    stdout.writeln('Ready for sync, expect-revoked or quit.');
    await for (final command
        in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
      if (command == 'quit') break;
      if (command == 'sync') {
        snapshot = await client.sync(pairing, snapshot['revision']);
        stdout.writeln(
          'Verified ${snapshot['hosts'].length} hosts at revision ${snapshot['revision']}.',
        );
      } else if (command == 'expect-revoked') {
        bool refused = false;
        try {
          await client.sync(pairing, snapshot['revision']);
        } on StateError catch (_) {
          refused = true;
        }
        if (!refused) throw StateError('Revoked device was accepted');
        stdout.writeln('Verified revoked device is refused.');
      }
    }
  }
}
