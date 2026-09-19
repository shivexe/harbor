import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harbor/sync_client.dart';

void main() {
  test('shared vectors match desktop encryption and signatures', () async {
    final vector = Map<String, dynamic>.from(
      jsonDecode(await File('../shared/protocol-vectors.json').readAsString()),
    );
    for (final message in vector['messages']) {
      expect(
        await decrypt(
          Map<String, dynamic>.from(message['envelope']),
          base64Decode(message['key']),
          message['aad'],
        ),
        jsonDecode(message['plaintext']),
      );
    }
    final digest = (await Sha256().hash([
      ...base64Decode(vector['secret']),
      ...base64Decode(vector['clientNonce']),
    ])).bytes;
    final code =
        (((digest[0] << 24) |
                    (digest[1] << 16) |
                    (digest[2] << 8) |
                    digest[3]) %
                1000000)
            .toString()
            .padLeft(6, '0');
    expect(code, vector['comparisonCode']);
    final snapshot = await SyncClient().verifySnapshot(
      {'payload': vector['payload'], 'signature': vector['signature']},
      {
        'publicKey': vector['publicKey'],
        'vaultId': vector['snapshot']['vaultId'],
      },
      vector['snapshot']['requestId'],
      7,
    );
    expect(snapshot['hosts'], vector['snapshot']['hosts']);
  });
  test('envelopes authenticate AAD and reject tampering', () async {
    final key = List.generate(32, (i) => i);
    final encrypted = await encrypt({'hello': 'harbor'}, key, 'test');
    expect(await decrypt(encrypted, key, 'test'), {'hello': 'harbor'});
    await expectLater(
      decrypt(encrypted, key, 'other'),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
    final tag = base64Decode(encrypted['tag']);
    tag[0] ^= 1;
    await expectLater(
      decrypt({...encrypted, 'tag': base64Encode(tag)}, key, 'test'),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });
  test('pairing only accepts private literal origins', () {
    for (final url in [
      'http://127.0.0.1:45873',
      'http://192.168.1.3',
      'http://100.64.0.0',
      'http://100.127.255.255',
      'http://[fd00::1]:45873',
      'http://[::1]',
    ]) {
      expect(localOrigin(url), isNotNull);
    }
    for (final url in [
      'http://8.8.8.8',
      'http://100.63.255.255',
      'http://100.128.0.0',
      'http://localhost',
      'https://192.168.1.2',
      'http://user@192.168.1.2',
      'http://192.168.1.2/a',
      'http://192.168.1.2?x=y',
      'http://192.168.1.2#x',
    ]) {
      expect(() => localOrigin(url), throwsFormatException);
    }
  });
  test(
    'signed snapshots bind request and preserve revision monotonicity',
    () async {
      final ed = Ed25519();
      final key = await ed.newKeyPair();
      final public = await key.extractPublicKey();
      final pairing = {
        'vaultId': 'vault',
        'publicKey': base64Encode(public.bytes),
      };
      final snapshot = {
        'version': 1,
        'vaultId': 'vault',
        'requestId': 'fresh',
        'revision': 2,
        'generatedAt': 1,
        'hosts': <dynamic>[],
      };
      Future<Map<String, dynamic>> sign(Map<String, dynamic> value) async {
        final payload = base64Encode(utf8.encode(jsonEncode(value)));
        final signature = await ed.sign(
          utf8.encode('harbor.snapshot.v1\n$payload'),
          keyPair: key,
        );
        return {'payload': payload, 'signature': base64Encode(signature.bytes)};
      }

      final client = SyncClient();
      final signed = await sign(snapshot);
      expect(
        (await client.verifySnapshot(signed, pairing, 'fresh', 2))['hosts'],
        isEmpty,
      );
      await expectLater(
        client.verifySnapshot(signed, pairing, 'stale', 2),
        throwsFormatException,
      );
      await expectLater(
        client.verifySnapshot(signed, pairing, 'fresh', 3),
        throwsFormatException,
      );
      final host = {
        'id': '11111111-1111-4111-8111-111111111111',
        'name': 'Server',
        'hostname': '127.0.0.1',
        'port': 22,
        'username': 'root',
        'group': '',
        'authType': 'password',
        'password': 'x',
        'privateKey': '',
        'passphrase': '',
        'hostKey': '',
        'notes': '',
      };
      await expectLater(
        client.verifySnapshot(
          await sign({
            ...snapshot,
            'hosts': [host, host],
          }),
          pairing,
          'fresh',
          1,
        ),
        throwsFormatException,
      );
      await expectLater(
        client.verifySnapshot(
          await sign({
            ...snapshot,
            'hosts': [
              {...host, 'port': 0},
            ],
          }),
          pairing,
          'fresh',
          1,
        ),
        throwsFormatException,
      );
      final tampered = {
        ...signed,
        'payload': base64Encode(
          utf8.encode(jsonEncode({...snapshot, 'revision': 3})),
        ),
      };
      await expectLater(
        client.verifySnapshot(tampered, pairing, 'fresh', 1),
        throwsFormatException,
      );
    },
  );
}
