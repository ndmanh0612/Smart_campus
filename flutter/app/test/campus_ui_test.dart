import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smartcard_week1/core/campus_api.dart';
import 'package:smartcard_week1/features/student.dart';
import 'package:smartcard_week1/main.dart';

http.Response response(Object? value, {int status = 200}) => http.Response(
  jsonEncode(status < 400 ? {'data': value} : {'error': value}),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
void main() {
  testWidgets(
    'mobile login shows Vietnamese labels and no camera permission flow',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = CampusApi(
        client: MockClient((_) async => response({})),
        origin: 'http://campus.test',
        enableRealtime: false,
      );
      await tester.pumpWidget(CampusApp(api: api));
      expect(find.text('Đăng nhập'), findsOneWidget);
      expect(find.text('RFID THẬT'), findsOneWidget);
      expect(find.text('Mở camera'), findsNothing);
      await tester.tap(find.text('Đăng nhập'));
      await tester.pumpAndSettle();
      expect(find.text('Nhập email hợp lệ'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      api.dispose();
    },
  );
  testWidgets(
    'wallet displays backend balances and sends student PIN approval bound to version',
    (tester) async {
      Map<String, dynamic>? approval;
      final api = CampusApi(
        origin: 'http://campus.test',
        enableRealtime: false,
        client: MockClient((request) async {
          final path = request.url.path;
          if (path.endsWith('/approvals')) {
            approval = Map<String, dynamic>.from(jsonDecode(request.body));
            return response({'approvalId': 'approval-1'});
          }
          if (path.endsWith('/wallet')) {
            return response({
              'postedPoints': '12000',
              'heldPoints': '2000',
              'availablePoints': '10000',
            });
          }
          if (path.endsWith('/payment-requests')) {
            return response([
              {
                'id': 'payment-1',
                'amountPoints': '3000',
                'parkingSessionId': 'session-1',
                'sourceVersion': 7,
                'status': 'AWAITING_CONFIRMATION',
              },
            ]);
          }
          return response([]);
        }),
      );
      api.accessToken = 'test-token';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: WalletPage(api))),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('10.000 point'), findsOneWidget);
      expect(find.text('2.000 point'), findsOneWidget);
      await tester.tap(find.text('Xác nhận'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.enterText(find.byType(TextFormField), '193827');
      await tester.tap(find.widgetWithText(FilledButton, 'Xác nhận').last);
      await tester.pumpAndSettle();
      expect(approval, {'pin': '193827', 'expectedSourceVersion': 7});
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      api.dispose();
    },
  );
  test('network retry keeps a mutation idempotency key', () async {
    final keys = <String?>[];
    var calls = 0;
    final api = CampusApi(
      origin: 'http://campus.test',
      enableRealtime: false,
      client: MockClient((request) async {
        keys.add(request.headers['Idempotency-Key']);
        if (calls++ == 0) throw http.ClientException('offline');
        return response({'id': 'topup-1'});
      }),
    );
    await api.request(
      '/me/topups',
      method: 'POST',
      body: {'requestedVnd': '1000'},
    );
    expect(keys.length, 2);
    expect(keys.first, isNotNull);
    expect(keys.first, keys.last);
    api.dispose();
  });
}
