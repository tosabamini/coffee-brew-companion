import 'package:flutter_test/flutter_test.dart';
import 'package:fcoffee_scale_app01/main.dart';

void main() {
  testWidgets('app builds', (WidgetTester tester) async {
    await tester.pumpWidget(const CoffeeScaleApp());
    expect(find.text('Coffee Scale'), findsOneWidget);
  });
}