import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harbor/sync.dart';
import 'package:harbor/sync_client.dart';
import 'package:harbor/vault.dart';

class FixtureClient extends SyncClient {
  bool failSync = false;
  void Function()? beforeSyncReturns;

  @override
  Future<Map<String, dynamic>> pair(
    String code,
    void Function(String, String) onComparison, {
    bool Function()? cancelled,
  }) async {
    onComparison('123456', 'New desktop');
    return {'desktopName': 'New desktop', 'vaultId': 'new-vault'};
  }

  @override
  Future<Map<String, dynamic>> sync(
    Map<String, dynamic> pairing,
    int revision,
  ) async {
    expect(pairing['desktopName'], 'New desktop');
    expect(revision, 0);
    beforeSyncReturns?.call();
    if (failSync) throw StateError('Desktop unavailable');
    return {'revision': 1, 'hosts': [], 'vaultId': 'new-vault'};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'replacement keeps old hosts until first verified sync commits',
    () async {
      final oldPairing = {'desktopName': 'Old desktop', 'vaultId': 'old-vault'};
      final oldSnapshot = {
        'revision': 7,
        'hosts': [
          {'name': 'Old host'},
        ],
      };
      FlutterSecureStorage.setMockInitialValues({
        'vault': jsonEncode({'pairing': oldPairing, 'snapshot': oldSnapshot}),
      });
      final vault = Vault();
      final client = FixtureClient()..failSync = true;
      final service = SyncService(vault, client: client);

      await service.pair('replacement', (_, _) {});
      expect(await vault.readState(), {
        'pairing': oldPairing,
        'snapshot': oldSnapshot,
      });
      await expectLater(service.sync(), throwsStateError);
      expect(await vault.readState(), {
        'pairing': oldPairing,
        'snapshot': oldSnapshot,
      });

      client.failSync = false;
      await service.sync();
      final committed = await vault.readState();
      expect(committed['pairing']['desktopName'], 'New desktop');
      expect(committed['snapshot']['revision'], 1);
      expect(committed['snapshot']['hosts'], isEmpty);
    },
  );

  test('locking after the sync response preserves the old snapshot', () async {
    final oldPairing = {'desktopName': 'Old desktop'};
    final oldSnapshot = {'revision': 2, 'hosts': []};
    FlutterSecureStorage.setMockInitialValues({
      'vault': jsonEncode({'pairing': oldPairing, 'snapshot': oldSnapshot}),
    });
    final vault = Vault();
    final client = FixtureClient();
    final service = SyncService(vault, client: client);
    await service.pair('replacement', (_, _) {});
    var locked = false;
    client.beforeSyncReturns = () => locked = true;

    await expectLater(service.sync(cancelled: () => locked), throwsStateError);
    expect(await vault.readState(), {
      'pairing': oldPairing,
      'snapshot': oldSnapshot,
    });
  });

  test(
    'first pairing persists approval for retry after failed first sync',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final vault = Vault();
      final client = FixtureClient()..failSync = true;
      final service = SyncService(vault, client: client);

      await service.pair('first', (_, _) {});
      expect(
        (await vault.readState())['pairing']['desktopName'],
        'New desktop',
      );
      await expectLater(service.sync(), throwsStateError);
      expect(
        (await vault.readState())['pairing']['desktopName'],
        'New desktop',
      );

      client.failSync = false;
      await service.sync();
      expect((await vault.readState())['snapshot']['revision'], 1);
    },
  );
}
