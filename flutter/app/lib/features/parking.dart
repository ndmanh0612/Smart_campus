import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;
import '../core/campus_api.dart';
import 'shared.dart';

class ParkingPage extends StatefulWidget {
  final CampusApi api;
  const ParkingPage(this.api, {super.key});
  @override
  State<ParkingPage> createState() => _ParkingPageState();
}

class _ParkingPageState extends State<ParkingPage> {
  String? contextId, identityId, sessionId;
  int? version;
  String purpose = 'PARKING_ENTRY', plate = '';
  bool useFace = false;
  bool isProcessing = false;
  Timer? _parkingRfidPollTimer;
  DateTime? _parkingWaitingStartedAt;
  String? _lastParkingTappedAt;

  CampusApi get api => widget.api;

  @override
  void dispose() {
    _parkingRfidPollTimer?.cancel();
    super.dispose();
  }

  void _startParkingRfidPolling() {
    _parkingRfidPollTimer?.cancel();
    _parkingRfidPollTimer = Timer.periodic(const Duration(milliseconds: 180), (t) async {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (contextId == null || identityId != null) {
        t.cancel();
        return;
      }

      try {
        final ev = await api.request('/simulator/events') as Map?;
        if (ev != null && ev['identities'] is List) {
          final ids = rows(ev['identities'])
              .where((i) => i['contextId'] == contextId && i['consumedAt'] == null)
              .toList();
          if (ids.isNotEmpty && mounted && identityId == null) {
            setState(() {
              identityId = ids.first['id'] as String?;
            });
            api.changed();
            t.cancel();
            return;
          }
        }

        if (!useFace) {
          final res = await api.request('/admin/latest-tapped-card');
          if (res is Map && res['uid'] != null) {
            final tappedAtStr = res['tappedAt'] as String?;
            if (tappedAtStr != null && tappedAtStr != _lastParkingTappedAt) {
              final tappedAt = DateTime.tryParse(tappedAtStr);
              if (tappedAt != null &&
                  _parkingWaitingStartedAt != null &&
                  !tappedAt.isBefore(_parkingWaitingStartedAt!.subtract(const Duration(seconds: 1))) &&
                  DateTime.now().difference(tappedAt).inSeconds <= 20) {
                _lastParkingTappedAt = tappedAtStr;
                api.changed();
              }
            }
          }
        }
      } catch (_) {}
    });
  }

