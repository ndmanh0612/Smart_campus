import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartcard_week1/main.dart';

void main() {
  testWidgets('camera waits for explicit user action', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: CameraSpike()));
    expect(find.text('Mở camera'), findsOneWidget);
    expect(find.text('Chụp'), findsOneWidget);
    expect(find.textContaining('Chỉ chụp người đã đồng ý'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
