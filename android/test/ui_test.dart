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

void main() {
  testWidgets('read-only host list renders groups and search on phone', (
    tester,
  ) async {
    final configFile = File('.dart_tool/package_config.json').absolute;
    final packages =
        jsonDecode(configFile.readAsStringSync())['packages'] as List;
    final flutterPackage = packages.singleWhere((p) => p['name'] == 'flutter');
    final flutterRoot = Directory.fromUri(
      configFile.uri.resolve(flutterPackage['rootUri']),
    ).parent.parent.path;
    await tester.runAsync(() async {
      final fonts = FontLoader('Roboto');
      for (final name in ['Regular', 'Medium', 'Bold']) {
        final data = await File(
          '$flutterRoot/bin/cache/artifacts/material_fonts/Roboto-$name.ttf',
        ).readAsBytes();
        fonts.addFont(Future.value(ByteData.view(data.buffer)));
      }
      await fonts.load();
      final icons = FontLoader('MaterialIcons');
      final data = await File(
        '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ).readAsBytes();
      icons.addFont(Future.value(ByteData.view(data.buffer)));
      await icons.load();
    });
    tester.view.physicalSize = const Size(412, 892);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
          'authType': 'password',
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
        'snapshot': {'hosts': records, 'syncedAt': '2026-09-18T19:00:00Z'},
      }),
    });
    unlocked.value = false;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('harbor/security'),
      (_) async => true,
    );
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(key: boundaryKey, child: const HarborApp()),
    );
    await tester.tap(find.text('Unlock Harbor'));
    await tester.pumpAndSettle();
    expect(find.text('Production'), findsOneWidget);
    expect(find.text('Orchard primary'), findsOneWidget);
    expect(find.byIcon(Icons.edit), findsNothing);
    expect(tester.takeException(), isNull);
    Future<void> capture(String name) async {
      final boundary =
          boundaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('build/screenshots/$name.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    await capture('hosts');
    await tester.enterText(find.byType(TextField), 'worker');
    await tester.pumpAndSettle();
    expect(find.text('Orchard primary'), findsNothing);
    expect(find.text('Orchard worker'), findsOneWidget);
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const PairScreen()),
    );
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(360, 640);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await capture('pair');
    await tester.pumpWidget(const SizedBox());
    unlocked.value = false;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('harbor/security'),
      null,
    );
  });
}
