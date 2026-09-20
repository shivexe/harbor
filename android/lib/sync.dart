import 'sync_client.dart';
import 'vault.dart';

class SyncService {
  SyncService(this.vault, {SyncClient? client})
    : client = client ?? SyncClient();
  final Vault vault;
  final SyncClient client;
  Map<String, dynamic>? pendingPairing;

  Future<void> pair(
    String code,
    void Function(String, String) onComparison, {
    bool Function()? cancelled,
  }) async {
    final pairing = await client.pair(code, onComparison, cancelled: cancelled);
    if (cancelled?.call() == true) throw StateError('Pairing cancelled');
    final previous = await vault.readState();
    if (cancelled?.call() == true) throw StateError('Pairing cancelled');
    if (previous['pairing'] == null) {
      await vault.writeState(pairing, null);
    } else {
      pendingPairing = pairing;
    }
  }

  Future<void> sync({bool Function()? cancelled}) async {
    final replacement = pendingPairing;
    if (replacement != null) {
      final snapshot = await client.sync(replacement, 0);
      if (cancelled?.call() == true) throw StateError('Sync cancelled');
      await vault.writeState(replacement, snapshot);
      pendingPairing = null;
      return;
    }
    final state = await vault.readState();
    final pairing = state['pairing'] == null
        ? null
        : Map<String, dynamic>.from(state['pairing']);
    if (pairing == null) throw StateError('Pair desktop first');
    final previous = state['snapshot'];
    final snapshot = await client.sync(pairing, previous?['revision'] ?? 0);
    if (cancelled?.call() == true) throw StateError('Sync cancelled');
    await vault.writeState(pairing, snapshot);
  }
}
