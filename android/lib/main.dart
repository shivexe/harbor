import 'dart:async';

import 'package:flutter/material.dart';

import 'screens/pair_screen.dart';
import 'screens/terminal_screen.dart';
import 'models.dart';
import 'ssh_session.dart';
import 'vault.dart';
import 'sync.dart';
import 'security_gate.dart';
import 'ui.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const HarborApp());
}

class HarborApp extends StatelessWidget {
  const HarborApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: navigatorKey,
    builder: (_, child) => SecurityGate(child: child!),
    title: 'Harbor',
    debugShowCheckedModeBanner: false,
    theme: harborTheme(),
    home: const HostsScreen(),
  );
}

class HostsScreen extends StatefulWidget {
  const HostsScreen({super.key});
  @override
  State<HostsScreen> createState() => _HostsScreenState();
}

class _HostsScreenState extends State<HostsScreen> {
  final vault = Vault();
  final sessions = <Connection>[];
  List<Host> hosts = [];
  String query = '';
  String? desktop;
  DateTime? lastSync;
  String? error;
  bool busy = true;
  @override
  void initState() {
    super.initState();
    busy = false;
    unlocked.addListener(lockChanged);
    if (unlocked.value) {
      busy = true;
      unawaited(load());
    }
  }

  void lockChanged() {
    if (unlocked.value) {
      unawaited(load());
    } else {
      for (final session in sessions) {
        session.dispose();
      }
      if (mounted) {
        setState(() {
          sessions.clear();
          hosts = [];
          desktop = null;
          lastSync = null;
          error = null;
          busy = false;
        });
      }
    }
  }

