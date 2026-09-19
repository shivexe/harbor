import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../security_gate.dart';
import '../sync.dart';
import '../ui.dart';
import '../vault.dart';

class PairScreen extends StatefulWidget {
  const PairScreen({
    this.scannerBuilder,
    this.service,
    this.onPaired,
    super.key,
  });
  final Widget Function(ValueChanged<String>)? scannerBuilder;
  final SyncService? service;
  final VoidCallback? onPaired;

  @override
  State<PairScreen> createState() => _PairScreenState();
}

class _PairScreenState extends State<PairScreen> {
  final vault = Vault();
  SyncService get service => widget.service ?? SyncService(vault);
  String phase = 'scan';
  String? comparison;
  String? desktopName;
  String? error;
  bool paired = false;
  bool cancelled = false;
  bool pasteOpen = false;
  int scanAttempt = 0;

  bool get wasCancelled => cancelled || !mounted || !unlocked.value;

  @override
  void dispose() {
    cancelled = true;
    super.dispose();
  }

  void resetScan() {
    setState(() {
      phase = 'scan';
      comparison = null;
      error = null;
      scanAttempt++;
    });
  }

  void accept(String invitation) {
    if (phase != 'scan' || pasteOpen || invitation.trim().isEmpty) return;
    setState(() {
      phase = 'waiting';
      error = null;
    });
    unawaited(pair(invitation.trim()));
  }

  Future<void> pair(String invitation) async {
    try {
      await service.pair(invitation, (code, name) {
        if (!wasCancelled) {
          setState(() {
            comparison = code;
            desktopName = name;
          });
        }
      }, cancelled: () => wasCancelled);
      if (wasCancelled) return;
      paired = true;
      widget.onPaired?.call();
      setState(() => phase = 'syncing');
      await sync();
    } catch (failure) {
      if (wasCancelled) return;
      setState(() {
        phase = 'error';
        error = failure is FormatException
            ? 'This invitation is invalid or expired. Generate a new QR code on your desktop.'
            : 'Pairing was not completed. Check both devices are on the same network, then generate a new QR code.';
      });
    }
  }

  Future<void> sync() async {
    try {
      await service.sync(cancelled: () => wasCancelled);
      if (!wasCancelled && mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (wasCancelled) return;
      setState(() {
        phase = 'error';
        error =
            'Desktop paired, but hosts could not sync. Keep Harbor open on your desktop and retry.';
      });
    }
  }

  Future<void> pasteInvitation() async {
    if (pasteOpen) return;
    setState(() => pasteOpen = true);
    final invitation = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => const _PasteInvitationSheet(),
    );
    if (!mounted) return;
    setState(() => pasteOpen = false);
    if (invitation != null) accept(invitation);
  }

  Widget scanner() =>
      widget.scannerBuilder?.call(accept) ??
      MobileScanner(
        key: ValueKey(scanAttempt),
        onDetect: (capture) {
          for (final barcode in capture.barcodes) {
            if (barcode.rawValue case final String value) {
              accept(value);
              break;
            }
          }
        },
        errorBuilder: (context, failure) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.no_photography_outlined,
                  size: 40,
                  color: muted,
                ),
                const SizedBox(height: 16),
                Text(
                  failure.errorCode == MobileScannerErrorCode.permissionDenied
                      ? 'Allow camera access in Android Settings, then return to scan.'
                      : 'The camera is unavailable. You can paste the invitation instead.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: muted, fontSize: 14),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: resetScan,
                  child: const Text('Try camera again'),
                ),
              ],
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Pair desktop')),
    body: SafeArea(
      child: switch (phase) {
        'scan' => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 24, 24, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Scan the QR code',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -.6,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'On your desktop, open Devices and choose Pair Android.',
                    style: TextStyle(fontSize: 16, color: muted, height: 1.35),
                  ),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, bounds) {
                  final frame = min(
                    276.0,
                    min(bounds.maxWidth - 48, bounds.maxHeight - 32),
                  ).clamp(0.0, 276.0);
                  return Container(
                    color: const Color(0xff101217),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (!pasteOpen) scanner(),
                        Center(
                          child: IgnorePointer(
                            child: Container(
                              width: frame,
                              height: frame,
                              decoration: BoxDecoration(
                                border: Border.all(color: action, width: 2),
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
              child: SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: pasteInvitation,
                  icon: const Icon(Icons.content_paste_outlined, size: 19),
                  label: const Text('Paste invitation instead'),
                ),
              ),
            ),
          ],
        ),
        _ => LayoutBuilder(
          builder: (context, bounds) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: bounds.maxHeight),
              child: IntrinsicHeight(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 48),
                      Icon(
                        phase == 'error'
                            ? Icons.error_outline
                            : Icons.devices_outlined,
                        color: phase == 'error'
                            ? Theme.of(context).colorScheme.error
                            : action,
                        size: 42,
                      ),
                      const SizedBox(height: 24),
                      Text(
                        phase == 'error'
                            ? paired
                                  ? 'Paired. Sync needed.'
                                  : 'Could not pair.'
                            : phase == 'syncing'
                            ? 'Bringing your hosts over.'
                            : 'Approve on your desktop.',
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -.6,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        error ??
                            (phase == 'syncing'
                                ? 'Your encrypted host collection is syncing now.'
                                : 'Compare this code with the one shown on ${desktopName ?? 'your desktop'}, then approve there.'),
                        style: const TextStyle(
                          fontSize: 16,
                          color: muted,
                          height: 1.4,
                        ),
                      ),
                      if (comparison != null && phase == 'waiting') ...[
                        const SizedBox(height: 32),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          decoration: BoxDecoration(
                            color: panel,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            comparison!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 40,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 6,
                              color: action,
                            ),
                          ),
                        ),
                      ],
                      if (phase != 'error') ...[
                        const SizedBox(height: 24),
                        const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: action,
                          ),
                        ),
                      ],
                      const Spacer(),
                      if (phase == 'error')
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: paired
                                ? () {
                                    setState(() => phase = 'syncing');
                                    unawaited(sync());
                                  }
                                : resetScan,
                            child: Text(
                              paired ? 'Retry sync' : 'Scan a new QR code',
                            ),
                          ),
                        ),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(
                          phase == 'error' ? 'Done' : 'Cancel pairing',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      },
    ),
  );
}

class _PasteInvitationSheet extends StatefulWidget {
  const _PasteInvitationSheet();

  @override
  State<_PasteInvitationSheet> createState() => _PasteInvitationSheetState();
}

class _PasteInvitationSheetState extends State<_PasteInvitationSheet> {
  final input = TextEditingController();

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      24,
      24,
      24,
      MediaQuery.viewInsetsOf(context).bottom + 24,
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Paste an invitation',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text(
            'Use this if you cannot scan the QR code on your desktop.',
            style: TextStyle(color: muted, fontSize: 14),
          ),
          const SizedBox(height: 24),
          Semantics(
            label: 'Invitation text',
            child: TextField(
              controller: input,
              minLines: 3,
              maxLines: 5,
              autocorrect: false,
              enableSuggestions: false,
              onChanged: (_) => noteInteraction(),
              decoration: const InputDecoration(labelText: 'Invitation text'),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                if (input.text.trim().isNotEmpty) {
                  Navigator.pop(context, input.text.trim());
                }
              },
              child: const Text('Continue pairing'),
            ),
          ),
        ],
      ),
    ),
  );
}
