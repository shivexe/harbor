import 'dart:convert';

class Host {
  const Host({
    required this.id,
    required this.name,
    required this.address,
    required this.port,
    required this.username,
    required this.group,
    required this.auth,
    required this.password,
    required this.privateKey,
    required this.passphrase,
    required this.hostKey,
  });
  final String id,
      name,
      address,
      username,
      group,
      auth,
      password,
      privateKey,
      passphrase,
      hostKey;
  final int port;
  factory Host.fromJson(Map<String, dynamic> json) {
    for (final field in [
      'id',
      'name',
      'hostname',
      'username',
      'group',
      'authType',
      'password',
      'privateKey',
      'passphrase',
      'hostKey',
      'notes',
    ]) {
      if (json[field] is! String) {
        throw const FormatException('Invalid host record');
      }
    }
    final port = json['port'];
    final auth = json['authType'];
    if (port is! int ||
        port < 1 ||
        port > 65535 ||
        !{'password', 'key'}.contains(auth)) {
      throw const FormatException('Invalid host record');
    }
    for (final field in ['id', 'name', 'hostname', 'username']) {
      if ((json[field] as String).trim().isEmpty) {
        throw const FormatException('Invalid host record');
      }
    }
    if (utf8.encode(json['privateKey']).length > 262144 ||
        utf8.encode(jsonEncode(json)).length > 1048576) {
      throw const FormatException('Host record too large');
    }
    if ((json['hostname'] as String).startsWith('-') ||
        (json['username'] as String).startsWith('-') ||
        (json['hostname'] as String).contains(RegExp(r'[\s\x00-\x1f]')) ||
        (json['username'] as String).contains(RegExp(r'[\s\x00-\x1f]'))) {
      throw const FormatException('Invalid host address');
    }
    if ((json['hostKey'] as String).isNotEmpty) {
      final parts = (json['hostKey'] as String).split(' ');
      if (parts.length != 2 ||
          base64Decode(parts[1]).isEmpty ||
          base64Decode(parts[1]).length > 16384) {
        throw const FormatException('Invalid host key');
      }
    }
    return Host(
      id: json['id'],
      name: json['name'],
      address: json['hostname'],
      port: port,
      username: json['username'],
      group: json['group'],
      auth: auth,
      password: json['password'],
      privateKey: json['privateKey'],
      passphrase: json['passphrase'],
      hostKey: json['hostKey'],
    );
  }
}
