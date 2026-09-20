import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harbor/main.dart';
import 'package:harbor/screens/pair_screen.dart';
import 'package:harbor/security_gate.dart';
import 'package:harbor/sync.dart';
import 'package:harbor/ui.dart';
import 'package:harbor/vault.dart';

class WaitingService extends SyncService {
  WaitingService({this.name = 'Studio Mac'}) : super(Vault());
  final String name;
  final pending = Completer<void>();
  String? submitted;

  @override
  Future<void> pair(
    String code,
    void Function(String, String) onComparison, {
    bool Function()? cancelled,
  }) async {
    submitted = code;
    onComparison('123456', name);
    await pending.future;
  }
}

class RetryService extends SyncService {
  RetryService() : super(Vault());
  int attempts = 0;

  @override
  Future<void> pair(
    String code,
    void Function(String, String) onComparison, {
    bool Function()? cancelled,
  }) async {
    onComparison('123456', 'Studio Mac');
  }

  @override
  Future<void> sync({bool Function()? cancelled}) async {
    attempts++;
    if (attempts == 1) throw StateError('offline');
  }
}

Future<void> loadFonts() async {
  final configFile = File('.dart_tool/package_config.json').absolute;
  final packages =
      jsonDecode(configFile.readAsStringSync())['packages'] as List;
  final flutterPackage = packages.singleWhere((p) => p['name'] == 'flutter');
  final flutterRoot = Directory.fromUri(
    configFile.uri.resolve(flutterPackage['rootUri']),
  ).parent.parent.path;
  final fonts = FontLoader('Roboto');
  for (final name in ['Regular', 'Medium', 'Bold']) {
    final data = await File(
      '$flutterRoot/bin/cache/artifacts/material_fonts/Roboto-$name.ttf',
    ).readAsBytes();
    fonts.addFont(Future.value(ByteData.view(data.buffer)));
  }
  await fonts.load();
  final mono = FontLoader('monospace');
  final monoData = await File(
    '$flutterRoot/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
  ).readAsBytes();
  mono.addFont(Future.value(ByteData.view(monoData.buffer)));
  await mono.load();
  final icons = FontLoader('MaterialIcons');
  final data = await File(
    '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  ).readAsBytes();
  icons.addFont(Future.value(ByteData.view(data.buffer)));
  await icons.load();
}

Future<void> capture(GlobalKey key, String name, WidgetTester tester) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/screenshots/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void phone(WidgetTester tester, {Size size = const Size(360, 640)}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadFonts);

  testWidgets('onboarding leads straight to QR scanning', (tester) async {
    phone(tester);
    FlutterSecureStorage.setMockInitialValues({});
    unlocked.value = false;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('harbor/security'),
      (_) async => true,
    );
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(key: key, child: const HarborApp()),
    );
    await capture(key, 'android-1.1-locked', tester);
    await tester.tap(find.text('Unlock Harbor'));
    await tester.pumpAndSettle();
    expect(find.text('Scan QR code'), findsOneWidget);
    expect(find.text('Paste invitation instead'), findsNothing);
    await capture(key, 'android-1.1-onboarding', tester);
    await tester.tap(find.text('Scan QR code'));
    await tester.pumpAndSettle();
    expect(find.byType(PairScreen), findsOneWidget);
    expect(find.text('Scan the QR code'), findsOneWidget);
    expect(find.text('Paste invitation instead'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    unlocked.value = false;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('harbor/security'),
      null,
    );
  });

  testWidgets('read-only grouped hosts search without an editor', (
    tester,
  ) async {
    phone(tester, size: const Size(412, 892));
    final hosts = [
      {
        'name': 'Orchard primary',
        'hostname': '10.0.0.12',
        'group': 'Production',
      },
      {
        'name': 'Orchard worker',
        'hostname': '10.0.0.18',
        'group': 'Production',
      },
      {'name': 'Preview server', 'hostname': '10.1.0.4', 'group': 'Staging'},
      {'name': 'Home lab', 'hostname': '192.168.1.20', 'group': 'Personal'},
    ];
    final records = [
      for (var i = 0; i < hosts.length; i++)
        {
          'id': '11111111-1111-4111-8111-${i.toString().padLeft(12, '0')}',
          'port': 22,
          'username': 'harbor',
          'authType': i == 0 ? 'none' : 'password',
          'password': '',
          'privateKey': '',
          'passphrase': '',
          'hostKey': '',
          'notes': '',
          ...hosts[i],
        },
    ];
    FlutterSecureStorage.setMockInitialValues({
      'vault': jsonEncode({
        'pairing': {'desktopName': 'Studio Mac'},
        'snapshot': {
          'hosts': records,
          'syncedAt': DateTime.now().toUtc().toIso8601String(),
        },
      }),
    });
    unlocked.value = true;
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(key: key, child: const HarborApp()),
    );
    await tester.pumpAndSettle();
    expect(find.text('Production'), findsOneWidget);
    expect(find.text('Orchard primary'), findsOneWidget);
    expect(find.textContaining('No password'), findsOneWidget);
    expect(find.byIcon(Icons.edit), findsNothing);
    expect(tester.takeException(), isNull);
    await capture(key, 'android-1.1-hosts', tester);
    await tester.enterText(find.byType(TextField), 'worker');
    await tester.pumpAndSettle();
    expect(find.text('Orchard primary'), findsNothing);
    expect(find.text('Orchard worker'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    unlocked.value = false;
  });

  testWidgets('paste fallback keeps approval code in pairing flow', (
    tester,
  ) async {
    phone(tester);
    unlocked.value = true;
    final service = WaitingService();
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: harborTheme(),
          home: PairScreen(
            service: service,
            scannerBuilder: (_) => const Center(child: Text('Camera preview')),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Scan the QR code'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await capture(key, 'android-1.1-pairing', tester);
    await tester.tap(find.text('Paste invitation instead'));
    await tester.pumpAndSettle();
    expect(find.text('Invitation text'), findsOneWidget);
    await capture(key, 'android-1.1-paste-fallback', tester);
    await tester.enterText(find.byType(TextField), 'sample invitation');
    await tester.tap(find.text('Continue pairing'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Paste an invitation'), findsNothing);
    expect(service.submitted, 'sample invitation');
    expect(find.text('Approve on your desktop.'), findsOneWidget);
    expect(find.text('123456'), findsOneWidget);
    await capture(key, 'android-1.1-comparison', tester);
    await tester.pumpWidget(const SizedBox());
    service.pending.complete();
    unlocked.value = false;
  });

  testWidgets('paired desktop can retry failed first sync without rescanning', (
    tester,
  ) async {
    phone(tester);
    unlocked.value = true;
    final service = RetryService();
    bool committed = false;
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: harborTheme(),
        home: PairScreen(
          service: service,
          onPaired: () => committed = true,
          scannerBuilder: (accept) => Center(
            child: FilledButton(
              onPressed: () => accept('one-time invitation'),
              child: const Text('Scan test code'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Scan test code'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Paired. Sync needed.'), findsOneWidget);
    expect(committed, isTrue);
    expect(find.text('Retry sync'), findsOneWidget);
    expect(service.attempts, 1);
    await tester.tap(find.text('Retry sync'));
    await tester.pump();
    expect(service.attempts, 2);
    await tester.pumpWidget(const SizedBox());
    unlocked.value = false;
  });

  testWidgets('approval stays scrollable on a compact phone', (tester) async {
    phone(tester, size: const Size(320, 568));
    unlocked.value = true;
    final service = WaitingService(
      name: 'A very long desktop name used for pairing approval',
    );
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: harborTheme(),
        home: PairScreen(
          service: service,
          scannerBuilder: (accept) => Center(
            child: FilledButton(
              onPressed: () => accept('one-time invitation'),
              child: const Text('Scan test code'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Scan test code'));
    await tester.pump();
    expect(find.text('123456'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Cancel pairing'));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    service.pending.complete();
    unlocked.value = false;
  });
}
