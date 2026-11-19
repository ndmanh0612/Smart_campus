import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;
import '../core/report_export.dart';
import '../core/campus_api.dart';
import 'shared.dart';

class AttendancePage extends StatefulWidget {
  final CampusApi api;
  const AttendancePage(this.api, {super.key});
  @override
  State<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends State<AttendancePage> {
  String? selected;
  Timer? _rfidPollTimer;
  String? _lastTappedAt;
  String? _recentCheckinMessage;
  bool _isSuccessMessage = true;

  CampusApi get api => widget.api;

  @override
  void dispose() {
    _rfidPollTimer?.cancel();
    super.dispose();
  }

  void _startRfidPolling(String sessionId) {
    _rfidPollTimer?.cancel();
    _rfidPollTimer = Timer.periodic(const Duration(milliseconds: 300), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (selected != sessionId) {
        timer.cancel();
        return;
      }
      try {
        final res = await api.request('/admin/latest-tapped-card');
        if (res is Map && res['uid'] != null) {
          final tappedAtStr = res['tappedAt'] as String?;
          final uid = res['uid'].toString().trim().toUpperCase();
          if (uid.isNotEmpty && tappedAtStr != null && tappedAtStr != _lastTappedAt) {
            _lastTappedAt = tappedAtStr;
            final checkinRes = await api.request(
              '/attendance/sessions/$sessionId/checkin',
              method: 'POST',
              body: {'cardUid': uid, 'method': 'RFID'},
            );
            if (!mounted) return;
            if (checkinRes is Map) {
              final student = checkinRes['student'] as Map?;
              final sName = student?['name'] ?? 'Sinh viên';
              final sCode = student?['studentCode'] ?? '';
              final status = checkinRes['status'] == 'LATE' ? 'Đi muộn' : 'Có mặt';
              final isAlready = checkinRes['alreadyRecorded'] == true;
              setState(() {
                _isSuccessMessage = !isAlready;
                _recentCheckinMessage = isAlready
                    ? 'ℹ️ $sName ($sCode) đã điểm danh trước đó ($status)'
                    : '✅ Điểm danh THẺ RFID: $sName ($sCode) — $status';
              });
              api.changed();
            }
          }
        }
      } catch (e) {
        // Silently continue polling or log
      }
    });
  }

  void _stopRfidPolling() {
    _rfidPollTimer?.cancel();
    _rfidPollTimer = null;
  }

