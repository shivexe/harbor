import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:dartssh2/dartssh2.dart';

import 'models.dart';

enum ConnectionStage {
  openingSocket,
  verifyingHost,
  authenticating,
  openingShell,
  connected,
  failed,
  disconnected,
}

class HostKeyException extends StateError {
  HostKeyException(super.message);
}

Future<SSHClient> connectSSH(
  Host host, {
  void Function(SSHClient)? onClient,
  void Function(ConnectionStage)? onStage,
  void Function(String)? onServerMessage,
}) async {
  if (host.hostKey.isEmpty) {
    throw HostKeyException(
      'Verify this server key on your desktop, then sync before connecting.',
    );
  }
  final parts = host.hostKey.split(' ');
  final digest = await Sha256().hash(base64Decode(parts[1]));
  final expected = 'SHA256:${base64Encode(digest.bytes).replaceAll('=', '')}';
  final identities = host.auth == 'key'
      ? SSHKeyPair.fromPem(
          host.privateKey,
          host.passphrase.isEmpty ? null : host.passphrase,
        )
      : null;
  onStage?.call(ConnectionStage.openingSocket);
  final socket = await SSHSocket.connect(
    host.address,
    host.port,
    timeout: const Duration(seconds: 15),
  );
  onStage?.call(ConnectionStage.verifyingHost);
  bool rejected = false;
  final client = SSHClient(
    socket,
    username: host.username,
    identities: identities,
    handshakeTimeout: const Duration(seconds: 15),
    authTimeout: const Duration(seconds: 30),
    onPasswordRequest: host.auth == 'password' ? () => host.password : null,
    onUserauthBanner: onServerMessage,
    onVerifyHostKey: (type, bytes) {
      if (utf8.decode(bytes) != expected) {
        rejected = true;
        return false;
      }
      onStage?.call(ConnectionStage.authenticating);
      return true;
    },
  );
  onClient?.call(client);
  try {
    await client.authenticated;
    return client;
  } catch (_) {
    client.close();
    if (rejected) {
      throw HostKeyException(
        'Host key changed. Verify this server on your desktop.',
      );
    }
    rethrow;
  }
}
