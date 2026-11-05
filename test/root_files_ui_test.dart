import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_control/screens/root_files_screen.dart';
import 'package:remote_control/services/root_files.dart';
import 'package:remote_control/utils/root_file_presentation.dart';
import 'package:remote_control/utils/root_folder_guide.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <(String, String?)>[];
  bool advancedOnly = false;
  Map<String, dynamic>? unlockRequest;
  Map<String, dynamic> entry(String name, {bool folder = false}) => {
    'name': name,
    'path': name == 'folder' ? '/folder' : '/folder/$name',
    'directory': folder,
    'regular': !folder,
    'link': false,
    'size': 1200,
    'uid': 0,
    'gid': 1000,
    'mode': '640',
    'identity': 'test-entry',
  };
  setUp(() {
    calls.clear();
    advancedOnly = false;
    unlockRequest = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(RootFiles.channel, (call) async {
          final args = Map<String, dynamic>.from(
            (call.arguments as Map?) ?? {},
          );
          final path = args['path'] as String?;
          calls.add((call.method, path));
          if (call.method == 'unlock') unlockRequest = args;
          return switch (call.method) {
            'lock' => null,
            'backupFolder' => jsonEncode({'path': '/folder/private-backups'}),
            'unlock' => jsonEncode({
              'scope': path,
              'seconds': 300,
              'advanced': args['advanced'] == true,
            }),
            'list' => jsonEncode({
              'path': path,
              'unlockable': path != '/' && !advancedOnly,
              'advancedUnlockable': path != '/',
              'entries': path == '/'
                  ? [entry('folder', folder: true)]
                  : [
                      entry('notes.txt')..['path'] = '$path/notes.txt',
                      entry('.hidden')..['path'] = '$path/.hidden',
                    ],
            }),
            'read' => jsonEncode({
              ...entry('notes.txt'),
              'text': 'Original text',
              'hash': 'test-hash',
            }),
            'save' => jsonEncode({'backup': '/folder/.backup'}),
            _ => throw StateError('Unexpected operation ${call.method}'),
          };
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(RootFiles.channel, null);
  });
  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const RootFilesScreen(),
                ),
              ),
              child: const Text('Open explorer'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open explorer'));
    await tester.pumpAndSettle();
  }

  Future<void> folder(WidgetTester tester) async {
    await tester.tap(find.text('folder'));
    await tester.pumpAndSettle();
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  test('owner and permission labels are meaningful including special bits', () {
    expect(fileOwnerLabel(0), 'root');
    expect(fileOwnerLabel(1000), 'system');
    expect(fileOwnerLabel(12345), 'UID 12345');
    expect(fileOwnerLabel(12345, group: true), 'GID 12345');
    expect(filePermissionSymbols('755'), 'rwxr-xr-x');
    expect(filePermissionSymbols('4755'), 'rwsr-xr-x');
    expect(filePermissionSymbols('1700'), 'rwx-----T');
    expect(filePermissionDescription('640', 0, directory: false), 'No access');
    expect(fileParentPath('/folder'), '/');
  });
  testWidgets('Back gesture goes up a folder then exits at root', (
    tester,
  ) async {
    await open(tester);
    await folder(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(calls.lastWhere((c) => c.$1 == 'list').$2, '/');
    expect(find.byType(RootFilesScreen), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Open explorer'), findsOneWidget);
    await finish(tester);
  });
  testWidgets('Back clears folder search before navigating', (tester) async {
    await open(tester);
    await folder(tester);
    await tester.enterText(find.byType(TextField), 'missing');
    await tester.pump();
    expect(find.text('No matching files'), findsOneWidget);
    final before = calls.where((c) => c.$1 == 'list').length;
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('notes.txt'), findsOneWidget);
    expect(calls.where((c) => c.$1 == 'list').length, before);
    await finish(tester);
  });
  testWidgets(
    'toolbar Back matches gesture; properties explain numeric metadata',
    (tester) async {
      await open(tester);
      await folder(tester);
      expect(find.text('1.2 KB · Owner: root'), findsOneWidget);
      expect(find.textContaining('0:1000'), findsNothing);
      await tester.tap(find.byTooltip('Actions for notes.txt'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Properties'));
      await tester.pumpAndSettle();
      expect(find.text('root (UID 0)'), findsOneWidget);
      expect(find.text('system (GID 1000)'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(calls.lastWhere((c) => c.$1 == 'list').$2, '/');
      await finish(tester);
    },
  );
  testWidgets('dirty editor Back can cancel or discard without saving', (
    tester,
  ) async {
    await open(tester);
    await folder(tester);
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unlock writes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('notes.txt'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Changed text');
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.text('Changed text'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.byType(RootFilesScreen), findsOneWidget);
    expect(calls.where((c) => c.$1 == 'save'), isEmpty);
    await finish(tester);
  });
  testWidgets('saving returns to the folder without a discard prompt', (
    tester,
  ) async {
    await open(tester);
    await folder(tester);
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unlock writes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('notes.txt'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Saved text');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(calls.where((c) => c.$1 == 'save').length, 1);
    expect(find.text('Discard changes?'), findsNothing);
    expect(find.byType(RootFilesScreen), findsOneWidget);
    expect(find.text('notes.txt'), findsOneWidget);
    await finish(tester);
  });
  testWidgets('backgrounding locks an open editor and keeps unsaved text', (
    tester,
  ) async {
    await open(tester);
    await folder(tester);
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unlock writes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('notes.txt'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Keep me');
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField).last).readOnly,
      isTrue,
    );
    expect(find.text('Keep me'), findsOneWidget);
    expect(find.text('Save'), findsNothing);
    expect(calls.last.$1, 'lock');
    await finish(tester);
  });
  testWidgets('compact phone layout supports larger text without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await open(tester);
    await folder(tester);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });
  test(
    'folder descriptions use specific boundaries and subfolder inheritance',
    () {
      expect(rootFolderDescription('/system/etc'), contains('Core Android'));
      expect(rootFolderDescription('/system_ext/app'), contains('extensions'));
      expect(rootFolderDescription('/data/local/tmp'), contains('Temporary'));
      expect(rootFolderDescription('/systematic'), isNull);
    },
  );
  testWidgets(
    'advanced unlock requires typed exact path and sends scoped request',
    (tester) async {
      advancedOnly = true;
      await open(tester);
      await folder(tester);
      await tester.tap(find.text('Advanced\nunlock'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Unlock folder'),
            )
            .onPressed,
        isNull,
      );
      final confirmation = find.widgetWithText(
        TextField,
        'Type the complete folder path',
      );
      await tester.ensureVisible(confirmation);
      await tester.enterText(confirmation, '/wrong');
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Unlock folder'),
            )
            .onPressed,
        isNull,
      );
      await tester.enterText(confirmation, '/folder');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Unlock folder'));
      await tester.pumpAndSettle();
      expect(unlockRequest?['advanced'], isTrue);
      expect(unlockRequest?['confirmation'], '/folder');
      expect(find.textContaining('Advanced writes'), findsOneWidget);
      await finish(tester);
    },
  );
  testWidgets('folder guide is available without unlocking or writes', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('Guide'));
    await tester.pumpAndSettle();
    expect(find.text('Android folder guide'), findsOneWidget);
    expect(calls.where((c) => c.$1 == 'unlock'), isEmpty);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(RootFilesScreen), findsOneWidget);
    await finish(tester);
  });
  testWidgets('root customization shortcut uses typed scoped unlock', (
    tester,
  ) async {
    advancedOnly = true;
    await open(tester);
    await tester.ensureVisible(find.text('Root customizations'));
    await tester.tap(find.text('Root customizations'));
    await tester.pumpAndSettle();
    expect(calls.lastWhere((c) => c.$1 == 'list').$2, '/data/adb');
    await tester.tap(find.text('Advanced\nunlock'));
    await tester.pumpAndSettle();
    expect(find.textContaining('prevent booting'), findsOneWidget);
    final input = find.widgetWithText(
      TextField,
      'Type the complete folder path',
    );
    await tester.ensureVisible(input);
    await tester.enterText(input, '/data/adb');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Unlock folder'));
    await tester.pumpAndSettle();
    expect(unlockRequest?['path'], '/data/adb');
    expect(unlockRequest?['confirmation'], '/data/adb');
    expect(unlockRequest?['advanced'], isTrue);
    await tester.tap(find.byTooltip('Actions for notes.txt'));
    await tester.pumpAndSettle();
    expect(find.text('Move to trash'), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await finish(tester);
  });
  testWidgets('private root backup shortcut opens without a write grant', (
    tester,
  ) async {
    await open(tester);
    await tester.ensureVisible(find.text('Root edit backups'));
    await tester.tap(find.text('Root edit backups'));
    await tester.pumpAndSettle();
    expect(
      calls.lastWhere((c) => c.$1 == 'list').$2,
      '/folder/private-backups',
    );
    expect(calls.where((c) => c.$1 == 'unlock'), isEmpty);
    await finish(tester);
  });
}