  @override
  Widget build(BuildContext context) => DataPanel(
    key: ValueKey(selected),
    api: api,
    paths: [
      '/lecturer/class-sections',
      '/attendance/sessions',
      '/simulator/status',
      '/simulator/students',
      '/attendance/adjustment-requests',
      if (selected != null) '/attendance/sessions/$selected/records',
    ],
    builder: (context, data) {
      final classes = rows(data['/lecturer/class-sections']),
          sessions = rows(data['/attendance/sessions']);
      final cameras = rows(
        (data['/simulator/status'] as Map)['devices'],
      ).where((d) => d['kind'] == 'ATTENDANCE_CAMERA').toList();
      final students = rows(data['/simulator/students']);
      final current = sessions.where((s) => s['id'] == selected).firstOrNull;

      // Maintain RFID polling if current session is OPEN
      if (current != null && current['status'] == 'OPEN') {
        if (_rfidPollTimer == null || !_rfidPollTimer!.isActive) {
          _startRfidPolling(current['id'] as String);
        }
      } else {
        _stopRfidPolling();
      }

      final records = selected != null ? rows(data['/attendance/sessions/$selected/records']) : <RowData>[];

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionTitle(
            'Lớp học & điểm danh',
            'Hỗ trợ quẹt thẻ RFID (ESP32) hoặc nhận diện khuôn mặt Camera AI realtime.',
          ),
          Surface(
            title: 'Lịch lớp được phân công',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RecordTable(
                  data: classes,
                  columns: const {
                    'code': 'Lớp học phần',
                    'startsAt': 'Bắt đầu',
                    'endsAt': 'Kết thúc',
                  },
                  actions: (c) => ActionButton('Tạo phiên', () async {
                    final f = await formDialog(
                      context,
                      'Chọn camera đúng phòng',
                      [
                        FormFieldSpec(
                          'deviceId',
                          'Camera phòng học',
                          options: options(cameras, 'name'),
                        ),
                      ],
                    );
                    if (f == null) return;
                    final s = await api.request(
                      '/attendance/sessions',
                      method: 'POST',
                      body: {'scheduleId': c['scheduleId'], ...f},
                    );
                    if (mounted) setState(() => selected = s['id'] as String);
                    api.changed();
                  }, icon: Icons.add),
                ),
              ],
            ),
          ),
          Surface(
            title: 'Phiên điểm danh',
            child: RecordTable(
              data: sessions,
              columns: const {
                'status': 'Trạng thái',
                'openedAt': 'Mở phiên',
                'lateAfter': 'Ngưỡng muộn',
              },
              actions: (s) => Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: () {
                      setState(() {
                        selected = s['id'] as String;
                        _recentCheckinMessage = null;
                      });
                      api.subscribeAttendance(s['id'] as String);
                    },
                    child: Text(selected == s['id'] ? '● Đang chọn' : 'Theo dõi'),
                  ),
                  if (s['status'] == 'SCHEDULED')
                    ActionButton('Mở phiên', () async {
                      await api.request(
                        '/attendance/sessions/${s['id']}/open',
                        method: 'POST',
                        body: {'expectedVersion': s['version']},
                      );
                      api.subscribeAttendance(s['id'] as String);
                      if (mounted) {
                        setState(() {
                          selected = s['id'] as String;
                          _recentCheckinMessage = '🟢 Phiên điểm danh đã mở thành công! Hãy quẹt thẻ hoặc mở camera.';
                          _isSuccessMessage = true;
                        });
                      }
                      api.changed();
                    }),
                  if (s['status'] == 'OPEN')
                    ActionButton('Đóng phiên', () async {
                      _stopRfidPolling();
                      await api.request(
                        '/attendance/sessions/${s['id']}/close',
                        method: 'POST',
                        body: {'expectedVersion': s['version']},
                      );
                      api.changed();
                    }, outlined: true),
                  if (['SCHEDULED', 'OPEN'].contains(s['status']))
                    ActionButton(
                      'Hủy',
                      () => submitForm(
                        context,
                        api,
                        'Hủy phiên điểm danh',
                        '/attendance/sessions/${s['id']}/cancel',
                        const [
                          FormFieldSpec(
                            'reason',
                            'Lý do hủy',
                            kind: 'multiline',
                          ),
                        ],
                        extra: {'expectedVersion': s['version']},
                      ),
                      outlined: true,
                    ),
                ],
              ),
            ),
          ),
          if (current != null)
            Surface(
              title: 'Theo dõi phiên: ${current['id']}',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Thông báo kết quả điểm danh realtime
                  if (_recentCheckinMessage != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: _isSuccessMessage ? const Color(0xffecfdf5) : const Color(0xfff0f9ff),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _isSuccessMessage ? const Color(0xff10b981) : const Color(0xff38bdf8),
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _isSuccessMessage ? Icons.check_circle : Icons.info,
                            color: _isSuccessMessage ? const Color(0xff059669) : const Color(0xff0284c7),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _recentCheckinMessage!,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: _isSuccessMessage ? const Color(0xff065f46) : const Color(0xff0369a1),
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () => setState(() => _recentCheckinMessage = null),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Trạng thái lắng nghe quẹt thẻ nếu phiên OPEN
                  if (current['status'] == 'OPEN') ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xfff0fdf4),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xffbbf7d0)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.sensors, color: Color(0xff16a34a), size: 20),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Đầu đọc RFID (ESP32) đang sẵn sàng — Chạm thẻ bất kỳ lúc nào để ghi nhận điểm danh.',
                              style: TextStyle(color: Color(0xff15803d), fontSize: 13, fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Hàng nút thao tác
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      if (current['status'] == 'OPEN') ...[
                        ActionButton(
                          'Quét mặt điểm danh (Camera AI)',
                          () async {
                            await showDialog<void>(
                              context: context,
                              barrierDismissible: false,
                              builder: (ctx) => _AttendanceFaceScanDialog(
                                api: api,
                                sessionId: current['id'] as String,
                                onCheckinSuccess: (studentName, studentCode, status) {
                                  if (mounted) {
                                    setState(() {
                                      _isSuccessMessage = true;
                                      _recentCheckinMessage = '✅ Điểm danh KHUÔN MẶT: $studentName ($studentCode) — $status';
                                    });
                                    api.changed();
                                  }
                                },
                              ),
                            );
                            if (mounted) api.changed();
                          },
                          icon: Icons.camera_alt,
                        ),
                        ActionButton(
                          'Điểm danh Face DEMO (Mô phỏng)',
                          () async {
                            final f = await formDialog(
                              context,
                              'Mô phỏng nhận diện điểm danh',
                              [
                                FormFieldSpec(
                                  'studentFixtureId',
                                  'Sinh viên mẫu',
                                  options: options(students, 'name'),
                                ),
                                const FormFieldSpec(
                                  'scenario',
                                  'Tình huống',
                                  options: {
                                    'SUCCESS': 'Nhận diện thành công',
                                    'UNKNOWN': 'Không nhận diện',
                                    'LOW_CONFIDENCE': 'Độ tin cậy thấp',
                                    'LIVENESS_FAIL': 'Liveness thất bại',
                                    'MULTIPLE_FACES': 'Nhiều khuôn mặt',
                                    'TIMEOUT': 'Hết thời gian',
                                  },
                                ),
                              ],
                            );
                            if (f == null) return;
                            await api.request(
                              '/simulator/attendance-events',
                              method: 'POST',
                              body: {
                                ...f,
                                'sessionId': current['id'],
                                'deviceId': current['deviceId'],
                              },
                            );
                            api.changed();
                          },
                          icon: Icons.face,
                          outlined: true,
                        ),
                      ],
                      ActionButton(
                        'Xuất nội dung CSV',
                        () async {
                          final report = await api.request(
                            '/attendance/sessions/$selected/report',
                          );
                          final message = await exportReport(
                            report['fileName'] as String,
                            report['content'] as String,
                          );
                          if (context.mounted) {
                            success(context, message);
                          }
                        },
                        icon: Icons.download_outlined,
                        outlined: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Bảng kết quả điểm danh
                  Text(
                    'Danh sách đã điểm danh (${records.length} sinh viên)',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  RecordTable(
                    data: records,
                    columns: const {
                      'studentCode': 'Mã sinh viên',
                      'name': 'Họ tên',
                      'status': 'Kết quả',
                      'source': 'Nguồn',
                      'receivedAt': 'Thời gian',
                    },
                    actions: (r) => ActionButton(
                      'Điều chỉnh',
                      () => submitForm(
                        context,
                        api,
                        'Điều chỉnh có lý do',
                        '/attendance/records/${r['id']}',
                        const [
                          FormFieldSpec(
                            'status',
                            'Kết quả mới',
                            options: {
                              'PRESENT': 'Có mặt',
                              'LATE': 'Đi muộn',
                              'ABSENT': 'Vắng',
                              'EXCUSED': 'Có phép',
                            },
                          ),
                          FormFieldSpec(
                            'reason',
                            'Lý do điều chỉnh',
                            kind: 'multiline',
                          ),
                        ],
                        method: 'PATCH',
                        extra: {'expectedVersion': r['version']},
                      ),
                      outlined: true,
                    ),
                  ),
                ],
              ),
            ),
          Surface(
            title: 'Yêu cầu điều chỉnh',
            child: RecordTable(
              data: rows(data['/attendance/adjustment-requests']),
              columns: const {
                'requestedStatus': 'Đề nghị',
                'reason': 'Lý do',
                'status': 'Trạng thái',
              },
              actions: (r) => r['status'] == 'PENDING'
                  ? ActionButton(
                      'Xử lý',
                      () => submitForm(
                        context,
                        api,
                        'Duyệt yêu cầu',
                        '/attendance/adjustment-requests/${r['id']}/decisions',
                        const [
                          FormFieldSpec(
                            'decision',
                            'Quyết định',
                            options: {
                              'APPROVED': 'Chấp thuận',
                              'REJECTED': 'Từ chối',
                            },
                          ),
                          FormFieldSpec(
                            'reason',
                            'Lý do quyết định',
                            kind: 'multiline',
                          ),
                        ],
                      ),
                      outlined: true,
                    )
                  : const Text('Đã xử lý'),
            ),
          ),
        ],
      );
    },
  );
}

