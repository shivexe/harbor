import 'dart:convert';
import 'dart:io';
import 'package:harbor/models.dart';
import 'package:harbor/ssh_client.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    throw ArgumentError('Provide a protected fixture host file');
  }
  final record = Map<String, dynamic>.from(
    jsonDecode(await File(args.single).readAsString()),
  );
  bool absent = false;
  try {
    await connectSSH(Host.fromJson({...record, 'hostKey': ''}));
  } on StateError catch (_) {
    absent = true;
  }
  if (!absent) throw StateError('Unverified server accepted');
  final parts = (record['hostKey'] as String).split(' ');
  final blob = base64Decode(parts[1]);
  blob[blob.length - 1] ^= 1;
  bool changed = false;
  try {
    final client = await connectSSH(
      Host.fromJson({
        ...record,
        'hostKey': '${parts[0]} ${base64Encode(blob)}',
      }),
    );
    client.close();
  } on StateError catch (error) {
    changed = error.message.toString().contains('Host key changed');
  }
  if (!changed) throw StateError('Changed server key accepted');
  stdout.writeln(
    'Verified absent and changed server keys are refused before authentication.',
  );
}
