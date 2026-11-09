import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;
import '../core/campus_api.dart';
import 'shared.dart';

class CanteenPage extends StatefulWidget {
  final CampusApi api;
  const CanteenPage(this.api, {super.key});
  @override
  State<CanteenPage> createState() => _CanteenPageState();
}

class _CanteenPageState extends State<CanteenPage> {
  final Map<String, int> cart = {};
  String? orderId, contextId, identityId;
  bool useFace = false; // false = RFID, true = Face AI
  bool isProcessing = false;
  Map<String, dynamic>? identifiedStudent;

  Timer? _rfidPollTimer;
  String? _lastHandledTappedAt;

  CampusApi get api => widget.api;

  @override
  void initState() {
    super.initState();
    _startRfidPolling();
  }

  @override
  void dispose() {
    _rfidPollTimer?.cancel();
    super.dispose();
  }

  void _startRfidPolling() {
    _rfidPollTimer?.cancel();
    _rfidPollTimer = Timer.periodic(const Duration(milliseconds: 600), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (orderId == null || useFace || isProcessing) return;

      try {
        final res = await api.request('/admin/latest-tapped-card');
        if (res is Map && res['uid'] != null) {
          final tappedAtStr = res['tappedAt'] as String?;
          final uid = res['uid'].toString().trim().toUpperCase();
          if (uid.isNotEmpty && tappedAtStr != null && tappedAtStr != _lastHandledTappedAt) {
            _lastHandledTappedAt = tappedAtStr;
            final check = await api.request('/admin/check-card?uid=$uid');
            if (check is Map && check['registered'] == true && mounted) {
              setState(() {
                identifiedStudent = {
                  'studentId': check['studentId'],
                  'studentCode': check['studentCode'],
                  'studentName': check['studentName'],
                  'walletBalance': check['walletBalance'],
                  'rfidUid': uid,
                };
              });
            }
          }
        }
      } catch (_) {}
    });
  }

  Future<void> _ensureCheckoutContext(Map detail, List<RowData> terminals) async {
    if (contextId != null || orderId == null) return;
    try {
      final posDevice = terminals.firstWhere(
        (d) =>
            d['role'] == 'CANTEEN_POS' ||
            d['name'].toString().contains('Căng tin') ||
            d['name'].toString().contains('RFID'),
        orElse: () => terminals.first,
      );
      final r = await api.request(
        '/canteen/orders/$orderId/checkout-contexts',
        method: 'POST',
        body: {'deviceId': posDevice['id'], 'expectedVersion': detail['version']},
      );
      if (mounted) {
        setState(() => contextId = r['id'] as String?);
      }
    } catch (_) {}
  }

  Future<void> _processPayment(BigInt totalPoints, String studentName) async {
    if (orderId == null || isProcessing) return;
    setState(() => isProcessing = true);
    try {
      final body = <String, dynamic>{};
      if (identifiedStudent?['identityAssertionId'] != null) {
        body['identityAssertionId'] = identifiedStudent!['identityAssertionId'];
      } else if (identifiedStudent?['rfidUid'] != null) {
        body['rfidUid'] = identifiedStudent!['rfidUid'];
      } else if (identifiedStudent?['studentId'] != null) {
        body['studentId'] = identifiedStudent!['studentId'];
      } else if (identityId != null) {
        body['identityAssertionId'] = identityId;
      }

      await api.request(
        '/canteen/orders/$orderId/direct-pay',
        method: 'POST',
        body: body,
      );

      if (mounted) {
        setState(() {
          orderId = null;
          contextId = null;
          identityId = null;
          identifiedStudent = null;
        });
      }
      api.changed();

      if (context.mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: const Icon(Icons.check_circle, color: Color(0xff16a34a), size: 48),
            title: const Text(
              'THANH TOÁN CĂNG TIN THÀNH CÔNG',
              style: TextStyle(color: Color(0xff16a34a), fontWeight: FontWeight.bold),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Đã tự động trừ ${pointText(totalPoints.toString())} từ ví của $studentName.',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text('Giao dịch đã hoàn tất và xuất hóa đơn.', textAlign: TextAlign.center),
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
            icon: const Icon(Icons.cancel, color: Color(0xffdc2626), size: 52),
            title: Text(
              isInsufficient
                  ? 'TỪ CHỐI THANH TOÁN - VÍ KHÔNG ĐỦ POINT'
                  : 'KHÔNG THỂ THANH TOÁN',
              style: const TextStyle(color: Color(0xffdc2626), fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  e.message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
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
                      '⛔ GIAO DỊCH BỊ TỪ CHỐI!\nVí sinh viên không đủ số dư để thanh toán đơn hàng này. Vui lòng yêu cầu sinh viên nạp thêm điểm vào ví trước khi mua hàng.',
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
                style: FilledButton.styleFrom(backgroundColor: const Color(0xffdc2626)),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Đã hiểu'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        error(context, 'Lỗi thanh toán: $e');
      }
    } finally {
      if (mounted) setState(() => isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) => DataPanel(
    key: ValueKey(orderId),
    api: api,
    paths: [
      '/canteen/products',
      '/canteen/orders',
      '/simulator/status',
      '/simulator/students',
      '/simulator/events',
      if (orderId != null) '/canteen/orders/$orderId',
    ],
    builder: (context, data) {
      final products = rows(data['/canteen/products']),
          orders = rows(data['/canteen/orders']);
      final terminals = rows(
        (data['/simulator/status'] as Map)['devices'],
      ).where((d) => d['role'] == 'CANTEEN_POS' || d['role'] == 'RFID_READER' || d['name'].toString().contains('RFID')).toList();
      final detail = data['/canteen/orders/$orderId'] as Map?;

      // Auto ensure context when order is opened
      if (detail != null && detail['status'] == 'AWAITING_PAYMENT' && contextId == null && terminals.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _ensureCheckoutContext(detail, terminals);
        });
      }

      // Check context identities if any matched via hardware bridge
      final identities = rows((data['/simulator/events'] as Map)['identities'])
          .where((i) => i['contextId'] == contextId && i['consumedAt'] == null)
          .toList();
      if (identities.isNotEmpty && identifiedStudent == null) {
        final firstId = identities.first;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && identifiedStudent == null) {
            setState(() {
              identityId = firstId['id'] as String?;
              identifiedStudent = {
                'studentId': firstId['studentId'],
                'studentCode': firstId['studentCode'],
                'studentName': firstId['studentName'],
                'identityAssertionId': firstId['id'],
              };
            });
          }
        });
      }

      final totalPointsStr = detail?['totalPoints']?.toString() ?? '0';
      final BigInt totalPoints = BigInt.tryParse(totalPointsStr) ?? BigInt.zero;

      final studentBalanceStr = identifiedStudent?['walletBalance']?.toString();
      final BigInt? studentBalance = studentBalanceStr != null ? BigInt.tryParse(studentBalanceStr) : null;
      final bool isInsufficient = studentBalance != null && studentBalance < totalPoints;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionTitle(
            'Cantin • Điểm bán hàng',
            'Thanh toán tự động bằng Thẻ RFID thật hoặc Nhận diện khuôn mặt AI (SFace). Tự động trừ ví trực tiếp.',
          ),
          const ModeLabels(),
          const SizedBox(height: 20),

          // PHẦN CHỌN MÓN
          Surface(
            title: 'Chọn món',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: products
                      .map(
                        (p) => SizedBox(
                          width: 235,
                          child: Card(
                            color: const Color(0xfff0fdfa),
                            elevation: 0,
                            child: Padding(
                              padding: const EdgeInsets.all(18),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.restaurant_outlined,
                                    size: 30,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    p['name'].toString(),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 18,
                                    ),
                                  ),
                                  Text(pointText(p['pricePoints'])),
                                  Text('Khả dụng: ${p['available']}'),
                                  Row(
                                    children: [
                                      IconButton(
                                        onPressed: (cart[p['id']] ?? 0) > 0
                                            ? () => setState(
                                                () => cart[p['id']] =
                                                    (cart[p['id']] ?? 0) - 1,
                                              )
                                            : null,
                                        icon: const Icon(
                                          Icons.remove_circle_outline,
                                        ),
                                      ),
                                      Text('${cart[p['id']] ?? 0}'),
                                      IconButton(
                                        onPressed:
                                            p['active'] == true &&
                                                p['available'] > 0
                                            ? () => setState(
                                                () => cart[p['id']] =
                                                    (cart[p['id']] ?? 0) + 1,
                                              )
                                            : null,
                                        icon: const Icon(
                                          Icons.add_circle_outline,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 16),
                ActionButton(
                  'Tạo đơn & giữ hàng',
                  cart.values.every((v) => v == 0)
                      ? null
                      : () async {
                          final r = await api.request(
                            '/canteen/orders',
                            method: 'POST',
                            body: {
                              'items': cart.entries
                                  .where((e) => e.value > 0)
                                  .map(
                                    (e) => {
                                      'productId': e.key,
                                      'quantity': e.value,
                                    },
                                  )
                                  .toList(),
                            },
                          );
                          if (mounted) {
                            setState(() {
                              orderId = r['id'] as String;
                              cart.clear();
                              contextId = null;
                              identityId = null;
                              identifiedStudent = null;
                            });
                          }
                          api.changed();
                        },
                  icon: Icons.shopping_bag_outlined,
                ),
              ],
            ),
          ),

          // PHẦN THANH TOÁN ĐƠN ĐANG THAO TÁC (TƯƠNG TỰ BÃI XE)
          if (detail != null)
            Surface(
              title: 'Đơn đang thao tác • ${pointText(totalPointsStr)}',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('Trạng thái đơn: ', style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(display(detail['status']), style: const TextStyle(color: Color(0xff0f766e), fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (detail['status'] == 'AWAITING_PAYMENT') ...[
                    // CHỌN PHƯƠNG THỨC: THẺ RFID HOẶC KHUÔN MẶT AI
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
                      onSelectionChanged: (values) => setState(() {
                        useFace = values.single;
                        identifiedStudent = null;
                      }),
                    ),
                    const SizedBox(height: 16),

                    // KHUNG THÔNG TIN SINH VIÊN KHI ĐÃ NHẬN DIỆN THÀNH CÔNG
                    if (identifiedStudent != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isInsufficient ? const Color(0xfffef2f2) : const Color(0xfff0fdf4),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isInsufficient ? const Color(0xfff87171) : const Color(0xff86efac),
                            width: 1.5,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  isInsufficient ? Icons.warning_amber : Icons.verified_user,
                                  color: isInsufficient ? const Color(0xffdc2626) : const Color(0xff16a34a),
                                  size: 28,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${identifiedStudent!['studentName']} (${identifiedStudent!['studentCode']})',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                          color: isInsufficient ? const Color(0xff991b1b) : const Color(0xff166534),
                                        ),
                                      ),
                                      if (studentBalanceStr != null) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          'Số dư ví hiện tại: ${pointText(studentBalanceStr)}',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: isInsufficient ? const Color(0xffdc2626) : const Color(0xff15803d),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 20),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Số tiền đơn hàng cần trừ:', style: TextStyle(fontSize: 13)),
                                Text(
                                  pointText(totalPointsStr),
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xff0f766e)),
                                ),
                              ],
                            ),
                            if (isInsufficient) ...[
                              const SizedBox(height: 8),
                              Text(
                                '⛔ Số dư ví không đủ để thanh toán (Còn thiếu ${(totalPoints - studentBalance!).toString()} point).',
                                style: const TextStyle(fontSize: 12.5, color: Color(0xffb91c1c), fontWeight: FontWeight.bold),
                              ),
                            ],
                          ],
                        ),
                      )
                    else ...[
                      // CHƯA NHẬN DIỆN SINH VIÊN
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xfffffbeb),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xfffde68a)),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              useFace ? Icons.camera_alt_outlined : Icons.nfc,
                              color: const Color(0xffd97706),
                              size: 28,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                useFace
                                    ? 'Bấm nút "Quét khuôn mặt AI (SFace)" bên dưới để nhận diện khách hàng qua camera.'
                                    : 'Chạm thẻ sinh viên RFID lên đầu đọc MFRC522 để nhận diện và thanh toán tự động.',
                                style: const TextStyle(fontSize: 13, color: Color(0xff92400e), height: 1.3),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // HÀNG NÚT THAO TÁC
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        if (useFace && identifiedStudent == null)
                          ActionButton(
                            'Quét khuôn mặt AI (SFace)',
                            contextId == null
                                ? null
                                : () async {
                                    final res = await showDialog<Map<String, dynamic>?>(
                                      context: context,
                                      barrierDismissible: false,
                                      builder: (ctx) => _LiveCanteenFaceIdentifyDialog(
                                        api: api,
                                        contextId: contextId!,
                                      ),
                                    );
                                    if (res != null && res['matched'] == true) {
                                      if (mounted) {
                                        setState(() {
                                          identifiedStudent = res;
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
                                    }
                                  },
                            icon: Icons.face,
                          ),

                        if (identifiedStudent != null)
                          ActionButton(
                            'Xác nhận thanh toán & Trừ ví',
                            isProcessing || isInsufficient
                                ? null
                                : () => _processPayment(
                                      totalPoints,
                                      identifiedStudent!['studentName']?.toString() ?? 'sinh viên',
                                    ),
                            icon: Icons.check_circle_outline,
                          ),

                        if (identifiedStudent != null)
                          ActionButton(
                            'Quét lại người khác',
                            () async { setState(() => identifiedStudent = null); },
                            outlined: true,
                          ),

                        ActionButton(
                          'Hủy đơn hàng',
                          isProcessing
                              ? null
                              : () async {
                                  await api.request(
                                    '/canteen/orders/$orderId/cancel',
                                    method: 'POST',
                                    body: {'reason': 'Nhân viên hủy đơn tại POS'},
                                  );
                                  if (mounted) {
                                    setState(() {
                                      orderId = null;
                                      contextId = null;
                                      identityId = null;
                                      identifiedStudent = null;
                                    });
                                  }
                                  api.changed();
                                },
                          outlined: true,
                          icon: Icons.close,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

          // LỊCH SỬ ĐƠN GẦN ĐÂY
          Surface(
            title: 'Đơn gần đây',
            child: RecordTable(
              data: orders,
              columns: const {
                'totalPoints': 'Tổng point',
                'status': 'Trạng thái',
                'createdAt': 'Thời gian',
              },
              actions: (o) => TextButton(
                onPressed: () => setState(() {
                  orderId = o['id'] as String;
                  contextId = null;
                  identityId = null;
                  identifiedStudent = null;
                }),
                child: const Text('Mở đơn'),
              ),
            ),
          ),
        ],
      );
    },
  );
}

