import 'package:flutter_test/flutter_test.dart';
import 'package:inappify_sdk_example/main.dart';

void main() {
  testWidgets('example starts without making an SDK request', (tester) async {
    await tester.pumpWidget(const InappifyExampleApp());
    expect(find.text('Configure'), findsOneWidget);
    expect(find.text('Load current offering'), findsOneWidget);
    await tester.tap(find.text('Configure'));
    await tester.pumpAndSettle();
    expect(find.text('Set INAPPIFY_PUBLIC_APP_KEY first.'), findsOneWidget);
  });
}
