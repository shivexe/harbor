import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:asn1lib/asn1lib.dart';
import 'package:cryptography/cryptography.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:pointycastle/export.dart';

class PrivateKeyException implements Exception {
  const PrivateKeyException(this.message);

  final String message;

  @override
  String toString() => message;
}

const _maxOpenSshBcryptRounds = 1024;
const _maxOpenSshBcryptSaltBytes = 64;

Future<List<SSHKeyPair>> loadPrivateKey(String pem, String passphrase) async {
  if (utf8.encode(pem).length > 256 * 1024) {
    throw const PrivateKeyException('Private key exceeds the 256 KiB limit.');
  }
  late final SSHPem decoded;
  try {
    decoded = SSHPem.decode(pem);
  } catch (_) {
    throw const PrivateKeyException('Private key is incomplete or malformed.');
  }
  final needsAdapter =
      decoded.type == 'ENCRYPTED PRIVATE KEY' ||
      decoded.type == 'PRIVATE KEY' ||
      (decoded.type == 'EC PRIVATE KEY' &&
          decoded.headers.containsKey('DEK-Info'));
  if (needsAdapter) {
    if (decoded.type != 'PRIVATE KEY' && passphrase.isEmpty) {
      throw const PrivateKeyException(
        'This private key requires a passphrase. Sync its passphrase and retry.',
      );
    }
    try {
      final clearPem = await Isolate.run(() => _adaptPem(pem, passphrase));
      return SSHKeyPair.fromPem(clearPem);
    } on PrivateKeyException {
      rethrow;
    } on UnsupportedError catch (error) {
      throw PrivateKeyException(error.message?.toString() ?? error.toString());
    } catch (_) {
      throw PrivateKeyException(
        decoded.type == 'PRIVATE KEY'
            ? 'Private key is incomplete or malformed.'
            : 'Private key could not be decrypted. Check its passphrase and sync again.',
      );
    }
  }
  try {
    final openSsh = decoded.type == 'OPENSSH PRIVATE KEY'
        ? OpenSSHKeyPairs.decode(decoded.content)
        : null;
    final encrypted = openSsh?.isEncrypted ?? SSHKeyPair.isEncryptedPem(pem);
    if (encrypted && passphrase.isEmpty) {
      throw const PrivateKeyException(
        'This private key requires a passphrase. Sync its passphrase and retry.',
      );
    }
    if (encrypted) {
      if (openSsh != null) {
        _validateOpenSshBcrypt(openSsh);
      }
      final clear = await Isolate.run(
        () => _decryptExistingPem(pem, passphrase),
      );
      return [for (final value in clear) ...SSHKeyPair.fromPem(value)];
    }
    return SSHKeyPair.fromPem(pem, passphrase.isEmpty ? null : passphrase);
  } on PrivateKeyException {
    rethrow;
  } on UnsupportedError catch (error) {
    throw PrivateKeyException(error.message?.toString() ?? error.toString());
  } catch (_) {
    throw PrivateKeyException(
      decoded.headers.containsKey('DEK-Info') ||
              decoded.type == 'OPENSSH PRIVATE KEY'
          ? 'Private key could not be decrypted. Check its passphrase and sync again.'
          : 'Private key is incomplete or malformed.',
    );
  }
}

void _validateOpenSshBcrypt(OpenSSHKeyPairs container) {
  final options = container.kdfOptions;
  if (options is! OpenSSHBcryptKdfOptions) {
    throw const PrivateKeyException(
      'Unsupported OpenSSH key derivation parameters.',
    );
  }
  if (options.rounds < 1 || options.rounds > _maxOpenSshBcryptRounds) {
    throw const PrivateKeyException(
      'OpenSSH bcrypt rounds are outside the supported limit of 1-1024.',
    );
  }
  if (options.salt.isEmpty ||
      options.salt.length > _maxOpenSshBcryptSaltBytes) {
    throw const PrivateKeyException(
      'OpenSSH bcrypt salt length is outside the supported limit of 1-64 bytes.',
    );
  }
}

List<String> _decryptExistingPem(String pem, String passphrase) =>
    SSHKeyPair.fromPem(
      pem,
      passphrase,
    ).map((key) => key.toPem()).toList(growable: false);

Future<String> _adaptPem(String pem, String passphrase) async {
  final decoded = SSHPem.decode(pem);
  if (decoded.type == 'EC PRIVATE KEY') {
    return _decryptLegacyEc(decoded, passphrase);
  }
  final der = decoded.type == 'ENCRYPTED PRIVATE KEY'
      ? _decryptPkcs8(decoded.content, passphrase)
      : decoded.content;
  return _unwrapPkcs8(der);
}

