import 'dart:async';

import 'package:flutter/material.dart';

import 'screens/pair_screen.dart';
import 'screens/terminal_screen.dart';
import 'models.dart';
import 'ssh_session.dart';
import 'vault.dart';
import 'sync.dart';
import 'security_gate.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const HarborApp());
}

const navy = Color(0xff0b1424);
const surface = Color(0xff142138);
const accent = Color(0xff91afff);

class HarborApp extends StatelessWidget {
  const HarborApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: navigatorKey,
    builder: (_, child) => SecurityGate(child: child!),
    title: 'Harbor',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      fontFamily: 'Roboto',
      brightness: Brightness.dark,
      scaffoldBackgroundColor: navy,
      colorScheme: const ColorScheme.dark(
        primary: accent,
        surface: surface,
        onSurface: Color(0xffedf2ff),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: navy,
        scrolledUnderElevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    ),
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
  String? comparison;
  bool pairingCancelled = false;
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
      pairingCancelled = true;
      for (final session in sessions) {
        session.dispose();
      }
      if (mounted) {
        setState(() {
          sessions.clear();
          hosts = [];
          desktop = null;
          lastSync = null;
          comparison = null;
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
    final code = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const PairScreen()));
    if (!mounted) return;
    if (code == null) {
      setState(() => busy = false);
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    pairingCancelled = false;
    try {
      await SyncService(vault).pair(code, (value, name) {
        if (mounted) setState(() => comparison = value);
      }, cancelled: () => pairingCancelled || !mounted);
      if (mounted) {
        setState(() {
          comparison = null;
          for (final session in sessions) {
            session.dispose();
          }
          sessions.clear();
        });
      }
      await SyncService(
        vault,
      ).sync(cancelled: () => pairingCancelled || !mounted || !unlocked.value);
      await load();
    } catch (_) {
      await load();
      if (mounted) {
        setState(() {
          error =
              'Pairing or initial sync failed. Generate a fresh code on your desktop and try again.';
          busy = false;
          comparison = null;
        });
      }
    }
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
    for (final session in sessions) {
      session.dispose();
    }
    super.dispose();
  }

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
            Icon(Icons.sailing_outlined, color: accent),
            SizedBox(width: 10),
            Text(
              'Harbor',
              style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: -.5),
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
            onSelected: (value) {
              if (value == 'pair') {
                pair();
              } else {
                forget();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'pair', child: Text('Pair desktop')),
              if (desktop != null)
                const PopupMenuItem(
                  value: 'forget',
                  child: Text('Unpair device'),
                ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Your hosts.',
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    desktop == null
                        ? 'Pair your desktop. Take your terminal with you.'
                        : 'From $desktop',
                    style: const TextStyle(
                      color: Color(0xffa1b1cb),
                      fontSize: 15,
                    ),
                  ),
                  if (lastSync != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Text(
                        'Last synced ${lastSync!.toLocal().toString().substring(0, 16)}',
                        style: const TextStyle(
                          color: Color(0xffa1b1cb),
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (busy) const LinearProgressIndicator(minHeight: 2),
            if (comparison != null)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Compare this code on your desktop, then approve pairing.',
                    ),
                    const SizedBox(height: 12),
                    Text(
                      comparison!,
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 6,
                        color: accent,
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() {
                        pairingCancelled = true;
                        comparison = null;
                      }),
                      child: const Text('Cancel pairing'),
                    ),
                  ],
                ),
              ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (sessions.isNotEmpty)
              SizedBox(
                height: 58,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  scrollDirection: Axis.horizontal,
                  itemCount: sessions.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => ActionChip(
                    avatar: const Icon(Icons.terminal, size: 16),
                    label: Text(sessions[i].host.name),
                    onPressed: () => unawaited(terminal(sessions[i])),
                  ),
                ),
              ),
            if (desktop != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 8,
                ),
                child: TextField(
                  onChanged: (value) {
                    noteInteraction();
                    setState(() => query = value);
                  },
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Find a host',
                    contentPadding: EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            Expanded(
              child: desktop == null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.devices_outlined,
                              size: 80,
                              color: accent,
                            ),
                            const SizedBox(height: 28),
                            const Text(
                              'One collection. Anywhere.',
                              style: TextStyle(
                                fontSize: 23,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Add and organize hosts on your desktop. Harbor keeps a secure copy here for direct SSH connections.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Color(0xffa1b1cb),
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 28),
                            FilledButton.icon(
                              onPressed: busy ? null : pair,
                              icon: const Icon(Icons.qr_code_scanner),
                              label: const Text('Pair desktop'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : filtered.isEmpty
                  ? Center(
                      child: Text(
                        hosts.isEmpty
                            ? 'Add hosts on your desktop, then sync.'
                            : 'No hosts match your search.',
                        style: const TextStyle(color: Color(0xffa1b1cb)),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: sync,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final host = filtered[index];
                          final showGroup =
                              index == 0 ||
                              filtered[index - 1].group != host.group;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (showGroup)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    top: 16,
                                    bottom: 8,
                                  ),
                                  child: Text(
                                    host.group.isEmpty
                                        ? 'Ungrouped'
                                        : host.group,
                                    style: const TextStyle(
                                      color: accent,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                elevation: 0,
                                color: surface,
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 6,
                                  ),
                                  leading: Container(
                                    width: 42,
                                    height: 42,
                                    decoration: BoxDecoration(
                                      color: accent.withValues(alpha: .1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(
                                      Icons.dns_outlined,
                                      color: accent,
                                    ),
                                  ),
                                  title: Text(
                                    host.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${host.username}@${host.address}:${host.port}',
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xffa1b1cb),
                                      fontSize: 12,
                                    ),
                                  ),
                                  trailing: const Icon(
                                    Icons.chevron_right,
                                    color: accent,
                                  ),
                                  onTap: () => open(host),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
