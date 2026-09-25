import 'package:flutter_test/flutter_test.dart';
import 'package:bavaria_ia/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const BavariaIAApp());
  });
}
