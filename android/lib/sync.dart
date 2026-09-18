import 'sync_client.dart';
import 'vault.dart';

class SyncService {
  SyncService(this.vault);
  final Vault vault;
  Future<void> pair(
    String code,
    void Function(String, String) onComparison, {
    bool Function()? cancelled,
  }) async {
    final pairing = await SyncClient().pair(
      code,
      onComparison,
      cancelled: cancelled,
    );
    if (cancelled?.call() == true) throw StateError('Pairing cancelled');
    await vault.writeState(pairing, null);
  }

  Future<void> sync({bool Function()? cancelled}) async {
    final state = await vault.readState();
    final pairing = state['pairing'] == null
        ? null
        : Map<String, dynamic>.from(state['pairing']);
    if (pairing == null) throw StateError('Pair desktop first');
    final previous = state['snapshot'];
    final snapshot = await SyncClient().sync(
      pairing,
      previous?['revision'] ?? 0,
    );
    if (cancelled?.call() == true) throw StateError('Sync cancelled');
    await vault.writeState(pairing, snapshot);
  }
}
