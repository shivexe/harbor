import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ui.dart';

final unlocked = ValueNotifier(false);
VoidCallback? onInteraction;
void noteInteraction() => onInteraction?.call();
final navigatorKey = GlobalKey<NavigatorState>();

class SecurityGate extends StatefulWidget {
  const SecurityGate({required this.child, super.key});
  final Widget child;
  @override
  State<SecurityGate> createState() => _SecurityGateState();
}

class _SecurityGateState extends State<SecurityGate>
    with WidgetsBindingObserver {
  Timer? idle;
  bool authenticating = false;
  String? error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    onInteraction = touch;
  }

  void touch() {
    idle?.cancel();
    if (unlocked.value) idle = Timer(const Duration(minutes: 5), lock);
  }

  void lock() {
    idle?.cancel();
    unlocked.value = false;
    navigatorKey.currentState?.popUntil((route) => route.isFirst);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && !authenticating) lock();
  }

  Future<void> unlock() async {
    if (authenticating) return;
    setState(() {
      authenticating = true;
      error = null;
    });
    try {
      final accepted = await const MethodChannel(
        'harbor/security',
      ).invokeMethod<bool>('unlock');
      if (accepted == true && mounted) {
        unlocked.value = true;
        touch();
      } else if (mounted) {
        setState(
          () => error =
              'Unlock cancelled. Use your device screen lock to open Harbor.',
        );
      }
    } on PlatformException catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Set up a device PIN, password or pattern in Android settings to protect Harbor.',
        );
      }
    } finally {
      if (mounted) setState(() => authenticating = false);
    }
  }

  @override
  void dispose() {
    idle?.cancel();
    onInteraction = null;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: unlocked,
    builder: (context, open, _) => open
        ? Listener(
            onPointerDown: (_) => touch(),
            child: Focus(
              onKeyEvent: (_, _) {
                touch();
                return KeyEventResult.ignored;
              },
              child: widget.child,
            ),
          )
        : Material(
            color: canvas,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.terminal, color: action, size: 26),
                        SizedBox(width: 10),
                        Text(
                          'Harbor',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    Expanded(
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                color: panel,
                                border: Border.all(color: hairline),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(
                                Icons.lock_outline,
                                color: action,
                                size: 29,
                              ),
                            ),
                            const SizedBox(height: 28),
                            const Text(
                              'Your workspace is locked.',
                              style: TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -.7,
                                height: 1.15,
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Use your device screen lock to access your hosts and sessions.',
                              style: TextStyle(
                                color: muted,
                                fontSize: 16,
                                height: 1.4,
                              ),
                            ),
                            if (error != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 20),
                                child: Text(
                                  error!,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: authenticating ? null : unlock,
                        icon: const Icon(Icons.lock_open),
                        label: const Text('Unlock Harbor'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
  );
}
