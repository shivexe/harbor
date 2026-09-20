import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harbor/main.dart';
import 'package:harbor/security_gate.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'device authentication gates hosts and backgrounding locks again',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      unlocked.value = false;
      bool accepted = true;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('harbor/security'),
        (_) async => accepted,
      );
      await tester.pumpWidget(const HarborApp());
      expect(find.text('Harbor is locked'), findsOneWidget);
      expect(find.text('Scan QR code'), findsNothing);
      await tester.tap(find.text('Unlock Harbor'));
      await tester.pumpAndSettle();
      expect(find.text('Scan QR code'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Harbor is locked'), findsOneWidget);
      accepted = false;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.tap(find.text('Unlock Harbor'));
      await tester.pumpAndSettle();
      expect(find.text('Scan QR code'), findsNothing);
      expect(find.textContaining('Unlock cancelled'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('harbor/security'),
        null,
      );
    },
  );
}
