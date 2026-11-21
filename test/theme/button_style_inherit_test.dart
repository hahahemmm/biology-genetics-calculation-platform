import 'package:biology/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('按钮主题显式使用非继承文字样式', () {
    for (final theme in [AppTheme.light(), AppTheme.dark()]) {
      final styles = <ButtonStyle?>[
        theme.filledButtonTheme.style,
        theme.outlinedButtonTheme.style,
      ];
      for (final style in styles) {
        final textStyle = style?.textStyle?.resolve(const <WidgetState>{});
        expect(textStyle, isNotNull);
        expect(textStyle!.inherit, isFalse);
      }
    }
  });

  testWidgets('四类按钮首帧与主题切换不发生插值异常', (tester) async {
    for (final theme in [AppTheme.light(), AppTheme.dark()]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Column(
              children: [
                FilledButton(onPressed: () {}, child: const Text('保存')),
                OutlinedButton(onPressed: () {}, child: const Text('测试')),
                TextButton(onPressed: () {}, child: const Text('继续')),
                SegmentedButton<bool>(
                  selected: const {false},
                  onSelectionChanged: (_) {},
                  segments: const [
                    ButtonSegment(value: false, label: Text('标准')),
                    ButtonSegment(value: true, label: Text('课堂')),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });
}
