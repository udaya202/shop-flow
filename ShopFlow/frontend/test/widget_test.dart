import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/main.dart';

void main() {
  testWidgets('ShopFlow login page loads', (WidgetTester tester) async {
    await tester.pumpWidget(const ShopFlowApp());

    expect(find.text('ShopFlow'), findsOneWidget);
    expect(find.text('Manage your business smarter.'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);
    expect(find.text('Email Address'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
  });
}
