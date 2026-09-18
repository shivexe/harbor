import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class Vault {
  final FlutterSecureStorage storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      resetOnError: false,
      storageNamespace: 'harbor_v1',
    ),
  );
  Future<Map<String, dynamic>> readState() async {
    final value = await storage.read(key: 'vault');
    return value == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(jsonDecode(value));
  }

  Future<Map<String, dynamic>?> read(String key) async {
    final state = await readState();
    return state[key] == null ? null : Map<String, dynamic>.from(state[key]);
  }

  Future<void> writeState(
    Map<String, dynamic> pairing,
    Map<String, dynamic>? snapshot,
  ) => storage.write(
    key: 'vault',
    value: jsonEncode({'pairing': pairing, 'snapshot': snapshot}),
  );
  Future<void> clear() => storage.deleteAll();
}