  Future<void> prepare(
    List<RowData> terminals,
    List<RowData> sessions,
    List<RowData> lots,
    bool exit,
  ) async {
    final face = useFace;
    final role = exit ? 'PARKING_EXIT' : 'PARKING_ENTRY';
    final canConfigure = api.roles.contains('ADMIN');
    final candidates = terminals
        .where(
          (r) =>
              r['active'] == true &&
              (r['role'] == role || (!face && canConfigure)) &&
              (face ? r['kind'] != 'RFID_READER' : r['kind'] == 'RFID_READER'),
        )
        .toList();
    final active = sessions.where((s) => s['status'] == 'ACTIVE').toList();
    final form = await formDialog(
      context,
      exit ? 'Chuẩn bị lấy xe ra' : 'Chuẩn bị lượt xe vào bãi',
      [
        FormFieldSpec(
          'deviceId',
          face ? 'Camera AI (SFace AI)' : 'Đầu đọc thẻ RFID (MFRC522)',
          options: options(candidates, 'name'),
        ),
        if (exit)
          FormFieldSpec(
            'sessionId',
            'Lượt xe đang gửi',
            options: {
              for (final s in active)
                s['id'].toString(): '${s['entryPlate']} • ${s['studentCode']}',
            },
          )
        else
          FormFieldSpec('lotId', 'Bãi xe', options: options(lots, 'name')),
      ],
    );
    if (form == null) return;
    final device = candidates.firstWhere((r) => r['id'] == form['deviceId']);
    if (!face && device['role'] != role) {
      await api.request(
        '/admin/devices/${device['id']}/role',
        method: 'PUT',
        body: {
          'role': role,
          'expectedVersion': device['configVersion'],
          'reason': 'Chuyển đầu đọc RFID sang lượt gửi hoặc lấy xe',
        },
      );
    }
    if (!face) {
      for (var attempt = 0; attempt < 6; attempt++) {
        final status = await api.request('/simulator/status') as Map;
        final current = rows(
          status['devices'],
        ).firstWhere((r) => r['id'] == device['id']);
        if (current['role'] == role &&
            current['ackVersion'] == current['configVersion']) {
          break;
        }
        if (attempt == 5) {
          throw CampusFailure(
            'DEVICE_NOT_READY',
            'Đầu đọc RFID chưa xác nhận cấu hình. Kiểm tra kết nối USB.',
            409,
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }
    RowData result;
    if (exit) {
      final selected = active.firstWhere((s) => s['id'] == form['sessionId']);
      version = selected['version'] as int;
      sessionId = selected['id'] as String;
      result = Map<String, dynamic>.from(
        await api.request(
          '/parking/sessions/$sessionId/exit-contexts',
          method: 'POST',
          body: {'deviceId': form['deviceId'], 'expectedVersion': version},
        ),
      );
    } else {
      result = Map<String, dynamic>.from(
        await api.request(
          '/parking/entry-contexts',
          method: 'POST',
          body: form,
        ),
      );
      sessionId = null;
    }
    if (!mounted) return;
    setState(() {
      purpose = exit ? 'PARKING_EXIT' : 'PARKING_ENTRY';
      contextId = result['id'] as String;
      identityId = null;
      plate = exit
          ? (active.firstWhere((s) => s['id'] == form['sessionId'])['entryPlate']?.toString() ?? '')
          : '';
      _parkingWaitingStartedAt = DateTime.now();
      _lastParkingTappedAt = DateTime.now().toIso8601String();
    });
    _startParkingRfidPolling();
    api.changed();
  }

  @override
  Widget build(BuildContext context) {
    final paths = [
      '/parking/lots',
      '/parking/sessions',
      '/parking/gate-commands',
      '/simulator/status',
      '/simulator/students',
      '/simulator/events',
      if (sessionId != null) '/parking/sessions/$sessionId',
    ];
    return DataPanel(
      key: ValueKey(sessionId),
      api: api,
      paths: paths,
      builder: (context, data) {
        final sessions = rows(data['/parking/sessions']),
            gates = rows(data['/parking/gate-commands']);
        final terminals = rows((data['/simulator/status'] as Map)['devices']);
        final identities =
            rows((data['/simulator/events'] as Map)['identities'])
                .where(
                  (i) => i['contextId'] == contextId && i['consumedAt'] == null,
                )
                .toList();
        final actualIdentity =
            identityId ??
            (identities.isEmpty ? null : identities.first['id'] as String);
        final matchingIdentity = identities.firstWhere(
          (i) => i['id'] == actualIdentity,
          orElse: () => <String, dynamic>{},
        );
        final activeSessions = sessions
            .where((s) => ['ACTIVE', 'PENDING_ENTRY', 'EXIT_PENDING', 'EXCEPTION'].contains(s['status']))
            .toList();
        final studentCode = matchingIdentity['studentCode']?.toString();
        final existingActiveSession = (studentCode != null && studentCode.isNotEmpty)
            ? activeSessions.cast<Map<String, dynamic>?>().firstWhere(
                (s) => s?['studentCode'] == studentCode,
                orElse: () => null,
              )
            : null;
        final hasVehicleAlreadyInLot = purpose == 'PARKING_ENTRY' && existingActiveSession != null;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionTitle(
              'Điều hành bãi xe',
              'Quẹt thẻ RFID thật hoặc Quét khuôn mặt AI (SFace) → Tự động trừ ví khi xe ra → Barie mở tự động.',
            ),
            const ModeLabels(),
            const SizedBox(height: 20),
            Surface(
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  if (contextId == null)
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(
                          value: false,
                          icon: Icon(Icons.contactless),
                          label: Text('Thẻ RFID (MFRC522)'),
                        ),
                        ButtonSegment(
                          value: true,
                          icon: Icon(Icons.face),
                          label: Text('Khuôn mặt (SFace AI)'),
                        ),
                      ],
                      selected: {useFace},
                      onSelectionChanged: (values) =>
                          setState(() => useFace = values.single),
                    ),
                  ActionButton(
                    'Chuẩn bị xe vào',
                    () => prepare(
                      terminals,
                      sessions,
                      rows(data['/parking/lots']),
                      false,
                    ),
                    icon: Icons.login,
                  ),
                  ActionButton(
                    'Chuẩn bị xe ra',
                    () => prepare(
                      terminals,
                      sessions,
                      rows(data['/parking/lots']),
                      true,
                    ),
                    icon: Icons.logout,
                    outlined: true,
                  ),
                ],
              ),
            ),
            if (contextId != null)
              Surface(
                title: purpose == 'PARKING_ENTRY'
                    ? 'Lượt vào bãi đang xử lý'
                    : 'Lượt ra bãi đang xử lý',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      actualIdentity == null
                          ? 'Đang chờ nhận diện: Quẹt thẻ sinh viên RFID lên đầu đọc MFRC522 hoặc bấm "Quét khuôn mặt SFace AI" bên dưới.'
                          : 'Đã nhận diện thành công sinh viên. Xác nhận biển số xe và tiến hành xử lý.',
                    ),
                    if (actualIdentity != null && matchingIdentity.isNotEmpty && hasVehicleAlreadyInLot)
                      Container(
                        margin: const EdgeInsets.only(top: 12, bottom: 8),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: const Color(0xFFF87171),
                            width: 1.5,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.block, color: Color(0xFFDC2626), size: 24),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '⛔ CẢNH BÁO ANTI-PASSBACK: XE ĐANG TRONG BÃI!',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: Color(0xFF991B1B),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Sinh viên "${matchingIdentity['studentName']}" (${matchingIdentity['studentCode']}) hiện đang có một xe đang gửi trong bãi (Biển số: ${existingActiveSession['entryPlate'] ?? "Đang gửi"}, trạng thái: ${existingActiveSession['status']}).\n\n'
                              'Hệ thống không cho phép dùng thẻ hoặc khuôn mặt này để gửi thêm xe khác!',
                              style: const TextStyle(fontSize: 12.5, color: Color(0xFF7F1D1D), height: 1.4),
                            ),
                          ],
                        ),
                      )
                    else if (actualIdentity != null && matchingIdentity.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: 12, bottom: 8),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0FDF4),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: const Color(0xFF86EFAC),
                            width: 1.5,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  matchingIdentity['source'] == 'REAL'
                                      ? Icons.contactless
                                      : Icons.face,
                                  color: const Color(0xFF15803D),
                                  size: 24,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    matchingIdentity['source'] == 'REAL'
                                        ? '🟢 ĐÃ NHẬN DIỆN THẺ RFID THẬT (MFRC522)'
                                        : '🟢 ĐÃ NHẬN DIỆN KHUÔN MẶT (SFACE AI)',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: Color(0xFF166534),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const Divider(
                              height: 16,
                              thickness: 1,
                              color: Color(0xFFBBF7D0),
                            ),
                            Wrap(
                              spacing: 20,
                              runSpacing: 8,
                              children: [
                                _infoPill(
                                  'Họ tên',
                                  matchingIdentity['studentName']?.toString() ?? '—',
                                ),
                                _infoPill(
                                  'MSSV',
                                  matchingIdentity['studentCode']?.toString() ?? '—',
                                ),
                                _infoPill(
                                  'Gmail',
                                  matchingIdentity['studentEmail']?.toString() ?? '—',
                                ),
                                _infoPill(
                                  'Mã thẻ',
                                  matchingIdentity['cardMask']?.toString() ?? 'Hợp lệ',
                                ),
                                _infoPill(
                                  'Số dư ví hiện tại',
                                  pointText(matchingIdentity['walletBalance']),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        if (actualIdentity == null)
                          ActionButton(
                            'Quét khuôn mặt AI (SFace)',
                            () async {
                              final res = await showDialog<Map<String, dynamic>?>(
                                context: context,
                                barrierDismissible: false,
                                builder: (ctx) => _LiveParkingFaceIdentifyDialog(
                                  api: api,
                                  contextId: contextId!,
                                ),
                              );
                              if (res != null && res['matched'] == true) {
                                if (mounted) {
                                  setState(() {
                                    identityId = res['identityAssertionId'] as String?;
                                  });
                                }
                                api.changed();
                                if (context.mounted) {
                                  final score = ((res['score'] as num?)?.toDouble() ?? 0.0) * 100;
                                  success(
                                    context,
                                    '🟢 Đã nhận diện thành công: ${res['studentName']} (${res['studentCode']}) • Khớp: ${score.toStringAsFixed(1)}%',
                                  );
                                }
                              } else if (res != null && res['outcome'] == 'VEHICLE_ALREADY_IN_LOT') {
                                if (context.mounted) {
                                  error(
                                    context,
                                    res['message']?.toString() ?? '⛔ Sinh viên này hiện đã có xe đang gửi trong bãi. Không thể gửi thêm xe!',
                                  );
                                }
                              }
                            },
                            icon: Icons.face,
                          ),
                        ActionButton(
                          'Nhập/đối chiếu biển số',
                          () async {
                            final form = await formDialog(
                              context,
                              'Đối chiếu biển số xe',
                              [
                                FormFieldSpec(
                                  'plate',
                                  'Biển số',
                                  initial: plate,
                                ),
                              ],
                            );
                            if (form == null || !mounted) return;
                            setState(() => plate = form['plate']!.trim());
                          },
                          outlined: true,
                          icon: Icons.directions_car_outlined,
                        ),
                        ActionButton('Hủy lượt đang xử lý', () async {
                          await api.request(
                            '/device-contexts/$contextId/cancel',
                            method: 'POST',
                            body: {
                              'reason': 'Nhân viên hủy để chuẩn bị lại lượt xác thực',
                            },
                          );
                          _parkingRfidPollTimer?.cancel();
                          if (mounted) {
                            setState(() {
                              contextId = null;
                              identityId = null;
                              sessionId = null;
                              plate = '';
                              _parkingWaitingStartedAt = null;
                            });
                          }
                          api.changed();
                        }, outlined: true),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Biển số xe: ${plate.isEmpty ? 'Chưa nhập' : plate}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 16),
                    if (purpose == 'PARKING_ENTRY')
                      ActionButton(
                        'Cho xe vào bãi & Mở cổng',
                        actualIdentity == null || plate.isEmpty || isProcessing || hasVehicleAlreadyInLot
                            ? null
                            : () async {
                                setState(() => isProcessing = true);
                                try {
                                  await api.request(
                                    '/parking/entries',
                                    method: 'POST',
                                    body: {
                                      'identityAssertionId': actualIdentity,
                                      'plate': plate,
                                    },
                                  );
                                  _parkingRfidPollTimer?.cancel();
                                  if (mounted) {
                                    setState(() {
                                      contextId = null;
                                      identityId = null;
                                      sessionId = null;
                                      plate = '';
                                      _parkingWaitingStartedAt = null;
                                    });
                                  }
                                  api.changed();
                                  if (context.mounted) {
                                    success(
                                      context,
                                      '🟢 Đã ghi nhận xe vào bãi và mở barie thành công!',
                                    );
                                  }
                                } finally {
                                  if (mounted) setState(() => isProcessing = false);
                                }
                              },
                        icon: Icons.login,
                      )
                    else
                      ActionButton(
                        'Xác nhận xe ra & Tự động trừ ví',
                        actualIdentity == null || plate.isEmpty || isProcessing
                            ? null
                            : () async {
                                setState(() => isProcessing = true);
                                try {
                                  // 1. Lấy báo giá phí gửi xe
                                  final q = await api.request(
                                    '/parking/sessions/$sessionId/exit-quotes',
                                    method: 'POST',
                                    body: {
                                      'identityAssertionId': actualIdentity,
                                      'plate': plate,
                                      'expectedVersion': version,
                                    },
                                  ) as Map;

                                  final feeAmount = q['amountPoints']?.toString() ?? '0';
                                  final quoteId = q['quoteId'] as String;

                                  // 2. Tự động thanh toán trừ thẳng vào ví sinh viên (không yêu cầu PIN)
                                  final auth = await api.request(
                                    '/parking/sessions/$sessionId/exit-authorizations',
                                    method: 'POST',
                                    body: {
                                      'quoteId': quoteId,
                                      'expectedVersion': version,
                                    },
                                  ) as Map;

                                  // 3. Tự động xác nhận xe qua cổng
                                  final commandId = auth['commandId'] as String?;
                                  if (commandId != null) {
                                    try {
                                      await api.request(
                                        '/parking/gate-commands/$commandId/passage-confirmations',
                                        method: 'POST',
                                        body: {
                                          'reason': 'Hệ thống tự động xác nhận xe ra sau khi trừ ví thành công',
                                          'providerEventId': api.requestKey(),
                                        },
                                      );
                                    } catch (_) {}
                                  }

                                  _parkingRfidPollTimer?.cancel();
                                  if (mounted) {
                                    setState(() {
                                      contextId = null;
                                      identityId = null;
                                      sessionId = null;
                                      plate = '';
                                      _parkingWaitingStartedAt = null;
                                    });
                                  }
                                  api.changed();

                                  if (context.mounted) {
                                    showDialog(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        icon: const Icon(
                                          Icons.check_circle,
                                          color: Color(0xff16a34a),
                                          size: 48,
                                        ),
                                        title: const Text(
                                          'CHO XE RA THÀNH CÔNG',
                                          style: TextStyle(
                                            color: Color(0xff16a34a),
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        content: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              'Đã tự động trừ ${pointText(feeAmount)} từ ví sinh viên.',
                                              style: const TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.bold,
                                              ),
                                              textAlign: TextAlign.center,
                                            ),
                                            const SizedBox(height: 8),
                                            const Text(
                                              'Cổng barie đã mở cho xe ra khỏi bãi.',
                                              textAlign: TextAlign.center,
                                            ),
                                          ],
                                        ),
                                        actions: [
                                          FilledButton(
                                            onPressed: () => Navigator.pop(ctx),
                                            child: const Text('Đóng'),
                                          ),
                                        ],
                                      ),
                                    );
                                  }
                                } on CampusFailure catch (e) {
                                  final isInsufficient = e.code == 'INSUFFICIENT_POINTS' ||
                                      e.message.contains('Ví chưa đủ point') ||
                                      e.message.contains('point');
                                  if (context.mounted) {
                                    showDialog(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        icon: const Icon(
                                          Icons.cancel,
                                          color: Color(0xffdc2626),
                                          size: 52,
                                        ),
                                        title: Text(
                                          isInsufficient
                                              ? 'TỪ CHỐI CHO XE RA - VÍ KHÔNG ĐỦ TIỀN'
                                              : 'KHÔNG THỂ CHO XE RA',
                                          style: const TextStyle(
                                            color: Color(0xffdc2626),
                                            fontWeight: FontWeight.bold,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                        content: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              e.message,
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            if (isInsufficient) ...[
                                              const SizedBox(height: 14),
                                              Container(
                                                padding: const EdgeInsets.all(12),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xfffef2f2),
                                                  borderRadius: BorderRadius.circular(8),
                                                  border: Border.all(color: const Color(0xfffecaca)),
                                                ),
                                                child: const Text(
                                                  '⛔ CỔNG BARIE GIỮ ĐÓNG!\nSinh viên không đủ số dư trong ví. Hãy yêu cầu sinh viên mở ứng dụng trên điện thoại để nạp thêm Point vào ví trước khi lấy xe.',
                                                  style: TextStyle(
                                                    color: Color(0xff991b1b),
                                                    fontSize: 13,
                                                    height: 1.4,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                  textAlign: TextAlign.center,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        actions: [
                                          FilledButton(
                                            style: FilledButton.styleFrom(
                                              backgroundColor: const Color(0xffdc2626),
                                            ),
                                            onPressed: () => Navigator.pop(ctx),
                                            child: const Text('Đã hiểu (Cổng giữ đóng)'),
                                          ),
                                        ],
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    error(context, 'Lỗi xử lý xe ra: $e');
                                  }
                                } finally {
                                  if (mounted) setState(() => isProcessing = false);
                                }
                              },
                        icon: Icons.check_circle_outline,
                      ),
                  ],
                ),
              ),
            Surface(
              title: 'Lệnh cổng mô phỏng',
              child: RecordTable(
                data: gates,
                columns: const {
                  'phase': 'Hướng',
                  'status': 'Trạng thái',
                  'createdAt': 'Thời gian',
                },
                actions: (g) => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (['OPENED', 'UNKNOWN'].contains(g['status']))
                      ActionButton('Xe đã qua', () async {
                        await api.request(
                          '/parking/gate-commands/${g['id']}/passage-confirmations',
                          method: 'POST',
                          body: {
                            'reason': 'Nhân viên xác nhận passage mô phỏng',
                            'providerEventId': api.requestKey(),
                          },
                        );
                        api.changed();
                      }, icon: Icons.done),
                    if (['OPENED', 'UNKNOWN'].contains(g['status'])) ...[
                      const SizedBox(width: 8),
                      ActionButton('Xe chưa qua', () async {
                        final current = await api.request(
                          '/parking/sessions/${g['sessionId']}',
                        );
                        if (!context.mounted) return;
                        await submitForm(
                          context,
                          api,
                          'Xác minh xe chưa qua cổng',
                          '/parking/sessions/${g['sessionId']}/exception-resolutions',
                          const [
                            FormFieldSpec('reason', 'Lý do', kind: 'multiline'),
                            FormFieldSpec(
                              'evidenceNote',
                              'Bằng chứng xác minh',
                              kind: 'multiline',
                            ),
                          ],
                          extra: {
                            'resolution': g['phase'] == 'ENTRY'
                                ? 'CANCEL_ENTRY'
                                : 'VEHICLE_STILL_INSIDE',
                            'expectedVersion': current['version'],
                          },
                        );
                      }, outlined: true),
                    ],
                  ],
                ),
              ),
            ),
            Surface(
              title: 'Lịch sử và phiên hiện hành',
              child: RecordTable(
                data: sessions,
                columns: const {
                  'entryPlate': 'Biển số',
                  'studentCode': 'Sinh viên',
                  'status': 'Trạng thái',
                  'entrySource': 'Nguồn',
                  'enteredAt': 'Vào bãi',
                },
                actions: (s) => s['status'] == 'COMPLETED'
                    ? ActionButton(
                        'Đối soát thu phí',
                        () => submitForm(
                          context,
                          api,
                          'Chỉ xác nhận khi đã chứng minh xe chưa ra; hoàn phí cũ và mở chu kỳ mới',
                          '/parking/sessions/${s['id']}/exception-resolutions',
                          const [
                            FormFieldSpec('reason', 'Lý do', kind: 'multiline'),
                            FormFieldSpec(
                              'evidenceNote',
                              'Bằng chứng xe chưa ra',
                              kind: 'multiline',
                            ),
                          ],
                          extra: {
                            'resolution': 'REVERSE_CAPTURE',
                            'expectedVersion': s['version'],
                          },
                        ),
                        outlined: true,
                      )
                    : const Text('—'),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _infoPill(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: Color(0xFF15803D),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            color: Color(0xFF14532D),
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class _LiveParkingFaceIdentifyDialog extends StatefulWidget {
  final CampusApi api;
  final String contextId;
  const _LiveParkingFaceIdentifyDialog({required this.api, required this.contextId});

  @override
  State<_LiveParkingFaceIdentifyDialog> createState() => _LiveParkingFaceIdentifyDialogState();
}

class _LiveParkingFaceIdentifyDialogState extends State<_LiveParkingFaceIdentifyDialog> {
  bool _active = true;
  double _score = 0.0;
  String? _frameBase64;
  String _statusText = 'Đang mở camera bãi xe realtime...';
  String _source = 'ESP32';
  web.HTMLVideoElement? _webcamVideo;
  web.MediaStream? _webcamStream;
  List<double>? _faceBox;
  int _centeredFrames = 0;
  double _aspectRatio = 4 / 3;

  static bool _webcamViewRegistered = false;

  @override
  void initState() {
    super.initState();
    _startLoop();
  }

  @override
  void dispose() {
    _active = false;
    _stopWebcam();
    super.dispose();
  }

  Future<void> _startWebcam() async {
    try {
      final mediaDevices = web.window.navigator.mediaDevices;
      final constraints = web.MediaStreamConstraints(video: true.toJS);
      final stream = await mediaDevices.getUserMedia(constraints).toDart;
      _webcamStream = stream;
      _webcamVideo = web.HTMLVideoElement()
        ..srcObject = stream
        ..autoplay = true
        ..playsInline = true
        ..muted = true
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.objectFit = 'cover'
        ..style.transform = 'scaleX(-1)';

      if (!_webcamViewRegistered) {
        ui_web.platformViewRegistry.registerViewFactory(
          'parking-webcam-video',
          (int viewId) => _webcamVideo!,
        );
        _webcamViewRegistered = true;
      }
      await _webcamVideo!.play().toDart;
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusText = 'Không thể truy cập Webcam máy tính: $e';
        });
      }
    }
  }

  void _stopWebcam() {
    if (_webcamStream != null) {
      final tracks = _webcamStream!.getTracks().toDart;
      for (final t in tracks) {
        t.stop();
      }
      _webcamStream = null;
      _webcamVideo = null;
    }
  }

  String? _grabWebcam({int targetWidth = 480, double quality = 0.65}) {
    if (_webcamVideo == null || _webcamVideo!.videoWidth == 0) return null;
    final vw = _webcamVideo!.videoWidth;
    final vh = _webcamVideo!.videoHeight;
    final targetHeight = (vh * (targetWidth / vw)).round();
    final canvas = web.HTMLCanvasElement()
      ..width = targetWidth
      ..height = targetHeight;
    final ctx = canvas.getContext('2d') as web.CanvasRenderingContext2D;
    ctx.translate(targetWidth, 0);
    ctx.scale(-1, 1);
    ctx.drawImage(_webcamVideo!, 0, 0, targetWidth, targetHeight);
    return canvas.toDataURL('image/jpeg', quality.toJS);
  }

  Future<void> _startLoop() async {
    while (mounted && _active) {
      try {
        String? b64;
        if (_source == 'WEBCAM') {
          b64 = _grabWebcam(targetWidth: 480, quality: 0.65);
          if (b64 == null) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
            continue;
          }
        }

        final det = await widget.api.request(
          '/face/detect',
          method: 'POST',
          body: {
            'useEsp32Camera': _source == 'ESP32',
            if (_source == 'WEBCAM') 'imageBase64': b64,
          },
        );

        if (!mounted || !_active) break;

        if (det is Map && det['success'] == true) {
          final fBase64 = det['frameBase64']?.toString();
          final faces = det['faces'] as List?;
          double currentScore = 0.0;
          List<double>? box;
          if (faces != null && faces.isNotEmpty) {
            final f = faces[0] as Map;
            currentScore = (f['score'] as num?)?.toDouble() ?? 0.0;
            if (f['box'] is List) {
              box = (f['box'] as List).map((v) => (v as num).toDouble()).toList();
            }
          }

          final width = (det['width'] as num?)?.toDouble() ?? 0;
          final height = (det['height'] as num?)?.toDouble() ?? 0;
          final eligible = det['enrollmentEligible'] == true &&
              faces != null &&
              faces.length == 1 &&
              fBase64 != null;

          if (mounted) {
            setState(() {
              if (fBase64 != null) _frameBase64 = fBase64;
              _score = currentScore;
              _faceBox = box;
              if (width > 0 && height > 0) {
                _aspectRatio = width / height;
              }
              _centeredFrames = eligible ? _centeredFrames + 1 : 0;

              if (eligible) {
                if (_centeredFrames >= 2) {
                  _statusText = '🟢 Khuôn mặt đã căn giữa chuẩn! Đang đối sánh danh tính...';
                } else {
                  _statusText = 'Giữ yên khuôn mặt ở giữa khung… ($_centeredFrames/2)';
                }
              } else {
                _statusText = det['guidance']?.toString() ??
                    (currentScore > 0.4
                        ? 'Di chuyển khuôn mặt vào chính giữa khung hướng dẫn.'
                        : 'Đang quét... Hãy hướng khuôn mặt vào giữa khung.');
              }
            });
          }

          if (eligible && _centeredFrames >= 2) {
            _active = false;
            final captureFrame = (_source == 'WEBCAM')
                ? (_grabWebcam(targetWidth: 720, quality: 0.88) ?? fBase64)
                : fBase64;

            final idRes = await widget.api.request(
              '/face/identify',
              method: 'POST',
              body: {
                'contextId': widget.contextId,
                'imageBase64': captureFrame,
                'useEsp32Camera': false,
              },
            );

            if (!mounted) break;

            if (idRes is Map && (idRes['matched'] == true || idRes['outcome'] == 'VEHICLE_ALREADY_IN_LOT')) {
              if (idRes['outcome'] == 'VEHICLE_ALREADY_IN_LOT') {
                if (mounted) {
                  setState(() {
                    _statusText = idRes['message']?.toString() ?? '⛔ Sinh viên này đã có xe trong bãi!';
                    _active = false;
                  });
                  await Future<void>.delayed(const Duration(milliseconds: 2200));
                }
              } else {
                if (mounted) {
                  setState(() {
                    _statusText = '🟢 Nhận diện thành công: ${idRes['studentName']} (${idRes['studentCode']})!';
                  });
                  await Future<void>.delayed(const Duration(milliseconds: 1200));
                }
              }
              if (mounted) {
                Navigator.of(context).pop(idRes as Map<String, dynamic>);
              }
              return;
            } else {
              if (mounted) {
                setState(() {
                  _statusText = '❌ Không tìm thấy hồ sơ sinh viên khớp trong hệ thống.';
                  _active = true;
                  _centeredFrames = 0;
                });
                await Future<void>.delayed(const Duration(seconds: 2));
              }
            }
          }
        }
      } catch (e) {
        if (mounted && _active) {
          setState(() {
            _statusText = 'Đang tìm tín hiệu camera: $e';
          });
        }
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 660),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.face, color: Color(0xff0f766e), size: 24),
                      SizedBox(width: 8),
                      Text(
                        'Quét khuôn mặt bãi xe (Realtime AI)',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Yêu cầu khuôn mặt nằm chính giữa khung hướng dẫn, rõ nét và đủ sáng. Hệ thống sẽ tự động xác thực.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  ChoiceChip(
                    label: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.videocam, size: 15),
                        SizedBox(width: 4),
                        Text('Camera ESP32-S3', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                    selected: _source == 'ESP32',
                    onSelected: (sel) {
                      if (sel) {
                        setState(() {
                          _source = 'ESP32';
                          _stopWebcam();
                          _centeredFrames = 0;
                        });
                      }
                    },
                    selectedColor: const Color(0xffccfbf1),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.laptop, size: 15),
                        SizedBox(width: 4),
                        Text('Webcam máy tính', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                    selected: _source == 'WEBCAM',
                    onSelected: (sel) async {
                      if (sel) {
                        setState(() {
                          _source = 'WEBCAM';
                          _centeredFrames = 0;
                        });
                        await _startWebcam();
                      }
                    },
                    selectedColor: const Color(0xffccfbf1),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              Center(
                child: Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxWidth: 420),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _centeredFrames > 0
                          ? const Color(0xff22c55e)
                          : (_score >= 0.50 ? const Color(0xfff59e0b) : const Color(0xff0ea5e9)),
                      width: 2.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: (_centeredFrames > 0 ? const Color(0xff22c55e) : Colors.black).withValues(alpha: 0.15),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: AspectRatio(
                      aspectRatio: _aspectRatio,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (_source == 'WEBCAM' && _webcamVideo != null)
                            const HtmlElementView(viewType: 'parking-webcam-video')
                          else if (_frameBase64 != null)
                            Image.memory(
                              base64Decode(
                                _frameBase64!.contains(',')
                                    ? _frameBase64!.split(',').last
                                    : _frameBase64!,
                              ),
                              fit: BoxFit.cover,
                              gaplessPlayback: true,
                            )
                          else
                            const Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircularProgressIndicator(color: Color(0xff0f766e)),
                                  SizedBox(height: 12),
                                  Text(
                                    'Đang kết nối camera bãi xe...',
                                    style: TextStyle(color: Colors.white70, fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _ParkingFaceReticlePainter(
                                hasFace: _score > 0.40 || _faceBox != null,
                                isEligible: _centeredFrames > 0,
                                centeredFrames: _centeredFrames,
                                score: _score,
                                faceBox: _faceBox,
                              ),
                            ),
                          ),
                          Positioned(
                            top: 10,
                            right: 10,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: _centeredFrames >= 2
                                    ? const Color(0xff16a34a)
                                    : Colors.black.withValues(alpha: 0.65),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: _centeredFrames >= 2 ? Colors.white : Colors.white30,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _centeredFrames >= 2 ? Icons.check_circle : Icons.videocam,
                                    size: 14,
                                    color: Colors.white,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    _centeredFrames >= 2 ? 'ĐÃ CĂN GIỮA' : 'AI REALTIME',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: _score.clamp(0.0, 1.0),
                  minHeight: 8,
                  backgroundColor: const Color(0xffe2e8f0),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    _centeredFrames > 0
                        ? const Color(0xff16a34a)
                        : (_score >= 0.50 ? const Color(0xfff59e0b) : const Color(0xff94a3b8)),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Độ rõ nét YuNet: ${(_score * 100).toStringAsFixed(1)}% (Chuẩn: ≥ 80%)',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  if (_centeredFrames > 0)
                    Text(
                      'Căn giữa: $_centeredFrames/2',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: Color(0xff16a34a),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _centeredFrames > 0
                      ? const Color(0xfff0fdf4)
                      : (_score >= 0.50 ? const Color(0xfffffbeb) : const Color(0xfff8fafc)),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _centeredFrames > 0
                        ? const Color(0xff86efac)
                        : (_score >= 0.50 ? const Color(0xfffde68a) : const Color(0xffe2e8f0)),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _centeredFrames > 0
                          ? Icons.check_circle_outline
                          : (_score >= 0.50 ? Icons.info_outline : Icons.center_focus_weak),
                      size: 18,
                      color: _centeredFrames > 0
                          ? const Color(0xff16a34a)
                          : (_score >= 0.50 ? const Color(0xffd97706) : Colors.black54),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _statusText,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: _centeredFrames > 0
                              ? const Color(0xff166534)
                              : (_score >= 0.50 ? const Color(0xff92400e) : Colors.black87),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ParkingFaceReticlePainter extends CustomPainter {
  final bool hasFace;
  final bool isEligible;
  final int centeredFrames;
  final double score;
  final List<double>? faceBox;

  _ParkingFaceReticlePainter({
    required this.hasFace,
    required this.isEligible,
    required this.centeredFrames,
    required this.score,
    this.faceBox,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radiusX = size.width * 0.28;
    final radiusY = size.height * 0.40;

    final Color frameColor = isEligible
        ? const Color(0xff22c55e)
        : (hasFace
            ? const Color(0xfff59e0b)
            : Colors.white.withValues(alpha: 0.40));

    final paint = Paint()
      ..color = frameColor.withValues(alpha: isEligible ? 0.95 : (hasFace ? 0.85 : 0.40))
      ..style = PaintingStyle.stroke
      ..strokeWidth = isEligible ? 3.0 : (hasFace ? 2.2 : 1.8);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: radiusX * 2, height: radiusY * 2),
        const Radius.circular(32),
      ),
      paint,
    );

    final cornerPaint = Paint()
      ..color = frameColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = isEligible ? 4.5 : 3.5
      ..strokeCap = StrokeCap.round;

    const cornerLen = 22.0;
    final left = center.dx - radiusX - 10;
    final right = center.dx + radiusX + 10;
    final top = center.dy - radiusY - 10;
    final bottom = center.dy + radiusY + 10;

    // Top-Left
    canvas.drawLine(Offset(left, top + cornerLen), Offset(left, top), cornerPaint);
    canvas.drawLine(Offset(left, top), Offset(left + cornerLen, top), cornerPaint);
    // Top-Right
    canvas.drawLine(Offset(right - cornerLen, top), Offset(right, top), cornerPaint);
    canvas.drawLine(Offset(right, top), Offset(right, top + cornerLen), cornerPaint);
    // Bottom-Left
    canvas.drawLine(Offset(left, bottom - cornerLen), Offset(left, bottom), cornerPaint);
    canvas.drawLine(Offset(left, bottom), Offset(left + cornerLen, bottom), cornerPaint);
    // Bottom-Right
    canvas.drawLine(Offset(right - cornerLen, bottom), Offset(right, bottom), cornerPaint);
    canvas.drawLine(Offset(right, bottom), Offset(right, bottom - cornerLen), cornerPaint);

    if (!isEligible) {
      final crosshairPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      canvas.drawLine(Offset(center.dx - 12, center.dy), Offset(center.dx + 12, center.dy), crosshairPaint);
      canvas.drawLine(Offset(center.dx, center.dy - 12), Offset(center.dx, center.dy + 12), crosshairPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ParkingFaceReticlePainter oldDelegate) =>
      oldDelegate.hasFace != hasFace ||
      oldDelegate.isEligible != isEligible ||
      oldDelegate.centeredFrames != centeredFrames ||
      oldDelegate.score != score ||
      oldDelegate.faceBox != faceBox;
}
