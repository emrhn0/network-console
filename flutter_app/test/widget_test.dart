import 'package:flutter_test/flutter_test.dart';
import 'package:network_console_app/main.dart';

void main() {
  testWidgets('App builds without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const NetworkConsoleApp());
    await tester.pump();
  });
}