Uint8List _decryptPkcs8(Uint8List der, String passphrase) {
  final root = _sequence(der);
  if (root.elements.length != 2) {
    throw const FormatException('Invalid encrypted PKCS#8 structure');
  }
  final algorithm = _asSequence(root.elements[0]);
  _requireOid(algorithm.elements[0], '1.2.840.113549.1.5.13', 'PBES2');
  final pbes2 = _asSequence(algorithm.elements[1]);
  if (pbes2.elements.length != 2) {
    throw const FormatException('Invalid PBES2 parameters');
  }
  final kdf = _asSequence(pbes2.elements[0]);
  _requireOid(kdf.elements[0], '1.2.840.113549.1.5.12', 'PBKDF2');
  final params = _asSequence(kdf.elements[1]);
  if (params.elements.length < 2 || params.elements.length > 4) {
    throw const FormatException('Invalid PBKDF2 parameters');
  }
  final salt = _asOctets(params.elements[0]);
  if (salt.length < 8 || salt.length > 64) {
    throw const PrivateKeyException('Unsupported PBKDF2 salt length.');
  }
  final iterations = _asInteger(params.elements[1]);
  if (iterations < 1 || iterations > 2000000) {
    throw const PrivateKeyException(
      'PBKDF2 iteration count is outside the supported limit.',
    );
  }
  final encryption = _asSequence(pbes2.elements[1]);
  final cipherOid = _asOid(encryption.elements[0]);
  final keyLength = switch (cipherOid) {
    '2.16.840.1.101.3.4.1.2' => 16,
    '2.16.840.1.101.3.4.1.22' => 24,
    '2.16.840.1.101.3.4.1.42' => 32,
    _ => throw PrivateKeyException(
      'Unsupported PKCS#8 encryption algorithm: $cipherOid.',
    ),
  };
  var next = 2;
  if (params.elements.length > next && params.elements[next] is ASN1Integer) {
    if (_asInteger(params.elements[next]) != keyLength) {
      throw const PrivateKeyException('Unsupported PBKDF2 key length.');
    }
    next++;
  }
  var prfOid = '1.2.840.113549.2.7';
  if (params.elements.length > next) {
    final prf = _asSequence(params.elements[next]);
    prfOid = _asOid(prf.elements[0]);
    next++;
  }
  if (params.elements.length != next) {
    throw const FormatException('Invalid PBKDF2 parameters');
  }
  final digest = switch (prfOid) {
    '1.2.840.113549.2.7' => SHA1Digest(),
    '1.2.840.113549.2.9' => SHA256Digest(),
    '1.2.840.113549.2.10' => SHA384Digest(),
    '1.2.840.113549.2.11' => SHA512Digest(),
    _ => throw PrivateKeyException('Unsupported PBKDF2 PRF: $prfOid.'),
  };
  final iv = _asOctets(encryption.elements[1]);
  final encrypted = _asOctets(root.elements[1]);
  if (iv.length != 16 ||
      encrypted.isEmpty ||
      encrypted.length % 16 != 0 ||
      encrypted.length > 256 * 1024) {
    throw const FormatException('Invalid AES-CBC parameters');
  }
  final kdfEngine = PBKDF2KeyDerivator(HMac(digest, digest.byteLength))
    ..init(Pbkdf2Parameters(salt, iterations, keyLength));
  final key = kdfEngine.process(Uint8List.fromList(utf8.encode(passphrase)));
  return _aesCbcDecrypt(encrypted, key, iv);
}

String _decryptLegacyEc(SSHPem pem, String passphrase) {
  if (pem.headers['Proc-Type'] != '4,ENCRYPTED') {
    throw const FormatException('Invalid encrypted EC PEM headers');
  }
  final parts = pem.headers['DEK-Info']!.split(',');
  if (parts.length != 2) {
    throw const FormatException('Invalid EC PEM cipher header');
  }
  final keyLength = switch (parts[0].toUpperCase()) {
    'AES-128-CBC' => 16,
    'AES-192-CBC' => 24,
    'AES-256-CBC' => 32,
    _ => throw PrivateKeyException(
      'Unsupported encrypted EC PEM algorithm: ${parts[0]}.',
    ),
  };
  final iv = _hex(parts[1]);
  if (iv.length != 16 || pem.content.length % 16 != 0) {
    throw const FormatException('Invalid encrypted EC PEM parameters');
  }
  final password = Uint8List.fromList(utf8.encode(passphrase));
  final material = BytesBuilder();
  var previous = Uint8List(0);
  while (material.length < keyLength) {
    final digest = MD5Digest();
    digest.update(previous, 0, previous.length);
    digest.update(password, 0, password.length);
    digest.update(iv, 0, 8);
    previous = Uint8List(digest.digestSize);
    digest.doFinal(previous, 0);
    material.add(previous);
  }
  final key = Uint8List.sublistView(material.takeBytes(), 0, keyLength);
  final clear = _aesCbcDecrypt(pem.content, key, iv);
  return SSHPem('EC PRIVATE KEY', const {}, clear).encode(64);
}

