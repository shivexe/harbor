import 'dart:io';

import 'package:asn1lib/asn1lib.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harbor/private_key_loader.dart';

String fixture(String name) =>
    File('test/fixtures/encrypted_keys/$name').readAsStringSync();

Matcher privateKeyError(String text) => isA<PrivateKeyException>().having(
  (error) => error.message,
  'message',
  contains(text),
);

String ed25519WithNullParameters() {
  final pem = SSHPem.decode(fixture('ed25519-clear.pem'));
  final original = ASN1Parser(pem.content).nextObject() as ASN1Sequence;
  final algorithm = ASN1Sequence()
    ..add(ASN1ObjectIdentifier.fromComponentString('1.3.101.112'))
    ..add(ASN1Null());
  final modified = ASN1Sequence()
    ..add(original.elements[0])
    ..add(algorithm)
    ..add(original.elements[2]);
  return SSHPem('PRIVATE KEY', const {}, modified.encodedBytes).encode(64);
}

String openSshWithRounds(int rounds) {
  final pem = SSHPem.decode(fixture('openssh-ed25519'));
  final container = OpenSSHKeyPairs.decode(pem.content);
  final options = container.kdfOptions as OpenSSHBcryptKdfOptions;
  return OpenSSHKeyPairs(
    cipherName: container.cipherName,
    kdfName: container.kdfName,
    kdfOptions: OpenSSHBcryptKdfOptions(options.salt, rounds),
    publicKeys: container.publicKeys,
    privateKeyBlob: container.privateKeyBlob,
  ).toPem();
}

void main() {
  late String passphrase;

  setUpAll(() {
    passphrase = fixture('passphrase').trim();
  });

  test('decrypts PBES2 RSA, EC, and Ed25519 PKCS8 keys', () async {
    final clearRsa = await loadPrivateKey(fixture('rsa-clear.pem'), '');
    final clearEc = await loadPrivateKey(fixture('ec-clear.pem'), '');
    for (final name in [
      'rsa-pkcs8.pem',
      'rsa-pkcs8-sha1.pem',
      'ec-pkcs8.pem',
    ]) {
      final encrypted = await loadPrivateKey(fixture(name), passphrase);
      final expected = name.startsWith('rsa') ? clearRsa : clearEc;
      expect(
        encrypted.single.toPublicKey().encode(),
        expected.single.toPublicKey().encode(),
      );
    }
    final ed25519 = await loadPrivateKey(
      fixture('ed25519-pkcs8.pem'),
      passphrase,
    );
    expect(ed25519.single.name, 'ssh-ed25519');
  });

  test('decrypts legacy encrypted EC and RSA keys', () async {
    final clearRsa = await loadPrivateKey(fixture('rsa-clear.pem'), '');
    final clearEc = await loadPrivateKey(fixture('ec-clear.pem'), '');
    final rsa = await loadPrivateKey(fixture('rsa-legacy.pem'), passphrase);
    final ec = await loadPrivateKey(fixture('ec-legacy.pem'), passphrase);
    expect(
      rsa.single.toPublicKey().encode(),
      clearRsa.single.toPublicKey().encode(),
    );
    expect(
      ec.single.toPublicKey().encode(),
      clearEc.single.toPublicKey().encode(),
    );
  });

  test('keeps encrypted OpenSSH compatibility', () async {
    final key = await loadPrivateKey(fixture('openssh-ed25519'), passphrase);
    expect(key.single.name, 'ssh-ed25519');
    final hardenedPem = fixture('openssh-ed25519-a100');
    final hardened = OpenSSHKeyPairs.decode(SSHPem.decode(hardenedPem).content);
    expect((hardened.kdfOptions as OpenSSHBcryptKdfOptions).rounds, 100);
    final hardenedKey = await loadPrivateKey(
      hardenedPem,
      'harbor-test-passphrase',
    );
    expect(hardenedKey.single.name, 'ssh-ed25519');
    await expectLater(
      loadPrivateKey(fixture('openssh-ed25519'), ''),
      throwsA(privateKeyError('requires a passphrase')),
    );
    await expectLater(
      loadPrivateKey(fixture('openssh-ed25519'), 'wrong'),
      throwsA(privateKeyError('Check its passphrase')),
    );
  });

  test('rejects excessive OpenSSH bcrypt work before deriving a key', () async {
    await expectLater(
      loadPrivateKey(openSshWithRounds(1025), passphrase),
      throwsA(privateKeyError('supported limit of 1-1024')),
    );
  });

  test('reports missing and wrong passphrases', () async {
    await expectLater(
      loadPrivateKey(fixture('rsa-pkcs8.pem'), ''),
      throwsA(privateKeyError('requires a passphrase')),
    );
    await expectLater(
      loadPrivateKey(fixture('ec-legacy.pem'), 'wrong'),
      throwsA(privateKeyError('Check its passphrase')),
    );
    await expectLater(
      loadPrivateKey(fixture('rsa-legacy.pem'), ''),
      throwsA(privateKeyError('requires a passphrase')),
    );
    await expectLater(
      loadPrivateKey(fixture('rsa-legacy.pem'), 'wrong'),
      throwsA(privateKeyError('Check its passphrase')),
    );
  });

  test('reports unsupported key algorithms', () async {
    await expectLater(
      loadPrivateKey(ed25519WithNullParameters(), ''),
      throwsA(privateKeyError('malformed')),
    );
    await expectLater(
      loadPrivateKey(fixture('rsa-pkcs8-des3.pem'), passphrase),
      throwsA(privateKeyError('Unsupported PKCS#8 encryption algorithm')),
    );
  });

  test('rejects excessive PBKDF2 work before deriving a key', () async {
    await expectLater(
      loadPrivateKey(fixture('rsa-pkcs8-high-iterations.pem'), passphrase),
      throwsA(privateKeyError('iteration count')),
    );
  });

  test('rejects malformed, truncated, and oversized input', () async {
    await expectLater(
      loadPrivateKey('not a PEM', ''),
      throwsA(privateKeyError('malformed')),
    );
    final truncated = fixture('rsa-pkcs8.pem');
    await expectLater(
      loadPrivateKey(truncated.substring(0, truncated.length ~/ 2), passphrase),
      throwsA(privateKeyError('malformed')),
    );
    await expectLater(
      loadPrivateKey('x' * (256 * 1024 + 1), ''),
      throwsA(privateKeyError('256 KiB')),
    );
  });
}