// CỬA SỔ CAMERA REALTIME QUÉT KHUÔN MẶT CĂNG TIN
class _LiveCanteenFaceIdentifyDialog extends StatefulWidget {
  final CampusApi api;
  final String contextId;
  const _LiveCanteenFaceIdentifyDialog({
    required this.api,
    required this.contextId,
  });

  @override
  State<_LiveCanteenFaceIdentifyDialog> createState() =>
      _LiveCanteenFaceIdentifyDialogState();
}

class _LiveCanteenFaceIdentifyDialogState
    extends State<_LiveCanteenFaceIdentifyDialog> {
  bool _active = true;
  double _score = 0.0;
  String? _frameBase64;
  String _statusText = 'Đang mở camera Căng tin realtime...';
  String _source = 'ESP32';
  web.HTMLVideoElement? _webcamVideo;
  web.MediaStream? _webcamStream;
  List<double>? _faceBox;

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
        ..muted = true;
      await _webcamVideo!.play().toDart;
    } catch (_) {}
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

  String? _grabWebcam() {
    if (_webcamVideo == null || _webcamVideo!.videoWidth == 0) return null;
    final canvas = web.HTMLCanvasElement()
      ..width = _webcamVideo!.videoWidth
      ..height = _webcamVideo!.videoHeight;
    final ctx = canvas.getContext('2d') as web.CanvasRenderingContext2D;
    ctx.drawImage(_webcamVideo!, 0, 0);
    return canvas.toDataURL('image/jpeg');
  }

  Future<void> _startLoop() async {
    while (mounted && _active) {
      try {
        String? b64;
        if (_source == 'WEBCAM') {
          b64 = _grabWebcam();
          if (b64 == null) {
            await Future<void>.delayed(const Duration(milliseconds: 200));
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

          if (mounted) {
            setState(() {
              if (fBase64 != null) _frameBase64 = fBase64;
              _score = currentScore;
              _faceBox = box;
              if (currentScore >= 0.80) {
                _statusText =
                    'Độ tin cậy: ${(currentScore * 100).toStringAsFixed(1)}% (Đạt chuẩn YuNet! Đang xác thực sinh viên...)';
              } else if (currentScore > 0.3) {
                _statusText =
                    'Phát hiện mặt (${(currentScore * 100).toStringAsFixed(1)}%). Hãy nhìn thẳng vào camera...';
              } else {
                _statusText = 'Chưa phát hiện khuôn mặt đạt chuẩn.';
              }
            });
          }

          if (currentScore >= 0.80) {
            _active = false;
            final idRes = await widget.api.request(
              '/face/identify',
              method: 'POST',
              body: {
                'contextId': widget.contextId,
                'imageBase64': fBase64,
                'useEsp32Camera': false,
              },
            );

            if (!mounted) break;

            if (idRes is Map && idRes['matched'] == true) {
              if (mounted) {
                setState(() {
                  _statusText = '🟢 Nhận diện thành công: ${idRes['studentName']} (${idRes['studentCode']})!';
                });
                await Future<void>.delayed(const Duration(milliseconds: 1400));
                if (mounted) {
                  Navigator.of(context).pop(idRes as Map<String, dynamic>);
                }
              }
              return;
            } else {
              if (mounted) {
                setState(() {
                  _statusText = '❌ Không tìm thấy hồ sơ sinh viên khớp trong hệ thống.';
                  _active = true;
                });
                await Future<void>.delayed(const Duration(seconds: 2));
              }
            }
          }
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _statusText = 'Đang kết nối camera: $e';
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
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.face, color: Color(0xff0f766e)),
                      SizedBox(width: 8),
                      Text(
                        'Quét khuôn mặt thanh toán Căng tin',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ],
                  ),
                  IconButton(
                    onPressed: () {
                      _active = false;
                      Navigator.of(context).pop();
                    },
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'ESP32', label: Text('Camera ESP32')),
                  ButtonSegment(value: 'WEBCAM', label: Text('Webcam máy tính')),
                ],
                selected: {_source},
                onSelectionChanged: (val) {
                  setState(() {
                    _source = val.single;
                    _score = 0;
                    _faceBox = null;
                  });
                  if (_source == 'WEBCAM') {
                    _startWebcam();
                  } else {
                    _stopWebcam();
                  }
                },
              ),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 480,
                  height: 320,
                  color: Colors.black,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (_frameBase64 != null)
                        Image.memory(
                          base64Decode(_frameBase64!.split(',').last),
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                        )
                      else
                        const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        ),
                      if (_faceBox != null)
                        CustomPaint(
                          painter: _FaceBoxPainter(
                            box: _faceBox!,
                            score: _score,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              LinearProgressIndicator(
                value: (_score / 0.8).clamp(0.0, 1.0),
                backgroundColor: const Color(0xffe2e8f0),
                color: _score >= 0.8 ? const Color(0xff16a34a) : const Color(0xff0f766e),
                minHeight: 6,
              ),
              const SizedBox(height: 10),
              Text(
                _statusText,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: _score >= 0.8 ? const Color(0xff16a34a) : Colors.black87,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FaceBoxPainter extends CustomPainter {
  final List<double> box;
  final double score;
  _FaceBoxPainter({required this.box, required this.score});

  @override
  void paint(Canvas canvas, Size size) {
    if (box.length < 4) return;
    final paint = Paint()
      ..color = score >= 0.8 ? const Color(0xff22c55e) : const Color(0xff38bdf8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    final x = box[0];
    final y = box[1];
    final w = box[2];
    final h = box[3];
    canvas.drawRect(Rect.fromLTWH(x, y, w, h), paint);
  }

  @override
  bool shouldRepaint(covariant _FaceBoxPainter oldDelegate) =>
      oldDelegate.box != box || oldDelegate.score != score;
}

class InventoryPage extends StatelessWidget {
  final CampusApi api;
  const InventoryPage(this.api, {super.key});
  @override
  Widget build(BuildContext context) => DataPanel(
    api: api,
    paths: const [
      '/canteen/products',
      '/canteen/categories',
      '/canteen/inventory-movements',
      '/refunds',
    ],
    builder: (context, data) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle(
          'Hàng hóa & tồn kho',
          'Nhập hàng, thay đổi giá bán và theo dõi biến động kho.',
        ),
        Surface(
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              ActionButton(
                'Thêm danh mục',
                () => submitForm(
                  context,
                  api,
                  'Danh mục mới',
                  '/canteen/categories',
                  const [FormFieldSpec('name', 'Tên danh mục')],
                ),
                outlined: true,
              ),
              ActionButton(
                'Thêm sản phẩm',
                () => submitForm(
                  context,
                  api,
                  'Sản phẩm mới',
                  '/canteen/products',
                  [
                    FormFieldSpec(
                      'categoryId',
                      'Danh mục',
                      options: options(
                        rows(data['/canteen/categories']),
                        'name',
                      ),
                    ),
                    const FormFieldSpec('sku', 'Mã hàng'),
                    const FormFieldSpec('name', 'Tên sản phẩm'),
                    const FormFieldSpec(
                      'pricePoints',
                      'Giá point',
                      kind: 'points',
                    ),
                    const FormFieldSpec(
                      'initialStock',
                      'Tồn ban đầu',
                      kind: 'integer',
                      initial: '0',
                    ),
                  ],
                ),
                icon: Icons.add,
              ),
              ActionButton(
                'Điều chỉnh kho',
                () => submitForm(
                  context,
                  api,
                  'Nhập / điều chỉnh hàng',
                  '/canteen/inventory-adjustments',
                  [
                    FormFieldSpec(
                      'productId',
                      'Sản phẩm',
                      options: options(rows(data['/canteen/products']), 'name'),
                    ),
                    const FormFieldSpec(
                      'delta',
                      'Số lượng tăng hoặc giảm',
                      kind: 'integer',
                    ),
                    const FormFieldSpec('reason', 'Lý do', kind: 'multiline'),
                  ],
                ),
                outlined: true,
              ),
              ActionButton(
                'Hoàn point',
                () => submitForm(
                  context,
                  api,
                  'Hoàn point giao dịch gốc',
                  '/refunds',
                  const [
                    FormFieldSpec(
                      'originalTransactionId',
                      'Mã giao dịch trên biên lai',
                    ),
                    FormFieldSpec(
                      'amountPoints',
                      'Số point hoàn',
                      kind: 'points',
                    ),
                    FormFieldSpec('reason', 'Lý do', kind: 'multiline'),
                  ],
                ),
                outlined: true,
              ),
            ],
          ),
        ),
        Surface(
          title: 'Sản phẩm',
          child: RecordTable(
            data: rows(data['/canteen/products']),
            columns: const {
              'name': 'Tên sản phẩm',
              'pricePoints': 'Giá point',
              'onHand': 'Tồn thực',
              'reserved': 'Đang giữ',
              'active': 'Đang bán',
            },
            actions: (p) => ActionButton(
              'Sửa',
              () => submitForm(
                context,
                api,
                'Giá và trạng thái bán',
                '/canteen/products/${p['id']}',
                [
                  FormFieldSpec(
                    'name',
                    'Tên sản phẩm',
                    initial: p['name'].toString(),
                  ),
                  FormFieldSpec(
                    'pricePoints',
                    'Giá point mới',
                    kind: 'points',
                    initial: p['pricePoints'].toString(),
                  ),
                ],
                method: 'PATCH',
                extra: {'active': true, 'expectedVersion': p['priceVersion']},
              ),
              outlined: true,
            ),
          ),
        ),
        Surface(
          title: 'Biến động kho',
          child: RecordTable(
            data: rows(data['/canteen/inventory-movements']),
            columns: const {
              'kind': 'Loại',
              'quantityDelta': 'Thay đổi',
              'reason': 'Lý do',
              'createdAt': 'Thời gian',
            },
          ),
        ),
        Surface(
          title: 'Hoàn point',
          child: RecordTable(
            data: rows(data['/refunds']),
            columns: const {
              'amountPoints': 'Point hoàn',
              'reason': 'Lý do',
              'createdAt': 'Thời gian',
            },
          ),
        ),
      ],
    ),
  );
}