  Future<void> load() async {
    try {
      final state = await vault.readState();
      final pair = state['pairing'];
      final snapshot = state['snapshot'];
      final loaded = ((snapshot?['hosts'] ?? []) as List)
          .map((e) => Host.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      if (mounted && unlocked.value) {
        setState(() {
          hosts = loaded;
          desktop = pair?['desktopName'];
          lastSync = DateTime.tryParse(snapshot?['syncedAt'] ?? '');
          busy = false;
        });
      }
    } catch (_) {
      if (mounted && unlocked.value) {
        setState(() {
          error = 'Secure storage could not be opened. Try restarting Harbor.';
          busy = false;
        });
      }
    }
  }

  Future<void> sync() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await SyncService(
        vault,
      ).sync(cancelled: () => !mounted || !unlocked.value);
      await load();
    } on StateError catch (failure) {
      if (mounted && unlocked.value) {
        setState(() {
          error = failure.message == 'Device revoked on desktop'
              ? 'This device was unpaired on your desktop. Use Switch desktop to pair again. Saved hosts remain available.'
              : 'Sync failed. Open Harbor on your paired desktop and check the network.';
          busy = false;
        });
      }
    } catch (_) {
      if (mounted && unlocked.value) {
        setState(() {
          error =
              'Sync failed. Open Harbor on your paired desktop and check the network.';
          busy = false;
        });
      }
    }
  }

  Future<void> pair() async {
    if (busy) return;
    if (desktop != null) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Switch desktop?'),
          content: const Text(
            'Your current hosts stay available until the new desktop pairs and finishes its first sync.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;
    }
    setState(() => busy = true);
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PairScreen(
          replacing: desktop != null,
          onPaired: () {
            if (!mounted) return;
            for (final session in sessions) {
              session.dispose();
            }
            setState(sessions.clear);
          },
        ),
      ),
    );
    if (!mounted) return;
    await load();
  }

  void open(Host host) {
    final connection = Connection(host);
    watchSession(connection);
    setState(() => sessions.add(connection));
    unawaited(terminal(connection));
  }

  void watchSession(Connection connection) {
    connection.onNormalExit = (finished) {
      if (mounted) setState(() => sessions.remove(finished));
      if (finished.activeViews == 0) finished.dispose();
    };
  }

  Future<void> terminal(Connection connection) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TerminalScreen(
          connection: connection,
          onClose: (current) {
            current.close();
            if (mounted) setState(() => sessions.remove(current));
          },
          onReplace: (previous, fresh) {
            if (!mounted || !unlocked.value) {
              throw StateError('Session closed');
            }
            final index = sessions.indexOf(previous);
            if (index < 0) throw StateError('Session closed');
            watchSession(fresh);
            setState(() => sessions[index] = fresh);
          },
        ),
      ),
    );
    if (connection.closed) connection.dispose();
    if (mounted && unlocked.value) await load();
  }

  Future<void> forget() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unpair this device?'),
        content: const Text(
          'Saved hosts, credentials and trusted server keys will be removed. Active sessions will close.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Unpair'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      if (mounted) setState(() => busy = false);
      return;
    }
    try {
      await vault.clear();
    } catch (_) {
      if (mounted && unlocked.value) {
        setState(() {
          busy = false;
          error =
              'Could not remove this device. Check secure storage and try again.';
        });
      }
      return;
    }
    for (final session in sessions) {
      session.dispose();
    }
    if (!mounted) return;
    setState(() {
      sessions.clear();
      desktop = null;
      hosts = [];
      lastSync = null;
      busy = false;
    });
  }

  @override
  void dispose() {
    unlocked.removeListener(lockChanged);
    search.dispose();
    for (final session in sessions) {
      session.dispose();
    }
    super.dispose();
  }

  String get syncLabel {
    if (lastSync == null) return 'Not synced yet';
    final elapsed = DateTime.now().difference(lastSync!.toLocal());
    if (elapsed.inMinutes < 1) return 'Synced just now';
    if (elapsed.inHours < 1) return 'Synced ${elapsed.inMinutes}m ago';
    if (elapsed.inDays < 1) return 'Synced ${elapsed.inHours}h ago';
    return 'Synced ${lastSync!.toLocal().year}-${lastSync!.toLocal().month.toString().padLeft(2, '0')}-${lastSync!.toLocal().day.toString().padLeft(2, '0')}';
  }

  Widget issueBanner() => Container(
    margin: const EdgeInsets.fromLTRB(20, 8, 20, 0),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: panel,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(
        color: Theme.of(context).colorScheme.error.withValues(alpha: .5),
      ),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            error!,
            style: const TextStyle(fontSize: 14, height: 1.4),
          ),
        ),
      ],
    ),
  );

  Widget onboarding() => SingleChildScrollView(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Connect to your hosts',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text(
            'Pair with Harbor on your desktop to sync your hosts securely.',
            style: TextStyle(color: muted, fontSize: 16, height: 1.4),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: busy ? null : pair,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scan QR code'),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'On your desktop, open Devices, then Pair Android.',
            style: TextStyle(color: muted, fontSize: 14, height: 1.35),
          ),
        ],
      ),
    ),
  );

  Widget sessionsPanel() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Row(
          children: [
            const Text(
              'Sessions',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 8),
            Text(
              '${sessions.length}',
              style: const TextStyle(color: muted, fontSize: 14),
            ),
          ],
        ),
      ),
      SizedBox(
        height: 64,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: sessions.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final session = sessions[index];
            return Material(
              color: raised,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => unawaited(terminal(session)),
                child: SizedBox(
                  width: 210,
                  child: Row(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 0, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                session.host.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                session.status,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close ${session.host.name} session',
                        onPressed: () {
                          session.dispose();
                          setState(() => sessions.remove(session));
                        },
                        icon: const Icon(Icons.close, size: 18),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
      const SizedBox(height: 8),
    ],
  );

  Widget hostList(List<Host> filtered) {
    if (filtered.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                hosts.isEmpty
                    ? 'No hosts on this device yet'
                    : 'No matching hosts',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                hosts.isEmpty
                    ? 'Add hosts on your desktop, then sync here.'
                    : 'Try a different name, group, or address.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: muted, fontSize: 14),
              ),
              const SizedBox(height: 16),
              if (hosts.isEmpty)
                TextButton(
                  onPressed: busy ? null : sync,
                  child: const Text('Sync now'),
                )
              else
                TextButton(
                  onPressed: () {
                    search.clear();
                    setState(() => query = '');
                  },
                  child: const Text('Clear search'),
                ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: sync,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        itemCount: filtered.length,
        itemBuilder: (context, index) {
          final host = filtered[index];
          final showGroup =
              index == 0 || filtered[index - 1].group != host.group;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showGroup)
                Padding(
                  padding: EdgeInsets.only(
                    top: index == 0 ? 12 : 16,
                    bottom: 4,
                  ),
                  child: Text(
                    host.group.isEmpty ? 'Ungrouped' : host.group,
                    style: const TextStyle(
                      color: muted,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              Material(
                color: canvas,
                child: InkWell(
                  onTap: () => open(host),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 64),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: hairline, width: .5),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.terminal, size: 20, color: muted),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                host.name,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${host.username}@${host.address}:${host.port}',
                                style: const TextStyle(
                                  color: muted,
                                  fontSize: 14,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.chevron_right, color: muted, size: 18),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  final search = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final filtered =
        hosts
            .where(
              (h) => '${h.name} ${h.address} ${h.username} ${h.group}'
                  .toLowerCase()
                  .contains(query.toLowerCase()),
            )
            .toList()
          ..sort((a, b) {
            final group = a.group.compareTo(b.group);
            return group == 0 ? a.name.compareTo(b.name) : group;
          });

    return Scaffold(
      appBar: AppBar(
        title: Text(desktop == null ? 'Harbor' : 'Hosts'),
        actions: [
          if (desktop != null)
            TextButton.icon(
              onPressed: busy ? null : sync,
              icon: const Icon(Icons.sync, size: 19),
              label: const Text('Sync'),
            ),
          if (desktop != null)
            PopupMenuButton<String>(
              enabled: !busy,
              tooltip: 'More options',
              onSelected: (value) {
                if (value == 'pair') {
                  unawaited(pair());
                } else {
                  unawaited(forget());
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'pair',
                  child: Text('Switch desktop'),
                ),
                const PopupMenuItem(
                  value: 'forget',
                  child: Text('Unpair this device'),
                ),
              ],
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (busy) const LinearProgressIndicator(minHeight: 2),
            if (error != null) issueBanner(),
            if (desktop == null)
              Expanded(child: onboarding())
            else ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        desktop!,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        style: const TextStyle(fontSize: 14, color: ink),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        syncLabel,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        textAlign: TextAlign.end,
                        style: const TextStyle(fontSize: 13, color: muted),
                      ),
                    ),
                  ],
                ),
              ),
              if (sessions.isNotEmpty) sessionsPanel(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: TextField(
                  controller: search,
                  onChanged: (value) {
                    noteInteraction();
                    setState(() => query = value);
                  },
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search, color: muted),
                    hintText: 'Search hosts',
                    suffixIcon: query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            onPressed: () {
                              search.clear();
                              setState(() => query = '');
                            },
                            icon: const Icon(Icons.close),
                          ),
                  ),
                ),
              ),
              Expanded(child: hostList(filtered)),
            ],
          ],
        ),
      ),
    );
  }
}
