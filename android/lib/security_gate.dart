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
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Harbor',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 44),
                            const Text(
                              'Harbor is locked',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Use your device screen lock to open your hosts.',
                              style: TextStyle(
                                color: muted,
                                fontSize: 16,
                                height: 1.35,
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
                      child: FilledButton(
                        onPressed: authenticating ? null : unlock,
                        child: const Text('Unlock Harbor'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
  );
}
