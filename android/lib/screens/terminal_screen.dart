import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

import '../models.dart';
import '../security_gate.dart';
import '../ssh_client.dart';
import '../ssh_session.dart';
import '../sync.dart';
import '../ui.dart';
import '../vault.dart';

class TerminalScreen extends StatefulWidget {
  const TerminalScreen({
    required this.connection,
    required this.onClose,
    required this.onReplace,
    super.key,
  });
  final Connection connection;
  final void Function(Connection) onClose;
  final void Function(Connection, Connection) onReplace;

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  final focus = FocusNode();
  TerminalController controller = TerminalController();
  late Connection current;
  bool retrying = false;
  bool syncing = false;
  bool cancelled = false;
  String? retryError;

  @override
  void initState() {
    super.initState();
    current = widget.connection;
    current.activeViews++;
    current.addListener(changed);
    if (!current.started) unawaited(current.connect());
  }

  void changed() {
    if (!mounted) return;
    if (current.normalExit && !cancelled) {
      cancelled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final route = ModalRoute.of(context);
        final navigator = Navigator.of(context);
        if (route?.isCurrent == true) {
          navigator.pop(true);
        } else if (route?.isActive == true) {
          navigator.removeRoute(route!);
        }
      });
    } else {
      setState(() {});
    }
  }

  @override
  void dispose() {
    cancelled = true;
    current.removeListener(changed);
    current.activeViews--;
    if (current.closed) current.dispose();
    focus.dispose();
    controller.dispose();
    super.dispose();
  }

  Future<void> retry({bool syncFirst = false}) async {
    if (retrying || cancelled) return;
    setState(() {
      retrying = true;
      syncing = syncFirst;
      retryError = null;
    });
    try {
      final vault = Vault();
      if (syncFirst) {
        await SyncService(
          vault,
        ).sync(cancelled: () => cancelled || !mounted || !unlocked.value);
      }
      if (cancelled || !mounted || !unlocked.value) return;
      final state = await vault.readState();
      if (cancelled || !mounted || !unlocked.value) return;
      final records = state['snapshot']?['hosts'];
      if (records is! List) {
        throw StateError(
          'No synced hosts are available. Sync from your desktop first.',
        );
      }
      final matches = records.where(
        (record) => record['id'] == current.host.id,
      );
      if (matches.isEmpty) {
        throw StateError(
          'This host is no longer on your desktop. Return to Hosts.',
        );
      }
      final next = Connection(
        Host.fromJson(Map<String, dynamic>.from(matches.first)),
      );
      try {
        widget.onReplace(current, next);
      } catch (_) {
        next.dispose();
        rethrow;
      }
      if (cancelled || !mounted || !unlocked.value) {
        next.dispose();
        return;
      }
      current.removeListener(changed);
      current.activeViews--;
      current.dispose();
      controller.dispose();
      controller = TerminalController();
      setState(() {
        current = next;
        current.activeViews++;
        retrying = false;
        syncing = false;
      });
      next.addListener(changed);
      unawaited(next.connect());
    } catch (error) {
      if (cancelled || !mounted || !unlocked.value) return;
      setState(() {
        retrying = false;
        syncing = false;
        retryError = syncFirst
            ? 'Sync failed. Keep Harbor open on your desktop, then try again.'
            : error is StateError
            ? error.message.toString()
            : 'Could not reload this host. Try syncing from your desktop.';
      });
    }
  }

  Future<void> editOnDesktop() async {
    final syncNow = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit on your desktop'),
        content: const Text(
          'Change this host in Harbor on your desktop and save it there. Then sync the updated host here and retry the connection.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sync and retry'),
          ),
        ],
      ),
    );
    if (syncNow == true && mounted) unawaited(retry(syncFirst: true));
  }

  Widget keyButton(
    String label,
    VoidCallback callback, {
    bool selected = false,
  }) => Padding(
    padding: const EdgeInsets.only(right: 6),
    child: TextButton(
      onPressed: callback,
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 40),
        foregroundColor: ink,
        backgroundColor: selected ? buttonFill : raised,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
  );

  Widget terminalBody() => SafeArea(
    child: Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 7, 16, 7),
          color: panel,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  '${current.host.username}@${current.host.address}:${current.host.port}',
                  style: const TextStyle(
                    color: muted,
                    fontSize: 13,
                    height: 1.35,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Connected',
                style: TextStyle(color: muted, fontSize: 13),
              ),
            ],
          ),
        ),
        Expanded(
          child: TerminalView(
            current.terminal,
            controller: controller,
            focusNode: focus,
            autofocus: true,
            padding: const EdgeInsets.all(8),
            textStyle: const TerminalStyle(fontSize: 13),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: const BoxDecoration(
            color: panel,
            border: Border(top: BorderSide(color: hairline)),
          ),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      keyButton('Esc', () => current.send('\x1b')),
                      keyButton(
                        'Ctrl',
                        () => setState(
                          () => current.controlNext = !current.controlNext,
                        ),
                        selected: current.controlNext,
                      ),
                      keyButton('Tab', () => current.send('\t')),
                      for (final entry in {
                        '↑': '\x1b[A',
                        '↓': '\x1b[B',
                        '←': '\x1b[D',
                        '→': '\x1b[C',
                      }.entries)
                        keyButton(entry.key, () => current.send(entry.value)),
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Show keyboard',
                onPressed: () => focus.requestFocus(),
                icon: const Icon(Icons.keyboard_outlined),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget connectionBody() {
    const steps = [
      (ConnectionStage.openingSocket, 'Reach server'),
      (ConnectionStage.verifyingHost, 'Verify host key'),
      (ConnectionStage.authenticating, 'Authenticate'),
      (ConnectionStage.openingShell, 'Open shell'),
    ];
    final stage = current.stage;
    final stopped =
        stage == ConnectionStage.failed ||
        stage == ConnectionStage.disconnected;
    final currentStep = stage == ConnectionStage.failed
        ? current.failedAt
        : stage;
    final position = steps.indexWhere((step) => step.$1 == currentStep);
    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, bounds) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: bounds.maxHeight),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          retrying
                              ? syncing
                                    ? 'Syncing hosts'
                                    : 'Preparing connection'
                              : stage == ConnectionStage.failed
                              ? 'Could not connect'
                              : stage == ConnectionStage.disconnected
                              ? 'Connection closed'
                              : 'Connecting',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${current.host.username}@${current.host.address}:${current.host.port}',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            color: muted,
                            fontSize: 14,
                          ),
                        ),
                        if (!retrying && (stopped || retryError != null)) ...[
                          const SizedBox(height: 12),
                          Text(
                            retryError ??
                                current.problem ??
                                'The remote shell closed.',
                            style: const TextStyle(
                              color: muted,
                              fontSize: 16,
                              height: 1.4,
                            ),
                          ),
                        ],
                        if (!retrying && current.serverMessage.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          const Text(
                            'Server message',
                            style: TextStyle(
                              color: ink,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: panel,
                              border: Border.all(color: hairline),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: SelectableText(
                              current.serverMessage,
                              style: const TextStyle(
                                color: ink,
                                fontSize: 14,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        for (var i = 0; i < steps.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 24,
                                  height: 24,
                                  child:
                                      retrying ||
                                          i > position &&
                                              stage !=
                                                  ConnectionStage.disconnected
                                      ? const Icon(
                                          Icons.circle_outlined,
                                          size: 19,
                                          color: muted,
                                        )
                                      : stopped &&
                                            stage == ConnectionStage.failed &&
                                            i == position
                                      ? Icon(
                                          Icons.close,
                                          size: 20,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.error,
                                        )
                                      : i < position ||
                                            stage ==
                                                ConnectionStage.disconnected
                                      ? const Icon(
                                          Icons.check,
                                          size: 20,
                                          color: Color(0xff70c997),
                                        )
                                      : const CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: action,
                                        ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Text(
                                    steps[i].$2,
                                    style: TextStyle(
                                      color:
                                          i > position &&
                                              stage !=
                                                  ConnectionStage.disconnected
                                          ? muted
                                          : ink,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (stopped && !retrying)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => unawaited(retry()),
                      child: const Text('Retry connection'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: editOnDesktop,
                      child: const Text('Edit on desktop'),
                    ),
                  ),
                ],
              ),
            )
          else if (!retrying)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Cancel connection'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final connected = current.stage == ConnectionStage.connected && !retrying;
    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) return;
        cancelled = true;
        if (result == true ||
            current.stage != ConnectionStage.connected ||
            retrying) {
          current.close();
          widget.onClose(current);
        }
      },
      child: Scaffold(
        backgroundColor: canvas,
        appBar: AppBar(
          title: Text(
            current.host.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            if (connected)
              IconButton(
                tooltip: 'Copy selection',
                onPressed: () {
                  final selection = controller.selection;
                  if (selection != null) {
                    Clipboard.setData(
                      ClipboardData(
                        text: current.terminal.buffer.getText(selection),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.copy_outlined, size: 21),
              ),
            if (connected)
              IconButton(
                tooltip: 'Back to sessions',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.view_list_outlined, size: 23),
              ),
            IconButton(
              tooltip: connected ? 'Close session' : 'Cancel connection',
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.close, size: 22),
            ),
          ],
        ),
        body: connected ? terminalBody() : connectionBody(),
      ),
    );
  }
}
