import 'package:flutter_test/flutter_test.dart';

import 'package:coffee_lab_app/main.dart';

void main() {
  testWidgets('起動画面に2つのモードが出る', (tester) async {
    await tester.pumpWidget(const CoffeeLabApp());
    expect(find.text('撮影'), findsOneWidget);
    expect(find.text('ライト'), findsOneWidget);
  });
}
