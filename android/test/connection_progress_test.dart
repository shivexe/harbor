import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harbor/models.dart';
import 'package:harbor/screens/terminal_screen.dart';
import 'package:harbor/security_gate.dart';
import 'package:harbor/ssh_client.dart';
import 'package:harbor/ssh_session.dart';
import 'package:harbor/ui.dart';
import 'package:xterm/xterm.dart';

Host fixtureHost() => Host.fromJson({
  'id': '9dd05513-bce7-495c-bd92-23cd19e6fd91',
  'name': 'Lab server',
  'hostname': '127.0.0.1',
  'port': 22,
  'username': 'harbor',
  'group': 'Lab',
  'authType': 'none',
  'password': '',
  'privateKey': '',
  'passphrase': '',
  'hostKey': '',
  'notes': '',
});

Widget screen(Connection connection, {double textScale = 1}) => MaterialApp(
  theme: harborTheme(),
  debugShowCheckedModeBanner: false,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: TerminalScreen(
    connection: connection,
    onClose: (_) {},
    onReplace: (_, _) {},
  ),
);

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadFonts);
  testWidgets('terminal waits for shell and shows real SSH stages', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final connection = Connection(fixtureHost())..started = true;
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(key: key, child: screen(connection, textScale: 1.35)),
    );
    for (final stage in [
      ConnectionStage.openingSocket,
      ConnectionStage.verifyingHost,
      ConnectionStage.authenticating,
      ConnectionStage.openingShell,
    ]) {
      connection.advance(stage);
      await tester.pump();
      expect(find.byType(TerminalView), findsNothing);
      expect(find.text('Reach server'), findsOneWidget);
      expect(find.text('Verify host key'), findsOneWidget);
      expect(find.text('Authenticate'), findsOneWidget);
      expect(find.text('Open shell'), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (stage == ConnectionStage.authenticating &&
          Platform.environment['HARBOR_CAPTURE_PROGRESS'] == '1') {
        await capture(key, 'android-1.1.2-progress', tester);
      }
    }
    connection.advance(ConnectionStage.connected);
    await tester.pump();
    expect(find.byType(TerminalView), findsOneWidget);
    connection.advance(ConnectionStage.authenticating);
    await tester.pump();
    expect(find.byType(TerminalView), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    connection.dispose();
  });

  testWidgets('failure keeps desktop recovery and a selectable server message', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final connection = Connection(fixtureHost())..started = true;
    final key = GlobalKey();
    connection.advance(ConnectionStage.authenticating);
    connection.receiveServerMessage(
      'Sign in at https://login.example.test/check\n\x1b[31mConnected\x1b[0m\x1b]8;;https://evil.test\x07',
    );
    expect(connection.stage, ConnectionStage.authenticating);
    expect(connection.serverMessage, isNot(contains('\x1b')));
    expect(connection.serverMessage, isNot(contains('[31m')));
    expect(connection.serverMessage, isNot(contains('evil.test')));
    await tester.pumpWidget(
      RepaintBoundary(key: key, child: screen(connection)),
    );
    await tester.pump();
    expect(find.byType(TerminalView), findsNothing);
    expect(find.byType(SelectableText), findsOneWidget);
    if (Platform.environment['HARBOR_CAPTURE_PROGRESS'] == '1') {
      await capture(key, 'android-1.1.2-server-message', tester);
    }
    connection.failedAt = ConnectionStage.authenticating;
    connection.problem = 'Authentication failed.';
    connection.advance(ConnectionStage.failed);
    await tester.pump();
    expect(find.byType(TerminalView), findsNothing);
    expect(find.byType(SelectableText), findsOneWidget);
    expect(
      find.textContaining('https://login.example.test/check'),
      findsOneWidget,
    );
    expect(find.text('Retry connection'), findsOneWidget);
    if (Platform.environment['HARBOR_CAPTURE_PROGRESS'] == '1') {
      await capture(key, 'android-1.1.2-failure', tester);
    }
    await tester.ensureVisible(find.text('Edit on desktop'));
    await tester.tap(find.text('Edit on desktop'));
    await tester.pumpAndSettle();
    expect(find.text('Sync and retry'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    connection.dispose();
  });

  testWidgets('retry reads the latest saved desktop host', (tester) async {
    unlocked.value = true;
    addTearDown(() => unlocked.value = false);
    final record = {
      'id': fixtureHost().id,
      'name': 'Updated server',
      'hostname': '10.0.0.42',
      'port': 2222,
      'username': 'new-user',
      'group': 'Lab',
      'authType': 'none',
      'password': '',
      'privateKey': '',
      'passphrase': '',
      'hostKey': '',
      'notes': '',
    };
    FlutterSecureStorage.setMockInitialValues({
      'vault': jsonEncode({
        'pairing': {'desktopName': 'Lab'},
        'snapshot': {
          'hosts': [record],
        },
      }),
    });
    final old = Connection(fixtureHost())..started = true;
    old.failedAt = ConnectionStage.openingSocket;
    old.problem = 'Unreachable';
    old.advance(ConnectionStage.failed);
    Host? replacement;
    await tester.pumpWidget(
      MaterialApp(
        theme: harborTheme(),
        home: TerminalScreen(
          connection: old,
          onClose: (_) {},
          onReplace: (_, fresh) {
            replacement = fresh.host;
            throw StateError('Test stopped before network access');
          },
        ),
      ),
    );
    await tester.tap(find.text('Retry connection'));
    await tester.pumpAndSettle();
    expect(replacement?.address, '10.0.0.42');
    expect(replacement?.port, 2222);
    expect(replacement?.username, 'new-user');
    await tester.pumpWidget(const SizedBox());
    old.dispose();
  });

  test('missing desktop pin fails before any socket milestone', () async {
    final connection = Connection(fixtureHost());
    await connection.connect();
    expect(connection.stage, ConnectionStage.failed);
    expect(connection.failedAt, isNull);
    expect(connection.problem, contains('Verify this server key'));
    connection.dispose();
  });

  test(
    'live fixture reaches shell only after pin and authentication',
    () async {
      final path = Platform.environment['HARBOR_SSH_FIXTURE'];
      if (path == null) return;
      final host = Host.fromJson(
        Map<String, dynamic>.from(jsonDecode(await File(path).readAsString())),
      );
      final connection = Connection(host);
      final seen = <ConnectionStage>[];
      ConnectionStage? bannerStage;
      connection.addListener(() {
        if (seen.isEmpty || seen.last != connection.stage) {
          seen.add(connection.stage);
        }
        if (connection.serverMessage.isNotEmpty && bannerStage == null) {
          bannerStage = connection.stage;
        }
      });
      final connected = connection.connect();
      final deadline = DateTime.now().add(const Duration(seconds: 20));
      while (connection.stage != ConnectionStage.connected &&
          connection.stage != ConnectionStage.failed &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(connection.stage, ConnectionStage.connected);
      expect(seen.take(5), [
        ConnectionStage.openingSocket,
        ConnectionStage.verifyingHost,
        ConnectionStage.authenticating,
        ConnectionStage.openingShell,
        ConnectionStage.connected,
      ]);
      if (Platform.environment['HARBOR_EXPECT_BANNER'] == '1') {
        expect(bannerStage, ConnectionStage.authenticating);
        expect(
          connection.serverMessage,
          contains('https://login.tailscale.com/a/harbor-fixture'),
        );
        expect(connection.serverMessage.length, lessThanOrEqualTo(2048));
      }
      connection.send('exit\n');
      await connected.timeout(const Duration(seconds: 5));
      expect(connection.stage, ConnectionStage.disconnected);
      connection.dispose();
    },
  );
}