Uint8List _aesCbcDecrypt(Uint8List encrypted, Uint8List key, Uint8List iv) {
  final cipher =
      PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()))..init(
        false,
        PaddedBlockCipherParameters(
          ParametersWithIV(KeyParameter(key), iv),
          null,
        ),
      );
  return cipher.process(encrypted);
}

Future<String> _unwrapPkcs8(Uint8List der) async {
  final root = _sequence(der);
  if (root.elements.length < 3) {
    throw const FormatException('Invalid PKCS#8 private key');
  }
  final version = _asInteger(root.elements[0]);
  if (version != 0 && version != 1) {
    throw const FormatException('Invalid PKCS#8 private key');
  }
  final algorithm = _asSequence(root.elements[1]);
  final oid = _asOid(algorithm.elements[0]);
  final key = _asOctets(root.elements[2]);
  if (oid == '1.2.840.113549.1.1.1') {
    _sequence(key);
    return SSHPem('RSA PRIVATE KEY', const {}, key).encode(64);
  }
  if (oid == '1.2.840.10045.2.1') {
    if (algorithm.elements.length != 2) {
      throw const FormatException('EC PKCS#8 key has no named curve');
    }
    final curveOid = _asOid(algorithm.elements[1]);
    final expectedLength = switch (curveOid) {
      '1.2.840.10045.3.1.7' => 32,
      '1.3.132.0.34' => 48,
      '1.3.132.0.35' => 66,
      _ => throw PrivateKeyException('Unsupported EC PKCS#8 curve: $curveOid.'),
    };
    final ec = _sequence(key);
    if (ec.elements.length < 2 ||
        _asOctets(ec.elements[1]).length != expectedLength) {
      throw const FormatException('EC key does not match its named curve');
    }
    final innerCurve = ec.elements.where((element) => element.tag == 0xa0);
    if (innerCurve.isEmpty) {
      ec.elements.insert(
        2,
        ASN1Object.preEncoded(
          0xa0,
          ASN1ObjectIdentifier.fromComponentString(curveOid).encodedBytes,
        ),
      );
    } else if (innerCurve.length != 1 ||
        _asOid(ASN1Parser(innerCurve.single.valueBytes()).nextObject()) !=
            curveOid) {
      throw const FormatException('EC key does not match its named curve');
    }
    return SSHPem('EC PRIVATE KEY', const {}, ec.encodedBytes).encode(64);
  }
  if (oid == '1.3.101.112') {
    if (algorithm.elements.length != 1) {
      throw const FormatException('Ed25519 PKCS#8 parameters must be absent');
    }
    final seedObject = ASN1Parser(key).nextObject();
    if (seedObject is! ASN1OctetString ||
        seedObject.totalEncodedByteLength != key.length ||
        seedObject.octets.length != 32) {
      throw const FormatException('Invalid Ed25519 PKCS#8 seed');
    }
    final derived = await Ed25519().newKeyPairFromSeed(seedObject.octets);
    final publicKey = await derived.extractPublicKey();
    derived.destroy();
    return OpenSSHEd25519KeyPair(
      Uint8List.fromList(publicKey.bytes),
      Uint8List.fromList([...seedObject.octets, ...publicKey.bytes]),
      '',
    ).toPem();
  }
  throw PrivateKeyException('Unsupported PKCS#8 key algorithm: $oid.');
}

ASN1Sequence _sequence(Uint8List bytes) {
  final parser = ASN1Parser(bytes);
  final object = parser.nextObject();
  if (object is! ASN1Sequence ||
      object.totalEncodedByteLength != bytes.length ||
      parser.hasNext()) {
    throw const FormatException('Invalid DER sequence');
  }
  return object;
}

ASN1Sequence _asSequence(ASN1Object object) {
  if (object is! ASN1Sequence) {
    throw const FormatException('Expected DER sequence');
  }
  return object;
}

Uint8List _asOctets(ASN1Object object) {
  if (object is! ASN1OctetString) {
    throw const FormatException('Expected DER octet string');
  }
  return object.octets;
}

int _asInteger(ASN1Object object) {
  if (object is! ASN1Integer || object.valueAsBigInteger.bitLength > 31) {
    throw const FormatException('Expected bounded DER integer');
  }
  return object.intValue;
}

String _asOid(ASN1Object object) {
  if (object is! ASN1ObjectIdentifier || object.identifier == null) {
    throw const FormatException('Expected object identifier');
  }
  return object.identifier!;
}

void _requireOid(ASN1Object object, String expected, String name) {
  final actual = _asOid(object);
  if (actual != expected) {
    throw PrivateKeyException('Unsupported $name algorithm: $actual.');
  }
}

Uint8List _hex(String value) {
  if (value.length.isOdd || !RegExp(r'^[0-9a-fA-F]+$').hasMatch(value)) {
    throw const FormatException('Invalid hexadecimal value');
  }
  return Uint8List.fromList([
    for (var i = 0; i < value.length; i += 2)
      int.parse(value.substring(i, i + 2), radix: 16),
  ]);
}