// ============================================================================
// DIALOG ĐIỂM DANH KHUÔN MẶT REALTIME (WEBCAM / SFace AI)
// ============================================================================
class _AttendanceFaceScanDialog extends StatefulWidget {
  final CampusApi api;
  final String sessionId;
  final Function(String name, String code, String status) onCheckinSuccess;

  const _AttendanceFaceScanDialog({
    required this.api,
    required this.sessionId,
    required this.onCheckinSuccess,
  });

  @override
  State<_AttendanceFaceScanDialog> createState() => _AttendanceFaceScanDialogState();
}

class _AttendanceFaceScanDialogState extends State<_AttendanceFaceScanDialog> {
  bool _active = true;
  String _statusText = 'Đang khởi động Camera AI...';
  String? _lastIdentifiedName;
  web.HTMLVideoElement? _webcamVideo;
  web.MediaStream? _webcamStream;
  List<double>? _faceBox;
  int _centeredFrames = 0;
  bool _isProcessing = false;
  double _aspectRatio = 4 / 3;

  static bool _viewRegistered = false;

  @override
  void initState() {
    super.initState();
    _startWebcam();
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

      if (!_viewRegistered) {
        ui_web.platformViewRegistry.registerViewFactory(
          'attendance-webcam-video',
          (int viewId) => _webcamVideo!,
        );
        _viewRegistered = true;
      }
      await _webcamVideo!.play().toDart;
      if (mounted) {
        setState(() {
          _statusText = 'Camera đã sẵn sàng. Hãy đứng trước camera và căn giữa khuôn mặt.';
        });
        _startDetectionLoop();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusText = 'Không thể truy cập Webcam: $e';
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

  Future<void> _startDetectionLoop() async {
    while (mounted && _active) {
      if (_isProcessing) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        continue;
      }

      try {
        final b64 = _grabWebcam(targetWidth: 480, quality: 0.65);
        if (b64 == null) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          continue;
        }

        final det = await widget.api.request(
          '/face/detect',
          method: 'POST',
          body: {
            'useEsp32Camera': false,
            'imageBase64': b64,
          },
        );

        if (!mounted || !_active) break;

        if (det is Map && det['success'] == true) {
          final faces = det['faces'] as List?;
          final eligible = det['enrollmentEligible'] == true && faces != null && faces.length == 1;
          List<double>? box;
          if (faces != null && faces.isNotEmpty) {
            final f = faces[0] as Map;
            if (f['box'] is List) {
              box = (f['box'] as List).map((v) => (v as num).toDouble()).toList();
            }
          }

          final width = (det['width'] as num?)?.toDouble() ?? 0;
          final height = (det['height'] as num?)?.toDouble() ?? 0;

          if (mounted) {
            setState(() {
              _faceBox = box;
              if (width > 0 && height > 0) {
                _aspectRatio = width / height;
              }
              _centeredFrames = eligible ? _centeredFrames + 1 : 0;
              if (eligible) {
                if (_centeredFrames >= 2) {
                  _statusText = '🟢 Đã căn giữa chuẩn! Đang đối sánh khuôn mặt...';
                } else {
                  _statusText = 'Giữ yên khuôn mặt ở giữa khung… ($_centeredFrames/2)';
                }
              } else {
                _statusText = det['guidance']?.toString() ?? 'Hãy di chuyển khuôn mặt vào chính giữa khung.';
              }
            });
          }

          // Kích hoạt nhận diện khi mặt căn giữa đủ 2 frame
          if (eligible && _centeredFrames >= 2 && !_isProcessing) {
            _isProcessing = true;
            final highResB64 = _grabWebcam(targetWidth: 720, quality: 0.88) ?? b64;

            try {
              final checkinRes = await widget.api.request(
                '/attendance/sessions/${widget.sessionId}/checkin',
                method: 'POST',
                body: {
                  'imageBase64': highResB64,
                  'method': 'FACE',
                },
              );

              if (mounted && checkinRes is Map) {
                final student = checkinRes['student'] as Map?;
                final sName = student?['name'] ?? 'Sinh viên';
                final sCode = student?['studentCode'] ?? '';
                final status = checkinRes['status'] == 'LATE' ? 'Đi muộn' : 'Có mặt';
                final already = checkinRes['alreadyRecorded'] == true;

                setState(() {
                  _lastIdentifiedName = '$sName ($sCode) — $status${already ? ' (Đã điểm danh)' : ''}';
                  _statusText = '✅ Đã nhận diện: $sName ($sCode)';
                });

                widget.onCheckinSuccess(sName.toString(), sCode.toString(), status);

                // Cooldown 3s cho người tiếp theo
                await Future<void>.delayed(const Duration(milliseconds: 2500));
              }
            } catch (err) {
              if (mounted) {
                setState(() {
                  _statusText = '⚠️ $err';
                });
                await Future<void>.delayed(const Duration(milliseconds: 1500));
              }
            } finally {
              _isProcessing = false;
              _centeredFrames = 0;
            }
          }
        }
      } catch (_) {
        // Continue loop
      }

      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 720),
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
                      Icon(Icons.face_retouching_natural, color: Color(0xff0d9488)),
                      SizedBox(width: 8),
                      Text(
                        'Điểm danh Khuôn mặt AI',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xfff0fdfa),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xff99f6e4)),
                ),
                child: Text(
                  _statusText,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xff0f766e),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(
                  aspectRatio: _aspectRatio,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      const HtmlElementView(viewType: 'attendance-webcam-video'),
                      CustomPaint(
                        painter: _AttendanceFaceOverlayPainter(
                          faceBox: _faceBox,
                          isCentered: _centeredFrames >= 2,
                        ),
                      ),
                      if (_isProcessing)
                        Container(
                          color: Colors.black26,
                          child: const Center(
                            child: CircularProgressIndicator(color: Colors.tealAccent),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              if (_lastIdentifiedName != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xffecfdf5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xff10b981)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle, color: Color(0xff059669)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _lastIdentifiedName!,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Color(0xff065f46),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.check),
                    label: const Text('Hoàn tất điểm danh'),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// PAINTER VẼ KHUNG HƯỚNG DẪN CĂN GIỮA VÀ BOUNDING BOX KHUÔN MẶT
// ============================================================================
class _AttendanceFaceOverlayPainter extends CustomPainter {
  final List<double>? faceBox;
  final bool isCentered;

  _AttendanceFaceOverlayPainter({
    required this.faceBox,
    required this.isCentered,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final guidePaint = Paint()
      ..color = isCentered ? const Color(0xff10b981) : const Color(0xff14b8a6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = isCentered ? 3.5 : 2.5;

    // Vùng chuẩn trung tâm: 50% chiều rộng, 60% chiều cao
    final guideW = size.width * 0.48;
    final guideH = size.height * 0.58;
    final guideLeft = (size.width - guideW) / 2;
    final guideTop = (size.height - guideH) / 2;
    final guideRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(guideLeft, guideTop, guideW, guideH),
      const Radius.circular(20),
    );
    canvas.drawRRect(guideRRect, guidePaint);

    // Vẽ 4 góc định vị
    final cornerPaint = Paint()
      ..color = isCentered ? const Color(0xff10b981) : const Color(0xff2dd4bf)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round;

    const cornerLen = 22.0;
    // Top-left
    canvas.drawLine(Offset(guideLeft, guideTop + cornerLen), Offset(guideLeft, guideTop), cornerPaint);
    canvas.drawLine(Offset(guideLeft, guideTop), Offset(guideLeft + cornerLen, guideTop), cornerPaint);
    // Top-right
    canvas.drawLine(Offset(guideLeft + guideW - cornerLen, guideTop), Offset(guideLeft + guideW, guideTop), cornerPaint);
    canvas.drawLine(Offset(guideLeft + guideW, guideTop), Offset(guideLeft + guideW, guideTop + cornerLen), cornerPaint);
    // Bottom-left
    canvas.drawLine(Offset(guideLeft, guideTop + guideH - cornerLen), Offset(guideLeft, guideTop + guideH), cornerPaint);
    canvas.drawLine(Offset(guideLeft, guideTop + guideH), Offset(guideLeft + cornerLen, guideTop + guideH), cornerPaint);
    // Bottom-right
    canvas.drawLine(Offset(guideLeft + guideW - cornerLen, guideTop + guideH), Offset(guideLeft + guideW, guideTop + guideH), cornerPaint);
    canvas.drawLine(Offset(guideLeft + guideW, guideTop + guideH), Offset(guideLeft + guideW, guideTop + guideH - cornerLen), cornerPaint);

    // Vẽ Face Box nếu phát hiện được
    if (faceBox != null && faceBox!.length >= 4) {
      final bx = (1.0 - (faceBox![0] + faceBox![2])) * size.width;
      final by = faceBox![1] * size.height;
      final bw = faceBox![2] * size.width;
      final bh = faceBox![3] * size.height;

      final facePaint = Paint()
        ..color = isCentered ? const Color(0xff10b981) : Colors.amber
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(bx, by, bw, bh), const Radius.circular(10)),
        facePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AttendanceFaceOverlayPainter oldDelegate) {
    return oldDelegate.faceBox != faceBox || oldDelegate.isCentered != isCentered;
  }
}
