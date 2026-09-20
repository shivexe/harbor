import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import 'models.dart';

final _random = Random.secure();
List<int> randomBytes(int count) =>
    List.generate(count, (_) => _random.nextInt(256));
String uuid() {
  final b = randomBytes(16);
  b[6] = (b[6] & 15) | 64;
  b[8] = (b[8] & 63) | 128;
  final hex = b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

List<int> binary(dynamic value, int? length) {
  if (value is! String) throw const FormatException('Invalid binary field');
  final bytes = base64Decode(value);
  if (base64Encode(bytes) != value) {
    throw const FormatException('Noncanonical binary encoding');
  }
  if (length != null && bytes.length != length) {
    throw const FormatException('Invalid binary length');
  }
  return bytes;
}

Future<Map<String, dynamic>> encrypt(
  Map<String, dynamic> plaintext,
  List<int> key,
  String aad,
) async {
  final box = await AesGcm.with256bits().encrypt(
    utf8.encode(jsonEncode(plaintext)),
    secretKey: SecretKey(key),
    nonce: randomBytes(12),
    aad: utf8.encode(aad),
  );
  return {
    'nonce': base64Encode(box.nonce),
    'ciphertext': base64Encode(box.cipherText),
    'tag': base64Encode(box.mac.bytes),
  };
}

Future<Map<String, dynamic>> decrypt(
  Map<String, dynamic> envelope,
  List<int> key,
  String aad,
) async {
  final ciphertext = binary(envelope['ciphertext'], null);
  if (ciphertext.length > 12582912) {
    throw const FormatException('Payload too large');
  }
  final bytes = await AesGcm.with256bits().decrypt(
    SecretBox(
      ciphertext,
      nonce: binary(envelope['nonce'], 12),
      mac: Mac(binary(envelope['tag'], 16)),
    ),
    secretKey: SecretKey(key),
    aad: utf8.encode(aad),
  );
  return Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes)));
}

