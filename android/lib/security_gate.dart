import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
            color: const Color(0xff0b1424),
            child: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.sailing_outlined,
                        size: 64,
                        color: Color(0xff91afff),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Harbor is locked',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Your device screen lock protects your hosts.',
                        textAlign: TextAlign.center,
                      ),
                      if (error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Text(error!, textAlign: TextAlign.center),
                        ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: authenticating ? null : unlock,
                        icon: const Icon(Icons.lock_open),
                        label: const Text('Unlock Harbor'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
  );
}
