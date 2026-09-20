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
      if (mounted) {
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
    } catch (_) {
      if (mounted) {
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
    setState(() => busy = true);
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PairScreen(
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
    setState(() => sessions.add(connection));
    unawaited(terminal(connection));
  }

  Future<void> terminal(Connection connection) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TerminalScreen(
          connection: connection,
          onClose: () {
            connection.close();
            setState(() => sessions.remove(connection));
          },
        ),
      ),
    );
    if (connection.closed) connection.dispose();
    if (mounted) setState(() {});
  }

  Future<void> forget() async {
    if (busy) return;
    setState(() => busy = true);
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
    for (final session in sessions) {
      session.dispose();
    }
    await vault.clear();
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
      padding: const EdgeInsets.fromLTRB(24, 52, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: panel,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: hairline),
            ),
            child: const Icon(Icons.qr_code_2, color: action, size: 34),
          ),
          const SizedBox(height: 32),
          const Text(
            'Your hosts,\nwithin reach.',
            style: TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w700,
              letterSpacing: -1,
              height: 1.13,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Scan the QR code in Harbor on your desktop to bring your host collection here.',
            style: TextStyle(color: muted, fontSize: 16, height: 1.45),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: busy ? null : pair,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scan QR code'),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'On your desktop, open Devices and choose Pair Android.',
            style: TextStyle(color: muted, fontSize: 14, height: 1.4),
          ),
        ],
      ),
    ),
  );

  Widget sessionsPanel() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 10),
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
        height: 78,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          itemCount: sessions.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final session = sessions[index];
            return Material(
              color: raised,
              borderRadius: BorderRadius.circular(9),
              child: InkWell(
                borderRadius: BorderRadius.circular(9),
                onTap: () => unawaited(terminal(session)),
                child: SizedBox(
                  width: 180,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
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
                          style: const TextStyle(fontSize: 13, color: muted),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
      const Divider(height: 24, color: hairline),
    ],
  );

  Widget hostList(List<Host> filtered) {
    if (filtered.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                hosts.isEmpty ? Icons.dns_outlined : Icons.search_off,
                size: 42,
                color: muted,
              ),
              const SizedBox(height: 16),
              Text(
                hosts.isEmpty
                    ? 'No hosts on this device yet'
                    : 'No matching hosts',
                style: const TextStyle(
                  fontSize: 18,
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
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 32),
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
                    top: index == 0 ? 16 : 26,
                    bottom: 8,
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
                color: panel,
                child: InkWell(
                  onTap: () => open(host),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 72),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: hairline, width: .5),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.dns_outlined, size: 21, color: action),
                        const SizedBox(width: 16),
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
                                host.auth == 'none'
                                    ? 'No password · ${host.username}@${host.address}:${host.port}'
                                    : '${host.username}@${host.address}:${host.port}',
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
                        const Icon(Icons.chevron_right, color: muted, size: 20),
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
        title: const Row(
          children: [
            Icon(Icons.terminal, color: action, size: 25),
            SizedBox(width: 10),
            Text(
              'Harbor',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        actions: [
          if (desktop != null)
            IconButton(
              onPressed: busy ? null : sync,
              tooltip: 'Sync hosts',
              icon: const Icon(Icons.sync),
            ),
          PopupMenuButton<String>(
            enabled: !busy,
            tooltip: 'More options',
            onSelected: (value) {
              if (value == 'pair') {
                pair();
              } else {
                forget();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'pair',
                child: Text('Pair another desktop'),
              ),
              if (desktop != null)
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
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Hosts',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -.8,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      'From $desktop',
                      style: const TextStyle(fontSize: 16, color: muted),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      syncLabel,
                      style: const TextStyle(fontSize: 14, color: muted),
                    ),
                  ],
                ),
              ),
              if (sessions.isNotEmpty) sessionsPanel(),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
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
