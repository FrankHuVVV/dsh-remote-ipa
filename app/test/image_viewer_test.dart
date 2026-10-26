import 'dart:convert';

import 'package:dsh_companion_ios/l10n/strings.dart';
import 'package:dsh_companion_ios/ui/image_viewer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// 1×1 PNG：足够让 Image.memory 正常解码，又不拖慢 widget 测试。
const String _tinyPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

void main() {
  testWidgets('全屏图片页有关闭按钮与保存按钮，且关闭能返回', (WidgetTester tester) async {
    var saved = false;
    var exported = false;
    final strings = Strings.of('zh-CN');

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (BuildContext context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (BuildContext context) => ImageViewerPage(
                    name: 'shot.png',
                    bytes: base64Decode(_tinyPng),
                    strings: strings,
                    onSaveToAlbum: (String name, List<int> bytes) async => saved = true,
                    onExportImage: (String name, List<int> bytes) async => exported = true,
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.close), findsOneWidget);
    expect(find.text(strings.get('save_to_album')), findsOneWidget);
    expect(find.text(strings.get('save_to_files')), findsOneWidget);

    await tester.tap(find.text(strings.get('save_to_album')));
    await tester.pump();
    expect(saved, isTrue);

    await tester.tap(find.text(strings.get('save_to_files')));
    await tester.pump();
    expect(exported, isTrue);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
  });
}