bool privateAddress(InternetAddress address) {
  final b = address.rawAddress;
  if (address.type == InternetAddressType.IPv4) {
    return b[0] == 10 ||
        b[0] == 127 ||
        (b[0] == 100 && b[1] >= 64 && b[1] <= 127) ||
        (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
        (b[0] == 192 && b[1] == 168) ||
        (b[0] == 169 && b[1] == 254);
  }
  return address.isLoopback ||
      (b[0] & 0xfe) == 0xfc ||
      (b[0] == 0xfe && (b[1] & 0xc0) == 0x80);
}

Uri localOrigin(String value) {
  final uri = Uri.parse(value);
  final address = InternetAddress.tryParse(uri.host);
  if (uri.scheme != 'http' ||
      address == null ||
      !privateAddress(address) ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      !(uri.path.isEmpty || uri.path == '/') ||
      uri.port < 1 ||
      uri.port > 65535) {
    throw const FormatException('Pairing requires a local IP address');
  }
  return uri.replace(path: '');
}

class SyncClient {
  Future<Map<String, dynamic>> pair(
    String code,
    void Function(String, String) onComparison, {
    bool Function()? cancelled,
  }) async {
    if (code.length > 16384) {
      throw const FormatException('Pairing code too large');
    }
    final invitation = Map<String, dynamic>.from(jsonDecode(code));
    if (invitation['version'] != 1 ||
        invitation['expiresAt'] is! int ||
        invitation['expiresAt'] <=
            DateTime.now().millisecondsSinceEpoch ~/ 1000 ||
        invitation['expiresAt'] >
            DateTime.now().millisecondsSinceEpoch ~/ 1000 + 330 ||
        invitation['desktopName'] is! String ||
        (invitation['desktopName'] as String).length > 80) {
      throw const FormatException('Expired invitation');
    }
    final origin = localOrigin(invitation['url']);
    final secret = binary(invitation['secret'], 32);
    binary(invitation['publicKey'], 32);
    final pairId = invitation['pairId'] as String;
    final vaultId = invitation['vaultId'] as String;
    if (!_validId(pairId) || !_validId(vaultId)) {
      throw const FormatException('Invalid invitation identity');
    }
    final deviceId = uuid();
    final clientNonce = randomBytes(32);
    final digest = (await Sha256().hash([...secret, ...clientNonce])).bytes;
    final comparison =
        (((digest[0] << 24) |
                    (digest[1] << 16) |
                    (digest[2] << 8) |
                    digest[3]) %
                1000000)
            .toString()
            .padLeft(6, '0');
    onComparison(comparison, invitation['desktopName'] as String);
    final request = await encrypt(
      {
        'deviceId': deviceId,
        'deviceName': 'Harbor Android',
        'clientNonce': base64Encode(clientNonce),
      },
      secret,
      'harbor/pair-request/v1/$pairId',
    );
    while (DateTime.now().millisecondsSinceEpoch ~/ 1000 <
        invitation['expiresAt']) {
      if (cancelled?.call() == true) throw StateError('Pairing cancelled');
      (int, Map<String, dynamic>) response;
      try {
        response = await post(origin.resolve('/v1/pair/$pairId'), request);
      } on SocketException {
        await Future<void>.delayed(const Duration(seconds: 2));
        continue;
      } on TimeoutException {
        await Future<void>.delayed(const Duration(seconds: 2));
        continue;
      } on HttpException {
        await Future<void>.delayed(const Duration(seconds: 2));
        continue;
      }
      if (cancelled?.call() == true) throw StateError('Pairing cancelled');
      if (response.$1 == 200) {
        final approved = await decrypt(
          response.$2,
          secret,
          'harbor/pair-response/v1/$pairId',
        );
        if (approved['version'] != 1 ||
            approved['deviceId'] != deviceId ||
            approved['vaultId'] != vaultId ||
            approved['desktopName'] is! String ||
            (approved['desktopName'] as String).length > 80) {
          throw const FormatException('Invalid pairing response');
        }
        binary(approved['syncKey'], 32);
        return {
          ...approved,
          'url': origin.toString(),
          'publicKey': invitation['publicKey'],
        };
      }
      if (response.$1 != 202 || response.$2['status'] != 'pending') {
        throw StateError('Pairing denied or expired');
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    throw StateError('Pairing expired');
  }

  Future<Map<String, dynamic>> sync(
    Map<String, dynamic> pairing,
    int revision,
  ) async {
    final origin = localOrigin(pairing['url']);
    final deviceId = pairing['deviceId'] as String;
    final requestId = base64Encode(randomBytes(32));
    final key = binary(pairing['syncKey'], 32);
    final request = await encrypt(
      {'version': 1, 'vaultId': pairing['vaultId'], 'requestId': requestId},
      key,
      'harbor/sync-request/v1/$deviceId',
    );
    final response = await post(origin.resolve('/v1/sync'), {
      ...request,
      'deviceId': deviceId,
    });
    if (response.$1 == 403) throw StateError('Device revoked on desktop');
    if (response.$1 != 200) throw StateError('Desktop unavailable');
    final signed = await decrypt(
      response.$2,
      key,
      'harbor/sync-response/v1/$deviceId',
    );
    return verifySnapshot(signed, pairing, requestId, revision);
  }

  Future<Map<String, dynamic>> verifySnapshot(
    Map<String, dynamic> signed,
    Map<String, dynamic> pairing,
    String requestId,
    int revision,
  ) async {
    final payload = signed['payload'] as String;
    final bytes = binary(payload, null);
    if (bytes.length > 8388608) {
      throw const FormatException('Snapshot too large');
    }
    final valid = await Ed25519().verify(
      utf8.encode('harbor.snapshot.v1\n$payload'),
      signature: Signature(
        binary(signed['signature'], 64),
        publicKey: SimplePublicKey(
          binary(pairing['publicKey'], 32),
          type: KeyPairType.ed25519,
        ),
      ),
    );
    if (!valid) throw const FormatException('Invalid desktop signature');
    final snapshot = Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes)));
    if (snapshot['version'] != 1 ||
        snapshot['vaultId'] != pairing['vaultId'] ||
        snapshot['requestId'] != requestId ||
        snapshot['revision'] is! int ||
        snapshot['revision'] < revision ||
        snapshot['revision'] < 1 ||
        snapshot['revision'] > 9007199254740991 ||
        snapshot['generatedAt'] is! int ||
        snapshot['generatedAt'] < 0 ||
        snapshot['generatedAt'] > 9007199254740991) {
      throw const FormatException('Invalid or stale snapshot');
    }
    final hosts = snapshot['hosts'];
    if (hosts is! List || hosts.length > 10000) {
      throw const FormatException('Invalid host collection');
    }
    final ids = <String>{};
    for (final record in hosts) {
      final host = Host.fromJson(Map<String, dynamic>.from(record));
      if (!_validId(host.id) || !ids.add(host.id)) {
        throw const FormatException('Invalid or duplicate host ID');
      }
    }
    return {...snapshot, 'syncedAt': DateTime.now().toUtc().toIso8601String()};
  }

  Future<(int, Map<String, dynamic>)> post(
    Uri uri,
    Map<String, dynamic> body,
  ) async {
    final http = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await http
          .postUrl(uri)
          .timeout(const Duration(seconds: 10));
      request.followRedirects = false;
      final bytes = utf8.encode(jsonEncode(body));
      request.headers.contentType = ContentType.json;
      request.contentLength = bytes.length;
      request.persistentConnection = false;
      request.add(bytes);
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      if (response.contentLength > 16777216) {
        throw const FormatException('Response too large');
      }
      final data = await response
          .fold<List<int>>(<int>[], (data, chunk) {
            if (data.length + chunk.length > 16777216) {
              throw const FormatException('Response too large');
            }
            data.addAll(chunk);
            return data;
          })
          .timeout(const Duration(seconds: 10));
      return (
        response.statusCode,
        Map<String, dynamic>.from(jsonDecode(utf8.decode(data))),
      );
    } finally {
      http.close(force: true);
    }
  }
}

bool _validId(String value) => RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
).hasMatch(value);
