import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;
import '../core/campus_api.dart';

Future<void> showEnrollStudentWizardDialog(
  BuildContext context,
  CampusApi api,
) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _EnrollStudentWizardDialog(api: api),
  );
}

class _EnrollStudentWizardDialog extends StatefulWidget {
  const _EnrollStudentWizardDialog({required this.api});
  final CampusApi api;

  @override
  State<_EnrollStudentWizardDialog> createState() =>
      _EnrollStudentWizardDialogState();
}

class _EnrollStudentWizardDialogState
    extends State<_EnrollStudentWizardDialog> {
  int _currentStep = 0;
  bool _submitting = false;
  bool _obscurePassword = true;

  // Bước 1: Thông tin cơ bản
  final _formKeyStep1 = GlobalKey<FormState>();
  final _emailController =
      TextEditingController(text: 'sinhvien@gmail.com');
  final _nameController = TextEditingController(text: 'Nguyễn Văn A');
  final _codeController = TextEditingController(text: 'SV2026001');
  final _passwordController = TextEditingController(text: '12345678');

  // Bước 2: Quẹt thẻ RFID
  final _rfidUidController = TextEditingController();
  Timer? _rfidPollTimer;
  DateTime? _wizardStartTime;
  String? _lastHandledTappedAt;
  String? _pendingTappedUid;

  // Kiểm tra trùng lặp thẻ RFID & khuôn mặt
  bool _isCheckingCard = false;
  bool _cardAlreadyRegistered = false;
  String? _cardConflictStudentName;
  String? _cardConflictStudentCode;

  bool _isCheckingFace = false;
  bool _faceAlreadyRegistered = false;
  String? _faceConflictStudentName;
  String? _faceConflictStudentCode;
  double _faceConflictScore = 0.0;

  // Bước 3: Khuôn mặt thật - Realtime Camera & Auto-Capture
  bool _faceCaptured = false;
  bool _liveScanActive = false;
  double _currentYunetScore = 0.0;
  String _faceStatusText = 'Đang khởi động camera dò tìm khuôn mặt realtime...';
  String? _faceImageBase64;
  String _selectedCameraSource = 'ESP32'; // 'ESP32' hoặc 'WEBCAM'
  web.HTMLVideoElement? _webcamVideo;
  web.MediaStream? _webcamStream;
  List<double>? _currentFaceBox;

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
    } catch (e) {
      if (mounted) {
        setState(() {
          _faceStatusText = 'Không thể truy cập Webcam máy tính: $e';
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

  String? _grabWebcamFrameBase64() {
    if (_webcamVideo == null || _webcamVideo!.videoWidth == 0) return null;
    final canvas = web.HTMLCanvasElement()
      ..width = _webcamVideo!.videoWidth
      ..height = _webcamVideo!.videoHeight;
    final ctx = canvas.getContext('2d') as web.CanvasRenderingContext2D;
    ctx.drawImage(_webcamVideo!, 0, 0);
    return canvas.toDataURL('image/jpeg');
  }

  void _startLiveFaceDetection() {
    if (_liveScanActive || _faceCaptured) return;
    _liveScanActive = true;
    _currentYunetScore = 0.0;
    _currentFaceBox = null;
    _faceStatusText = 'Đang kết nối camera và dò tìm khuôn mặt...';
    _runLiveScanLoop();
  }

  void _stopLiveFaceDetection() {
    _liveScanActive = false;
  }

  Future<void> _switchCameraSource(String newSource) async {
    if (_selectedCameraSource == newSource) return;
    setState(() {
      _selectedCameraSource = newSource;
      _currentYunetScore = 0.0;
      _currentFaceBox = null;
      _faceStatusText = 'Đang chuyển đổi camera...';
    });
    if (newSource == 'WEBCAM') {
      await _startWebcam();
    } else {
      _stopWebcam();
    }
    if (!_faceCaptured && _currentStep == 2) {
      _startLiveFaceDetection();
    }
  }

  Future<void> _runLiveScanLoop() async {
    while (mounted && _liveScanActive && !_faceCaptured && _currentStep == 2) {
      try {
        String? webcamFrame;
        if (_selectedCameraSource == 'WEBCAM') {
          webcamFrame = _grabWebcamFrameBase64();
          if (webcamFrame == null) {
            await Future<void>.delayed(const Duration(milliseconds: 200));
            continue;
          }
        }

        final res = await widget.api.request(
          '/face/detect',
          method: 'POST',
          body: {
            'useEsp32Camera': _selectedCameraSource == 'ESP32',
            if (_selectedCameraSource == 'WEBCAM') 'imageBase64': webcamFrame,
          },
        );

        if (!mounted || !_liveScanActive || _faceCaptured || _currentStep != 2) break;

        if (res is Map && res['success'] == true) {
          final frameBase64 = res['frameBase64']?.toString();
          final faces = res['faces'] as List?;
          double score = 0.0;
          List<double>? box;

          if (faces != null && faces.isNotEmpty) {
            final firstFace = faces[0] as Map;
            score = (firstFace['score'] as num?)?.toDouble() ?? 0.0;
            final rawBox = firstFace['box'] as List?;
            if (rawBox != null && rawBox.length == 4) {
              box = rawBox.map((e) => (e as num).toDouble()).toList();
            }
          }

          if (mounted) {
            setState(() {
              if (frameBase64 != null) {
                _faceImageBase64 = frameBase64;
              }
              _currentYunetScore = score;
              _currentFaceBox = box;

              if (score >= 0.80) {
                // TỰ ĐỘNG CHỤP KHI ĐỦ TỶ LỆ YUNET SCORE (>= 80%)
                _liveScanActive = false;
                _faceStatusText = '🔍 Đang kiểm tra trùng lặp khuôn mặt trên hệ thống...';
                _checkFaceDuplication(frameBase64, score);
              } else if (score >= 0.50) {
                _faceStatusText =
                    '🔍 Đang lấy nét: ${(score * 100).toStringAsFixed(1)}% (Cần ≥ 80% để tự chụp). Giữ yên khuôn mặt...';
              } else {
                _faceStatusText = 'Đang quét... Hãy hướng khuôn mặt vào camera.';
              }
            });
          }
        }
      } catch (e) {
        if (mounted && _liveScanActive) {
          setState(() {
            _faceStatusText = 'Đang tìm tín hiệu camera: $e';
          });
        }
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }

      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  @override
  void initState() {
    super.initState();
    _wizardStartTime = DateTime.now();
    _clearServerTappedCard();
    _startRfidPolling();
    _rfidUidController.addListener(() {
      final text = _rfidUidController.text.trim().replaceAll(' ', '').toUpperCase();
      if (text.length >= 8 && !_isCheckingCard && _currentStep == 1) {
        _checkCardRegistration(text);
      }
    });
  }

  void _clearServerTappedCard() {
    widget.api.request('/admin/clear-latest-card', method: 'POST').catchError((_) => null);
  }

  @override
  void dispose() {
    _stopLiveFaceDetection();
    _stopWebcam();
    _rfidPollTimer?.cancel();
    _emailController.dispose();
    _nameController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _rfidUidController.dispose();
    super.dispose();
  }

  void _startRfidPolling() {
    _rfidPollTimer?.cancel();
    _rfidPollTimer = Timer.periodic(const Duration(milliseconds: 500), (
      timer,
    ) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      try {
        final res = await widget.api.request(
          '/admin/latest-tapped-card',
        );
        if (res is Map && res['uid'] != null) {
          final tappedAtStr = res['tappedAt'] as String?;
          final newUid = res['uid'].toString().trim().toUpperCase();
          if (newUid.isNotEmpty) {
            if (_currentStep == 1) {
              if (_rfidUidController.text != newUid || (tappedAtStr != null && tappedAtStr != _lastHandledTappedAt)) {
                _lastHandledTappedAt = tappedAtStr;
                if (mounted) {
                  setState(() {
                    _rfidUidController.text = newUid;
                  });
                  _checkCardRegistration(newUid);
                }
              }
            } else {
              _pendingTappedUid = newUid;
              _lastHandledTappedAt = tappedAtStr;
            }
          }
        }
      } catch (_) {
        // Bỏ qua lỗi polling mạng định kỳ
      }
    });
  }

  Future<void> _checkCardRegistration(String uid) async {
    final cleanUid = uid.trim().replaceAll(' ', '').toUpperCase();
    if (cleanUid.length < 4) {
      if (mounted) {
        setState(() {
          _cardAlreadyRegistered = false;
          _cardConflictStudentName = null;
          _cardConflictStudentCode = null;
        });
      }
      return;
    }
    setState(() => _isCheckingCard = true);
    try {
      final res = await widget.api.request('/admin/check-card?uid=$cleanUid');
      if (!mounted) return;
      if (res is Map && res['registered'] == true) {
        setState(() {
          _cardAlreadyRegistered = true;
          _cardConflictStudentName = res['studentName']?.toString();
          _cardConflictStudentCode = res['studentCode']?.toString();
        });
      } else {
        setState(() {
          _cardAlreadyRegistered = false;
          _cardConflictStudentName = null;
          _cardConflictStudentCode = null;
        });
      }
    } catch (_) {
      // Bỏ qua lỗi mạng
    } finally {
      if (mounted) setState(() => _isCheckingCard = false);
    }
  }

  Future<void> _checkFaceDuplication(String? frameBase64, double score) async {
    if (frameBase64 == null) return;
    setState(() => _isCheckingFace = true);
    try {
      final res = await widget.api.request(
        '/face/check-enrolled',
        method: 'POST',
        body: {'imageBase64': frameBase64},
      );
      if (!mounted) return;
      if (res is Map && res['alreadyEnrolled'] == true) {
        setState(() {
          _faceCaptured = false;
          _faceAlreadyRegistered = true;
          _faceConflictStudentName = res['studentName']?.toString();
          _faceConflictStudentCode = res['studentCode']?.toString();
          _faceConflictScore = (res['score'] as num?)?.toDouble() ?? 0.0;
          _faceStatusText =
              '⛔ Khuôn mặt này đã thuộc về: ${_faceConflictStudentName} (${_faceConflictStudentCode}) • Trùng khớp: ${(_faceConflictScore * 100).toStringAsFixed(1)}%';
        });
      } else {
        setState(() {
          _faceCaptured = true;
          _faceAlreadyRegistered = false;
          _faceConflictStudentName = null;
          _faceConflictStudentCode = null;
          _faceStatusText =
              '🟢 ĐÃ TỰ ĐỘNG CHỤP & KHUÔN MẶT HỢP LỆ (Chưa từng đăng ký, YuNet: ${(score * 100).toStringAsFixed(1)}%)';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _faceCaptured = true;
          _faceAlreadyRegistered = false;
          _faceStatusText = '🟢 ĐÃ TỰ ĐỘNG CHỤP KHUÔN MẶT (YuNet: ${(score * 100).toStringAsFixed(1)}%)';
        });
      }
    } finally {
      if (mounted) setState(() => _isCheckingFace = false);
    }
  }

  Future<void> _submitEnrollment() async {
    setState(() => _submitting = true);
    try {
      final payload = {
        'email': _emailController.text.trim().toLowerCase(),
        'name': _nameController.text.trim(),
        'studentCode': _codeController.text.trim().toUpperCase(),
        'password': _passwordController.text,
        'rfidUid': _rfidUidController.text.trim().replaceAll(' ', '').toUpperCase(),
        if (_faceImageBase64 != null) 'faceImageBase64': _faceImageBase64,
      };

      final res = await widget.api.request(
        '/admin/enroll-student',
        method: 'POST',
        body: payload,
      );
      widget.api.changed();

      if (mounted) {
        Navigator.of(context).pop(); // Đóng wizard
        // Hiển thị dialog kết quả thành công
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Color(0xff16a34a), size: 28),
                SizedBox(width: 10),
                Text('Đăng ký sinh viên thành công!'),
              ],
            ),
            content: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xfff0fdf4),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xffbbf7d0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('• Họ và tên: ${res['name']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                        Text('• MSSV: ${res['studentCode']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                        Text('• Gmail: ${res['email']}'),
                        Text('• Mật khẩu: ${_passwordController.text}'),
                        Text('• Thẻ RFID: ${res['rfidUid'] ?? 'Đã liên kết'}'),
                        const Text('• Khuôn mặt SFace: Đã kích hoạt'),
                        const Text('• Số dư ví khởi tạo: 0 point (Sinh viên tự nạp trên App)'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Sinh viên có thể sử dụng Gmail và Mật khẩu này để đăng nhập ngay trên ứng dụng sinh viên, nạp tiền vào ví và quẹt thẻ RFID để gửi xe, mua hàng căng tin mà không cần PIN!',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Color(0xff0f766e),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xff16a34a),
                ),
                child: const Text('Xong'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Đăng ký thất bại: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 760),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Tiêu đề & Nút đóng
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.how_to_reg, color: Color(0xff0f766e), size: 28),
                      SizedBox(width: 10),
                      Text(
                        'Đăng ký sinh viên trọn gói',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xff134e4a),
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: _submitting ? null : () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Thanh tiến trình 3 bước
              _buildStepperHeader(),
              const Divider(height: 28),

              // Nội dung của từng bước
              Expanded(
                child: SingleChildScrollView(
                  child: _buildStepContent(),
                ),
              ),

              const SizedBox(height: 16),

              // Nút điều hướng các bước
              _buildBottomActions(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepperHeader() {
    final steps = [
      {'number': '1', 'title': 'Tài khoản', 'subtitle': 'Gmail & MSSV'},
      {'number': '2', 'title': 'Thẻ RFID', 'subtitle': 'Tap thẻ SV'},
      {'number': '3', 'title': 'Khuôn mặt', 'subtitle': 'SFace AI'},
    ];

    return Row(
      children: [
        for (int i = 0; i < steps.length; i++) ...[
          Expanded(
            child: Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: _currentStep > i
                      ? const Color(0xff16a34a)
                      : _currentStep == i
                          ? const Color(0xff0f766e)
                          : Colors.grey.shade300,
                  foregroundColor: Colors.white,
                  child: _currentStep > i
                      ? const Icon(Icons.check, size: 16)
                      : Text(
                          steps[i]['number']!,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        steps[i]['title']!,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: _currentStep == i
                              ? FontWeight.bold
                              : FontWeight.w500,
                          color: _currentStep == i
                              ? const Color(0xff0f766e)
                              : Colors.grey.shade700,
                        ),
                      ),
                      Text(
                        steps[i]['subtitle']!,
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (i < steps.length - 1)
            Container(
              width: 24,
              height: 2,
              color: _currentStep > i
                  ? const Color(0xff16a34a)
                  : Colors.grey.shade300,
              margin: const EdgeInsets.symmetric(horizontal: 4),
            ),
        ],
      ],
    );
  }

  Widget _buildStepContent() {
    switch (_currentStep) {
      case 0:
        return _buildStep1Form();
      case 1:
        return _buildStep2Rfid();
      case 2:
        return _buildStep3Face();
      default:
        return const SizedBox.shrink();
    }
  }

  // BƯỚC 1: Nhập Gmail, Họ tên, MSSV, Mật khẩu
  Widget _buildStep1Form() {
    return Form(
      key: _formKeyStep1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Bước 1: Nhập thông tin tài khoản sinh viên',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Color(0xff0f766e),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Sinh viên sẽ sử dụng Gmail và Mật khẩu này để đăng nhập vào ứng dụng sinh viên.',
            style: TextStyle(fontSize: 13, color: Colors.black54),
          ),
          const SizedBox(height: 16),

          // Gmail
          TextFormField(
            controller: _emailController,
            decoration: const InputDecoration(
              labelText: 'Gmail / Email sinh viên',
              hintText: 'sinhvien@gmail.com',
              prefixIcon: Icon(Icons.email_outlined),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            keyboardType: TextInputType.emailAddress,
            validator: (v) {
              final val = v?.trim() ?? '';
              if (val.isEmpty) return 'Vui lòng nhập Gmail';
              if (!val.contains('@') || !val.contains('.')) {
                return 'Định dạng Gmail không hợp lệ';
              }
              return null;
            },
          ),
          const SizedBox(height: 14),

          // Họ và tên
          TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Họ và tên sinh viên',
              hintText: 'Nguyễn Văn A',
              prefixIcon: Icon(Icons.person_outline),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) {
                return 'Vui lòng nhập họ và tên';
              }
              return null;
            },
          ),
          const SizedBox(height: 14),

          // MSSV
          TextFormField(
            controller: _codeController,
            decoration: const InputDecoration(
              labelText: 'Mã số sinh viên (MSSV)',
              hintText: 'SV2026001',
              prefixIcon: Icon(Icons.badge_outlined),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            textCapitalization: TextCapitalization.characters,
            validator: (v) {
              if (v == null || v.trim().isEmpty) {
                return 'Vui lòng nhập mã số sinh viên';
              }
              return null;
            },
          ),
          const SizedBox(height: 14),

          // Mật khẩu
          TextFormField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            decoration: InputDecoration(
              labelText: 'Mật khẩu đăng nhập',
              hintText: 'Tối thiểu 6 ký tự',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
                onPressed: () => setState(
                  () => _obscurePassword = !_obscurePassword,
                ),
              ),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            validator: (v) {
              if (v == null || v.length < 6) {
                return 'Mật khẩu phải có ít nhất 6 ký tự';
              }
              return null;
            },
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, size: 20, color: Color(0xff0369a1)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Số dư ví sẽ được sinh viên tự nạp qua ứng dụng. Biển số xe sẽ tự lưu khi xe vào bãi và tự xóa khi xe ra.',
                    style: TextStyle(fontSize: 12, color: Color(0xff0369a1)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // BƯỚC 2: Tap thẻ RFID vào đầu đọc
  Widget _buildStep2Rfid() {
    final rawUid = _rfidUidController.text.trim().replaceAll(' ', '').toUpperCase();
    final hasValidUid = rawUid.length >= 4;

    final formattedUid = rawUid.replaceAllMapped(
      RegExp(r'.{2}'),
      (match) => '${match.group(0)} ',
    ).trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Bước 2: Chạm thẻ RFID thật vào đầu đọc MFRC522',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xff0f766e),
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Yêu cầu quẹt thẻ sinh viên vật lý lên đầu đọc MFRC522 (Cổng COM10). Hệ thống sẽ tự động quét được mã thẻ và hiển thị lên màn hình.',
          style: TextStyle(fontSize: 13, color: Colors.black54),
        ),
        const SizedBox(height: 24),

        if (!hasValidUid)
          Center(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
              decoration: BoxDecoration(
                color: const Color(0xfff8fafc),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.blueGrey.shade200, width: 1.5),
              ),
              child: Column(
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 96,
                        height: 96,
                        child: CircularProgressIndicator(
                          strokeWidth: 3.5,
                          color: const Color(0xff0f766e).withValues(alpha: 0.5),
                        ),
                      ),
                      CircleAvatar(
                        radius: 38,
                        backgroundColor:
                            const Color(0xff0f766e).withValues(alpha: 0.12),
                        child: const Icon(
                          Icons.contactless,
                          size: 46,
                          color: Color(0xff0f766e),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    'ĐANG CHỜ QUẸT THẺ RFID THẬT...',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                      color: Color(0xff0f766e),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Hãy áp thẻ sinh viên vào đầu đọc MFRC522 (COM10).\nHệ thống đang tự động lắng nghe tín hiệu quét thẻ...',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.black54,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          )
        else if (_cardAlreadyRegistered)
          Center(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
              decoration: BoxDecoration(
                color: const Color(0xfffef2f2),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xfff87171), width: 2),
              ),
              child: Column(
                children: [
                  const CircleAvatar(
                    radius: 36,
                    backgroundColor: Color(0xfffee2e2),
                    child: Icon(
                      Icons.cancel,
                      size: 44,
                      color: Color(0xffdc2626),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '⛔ THẺ RFID ĐÃ ĐƯỢC ĐĂNG KÝ TRƯỚC ĐÓ!',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Color(0xff991b1b),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Thẻ UID: $formattedUid\nđã được gán cho sinh viên: ${_cardConflictStudentName ?? "Đã có người dùng"} (MSSV: ${_cardConflictStudentCode ?? "—"}).\n\nHệ thống không cho phép trùng thẻ. Vui lòng quẹt thẻ RFID khác!',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, color: Color(0xff7f1d1d), height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _rfidUidController.clear();
                        _cardAlreadyRegistered = false;
                        _cardConflictStudentName = null;
                        _cardConflictStudentCode = null;
                        _wizardStartTime = DateTime.now();
                      });
                      _clearServerTappedCard();
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Quẹt thẻ RFID khác'),
                    style: OutlinedButton.styleFrom(foregroundColor: const Color(0xffdc2626)),
                  ),
                ],
              ),
            ),
          )
        else
          Center(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
              decoration: BoxDecoration(
                color: const Color(0xfff0fdf4),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xff86efac), width: 2),
              ),
              child: Column(
                children: [
                  const CircleAvatar(
                    radius: 36,
                    backgroundColor: Color(0xffdcfce7),
                    child: Icon(
                      Icons.check_circle,
                      size: 44,
                      color: Color(0xff16a34a),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '🟢 ĐÃ QUÉT ĐƯỢC THẺ RFID THẬT TỪ ĐẦU ĐỌC!',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Color(0xff166534),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xff86efac)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        const Text(
                          'MÃ UID THẺ SINH VIÊN',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xff15803d),
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          formattedUid,
                          style: const TextStyle(
                            fontSize: 22,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.bold,
                            color: Color(0xff14532d),
                            letterSpacing: 2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _rfidUidController.clear();
                        _wizardStartTime = DateTime.now();
                        _clearServerTappedCard();
                      });
                    },
                    icon: const Icon(
                      Icons.refresh,
                      size: 18,
                      color: Colors.black54,
                    ),
                    label: const Text(
                      'Quẹt lại thẻ khác',
                      style: TextStyle(color: Colors.black54),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // BƯỚC 3: Lấy khuôn mặt - Realtime Window Cam & Auto-Capture
  Widget _buildStep3Face() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Bước 3: Tự động chụp khuôn mặt AI (YuNet + SFace)',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xff0f766e),
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Hướng mặt thẳng vào camera. Hệ thống tự động phân tích độ nét realtime và TỰ ĐỘNG CHỤP khi YuNet Score ≥ 80%.',
          style: TextStyle(fontSize: 12.5, color: Colors.black54),
        ),
        const SizedBox(height: 12),

        // Lựa chọn nguồn camera (ESP32-S3 hoặc Webcam Laptop)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xfff1f5f9),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.blueGrey.shade100),
          ),
          child: Row(
            children: [
              const Text(
                'Nguồn Cam: ',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.videocam, size: 15),
                    SizedBox(width: 4),
                    Text('Camera ESP32-S3 (192.168.2.43)', style: TextStyle(fontSize: 12)),
                  ],
                ),
                selected: _selectedCameraSource == 'ESP32',
                onSelected: (sel) {
                  if (sel) _switchCameraSource('ESP32');
                },
                selectedColor: const Color(0xffccfbf1),
                labelStyle: TextStyle(
                  color: _selectedCameraSource == 'ESP32' ? const Color(0xff0f766e) : Colors.black87,
                  fontWeight: _selectedCameraSource == 'ESP32' ? FontWeight.bold : FontWeight.normal,
                ),
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
                selected: _selectedCameraSource == 'WEBCAM',
                onSelected: (sel) {
                  if (sel) _switchCameraSource('WEBCAM');
                },
                selectedColor: const Color(0xffccfbf1),
                labelStyle: TextStyle(
                  color: _selectedCameraSource == 'WEBCAM' ? const Color(0xff0f766e) : Colors.black87,
                  fontWeight: _selectedCameraSource == 'WEBCAM' ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Cửa sổ Camera Realtime (Window Cam)
        Center(
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxWidth: 440),
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _faceCaptured
                    ? const Color(0xff22c55e)
                    : (_currentYunetScore >= 0.50
                        ? const Color(0xff0ea5e9)
                        : Colors.blueGrey.shade700),
                width: _faceCaptured ? 3 : 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: (_faceCaptured ? const Color(0xff22c55e) : Colors.black).withValues(alpha: 0.15),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Khung hình camera realtime
                  AspectRatio(
                    aspectRatio: 4 / 3,
                    child: _faceImageBase64 != null
                        ? Image.memory(
                            base64Decode(
                              _faceImageBase64!.contains(',')
                                  ? _faceImageBase64!.split(',').last
                                  : _faceImageBase64!,
                            ),
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                          )
                        : Container(
                            color: const Color(0xff0f172a),
                            child: const Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircularProgressIndicator(color: Color(0xff0f766e)),
                                  SizedBox(height: 12),
                                  Text(
                                    'Đang kết nối luồng camera...',
                                    style: TextStyle(color: Colors.white70, fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                          ),
                  ),

                  // Lớp phủ hướng dẫn khuôn mặt (Face Reticle Overlay)
                  if (!_faceCaptured)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _FaceReticlePainter(
                            hasFace: _currentYunetScore > 0.40,
                            score: _currentYunetScore,
                            faceBox: _currentFaceBox,
                          ),
                        ),
                      ),
                    ),

                  // Huy hiệu trạng thái góc trên bên phải
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: _faceCaptured
                            ? const Color(0xff16a34a)
                            : Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _faceCaptured ? Colors.white : Colors.white30,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _faceCaptured ? Icons.check_circle : Icons.videocam,
                            size: 14,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            _faceCaptured
                                ? 'ĐÃ TỰ ĐỘNG CHỤP'
                                : 'LIVE REALTIME',
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

                  // Nút quét lại khi đã tự động chụp
                  if (_faceCaptured)
                    Positioned(
                      bottom: 12,
                      child: FilledButton.tonalIcon(
                        onPressed: () {
                          setState(() {
                            _faceCaptured = false;
                            _faceImageBase64 = null;
                            _currentYunetScore = 0.0;
                            _currentFaceBox = null;
                            _startLiveFaceDetection();
                          });
                        },
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('Quét lại khuôn mặt', style: TextStyle(fontSize: 12)),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: 0.9),
                          foregroundColor: Colors.black87,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),

        if (_faceAlreadyRegistered)
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xfffef2f2),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xfff87171), width: 1.5),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.cancel, color: Color(0xffdc2626), size: 22),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'KHUÔN MẶT ĐÃ ĐƯỢC ĐĂNG KÝ TRƯỚC ĐÓ!',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xff991b1b),
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Khuôn mặt này đã thuộc về sinh viên: ${_faceConflictStudentName ?? "Đã có trong hệ thống"} (${_faceConflictStudentCode ?? "—"}).\nĐộ khớp sinh trắc học: ${(_faceConflictScore * 100).toStringAsFixed(1)}%.\n\nHệ thống từ chối đăng ký trùng khuôn mặt. Vui lòng quét khuôn mặt của sinh viên chưa đăng ký!',
                  style: const TextStyle(fontSize: 12, color: Color(0xff7f1d1d), height: 1.4),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xffdc2626)),
                  onPressed: () {
                    setState(() {
                      _faceAlreadyRegistered = false;
                      _faceCaptured = false;
                      _faceImageBase64 = null;
                      _currentYunetScore = 0.0;
                      _currentFaceBox = null;
                      _faceConflictStudentName = null;
                      _faceConflictStudentCode = null;
                      _startLiveFaceDetection();
                    });
                  },
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Quét lại khuôn mặt khác'),
                ),
              ],
            ),
          ),

        // Thanh đo YuNet Score (Gauge)
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _faceCaptured
                ? const Color(0xfff0fdf4)
                : const Color(0xfff8fafc),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _faceCaptured ? const Color(0xff86efac) : Colors.blueGrey.shade200,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        _faceCaptured
                            ? Icons.verified
                            : (_currentYunetScore >= 0.80
                                ? Icons.check_circle
                                : Icons.sensors),
                        size: 16,
                        color: _faceCaptured
                            ? const Color(0xff16a34a)
                            : (_currentYunetScore >= 0.80
                                ? const Color(0xff16a34a)
                                : const Color(0xff0284c7)),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Độ tin cậy YuNet: ${(_currentYunetScore * 100).toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: _faceCaptured || _currentYunetScore >= 0.80
                              ? const Color(0xff166534)
                              : const Color(0xff0f172a),
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xffe2e8f0),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'Chuẩn tự chụp: ≥ 80%',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xff475569),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: _faceCaptured ? 1.0 : _currentYunetScore.clamp(0.0, 1.0),
                  minHeight: 8,
                  backgroundColor: const Color(0xffe2e8f0),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    _faceCaptured || _currentYunetScore >= 0.80
                        ? const Color(0xff16a34a)
                        : (_currentYunetScore >= 0.50
                            ? const Color(0xfff59e0b)
                            : const Color(0xff94a3b8)),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _faceStatusText,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: _faceCaptured ? FontWeight.bold : FontWeight.normal,
                  color: _faceCaptured
                      ? const Color(0xff166534)
                      : (_currentYunetScore >= 0.80
                          ? const Color(0xff15803d)
                          : Colors.grey.shade700),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Tóm tắt đăng ký
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xfff0fdf4),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xffbbf7d0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Tóm tắt đăng ký:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 4),
              Text('• Sinh viên: ${_nameController.text} (${_codeController.text})'),
              Text('• Gmail: ${_emailController.text}'),
              Text('• Thẻ RFID: ${_rfidUidController.text.trim()}'),
              Text(
                _faceCaptured
                    ? '• Khuôn mặt: 🟢 Đã tự động chụp đạt chuẩn YuNet SFace'
                    : '• Khuôn mặt: ⏳ Đang quét realtime (Chờ độ nét ≥ 80% để tự chụp)',
                style: TextStyle(
                  color: _faceCaptured ? const Color(0xff166534) : Colors.orange.shade800,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBottomActions() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        if (_currentStep > 0)
          OutlinedButton.icon(
            onPressed: _submitting
                ? null
                : () {
                    setState(() {
                      if (_currentStep == 2) {
                        _stopLiveFaceDetection();
                      }
                      _currentStep--;
                    });
                  },
            icon: const Icon(Icons.arrow_back),
            label: const Text('Quay lại'),
          )
        else
          TextButton(
            onPressed: _submitting ? null : () => Navigator.of(context).pop(),
            child: const Text('Hủy'),
          ),

        if (_currentStep < 2)
          FilledButton.icon(
            onPressed: (_currentStep == 1 &&
                    (_rfidUidController.text.trim().replaceAll(' ', '').length < 4 || _cardAlreadyRegistered || _isCheckingCard))
                ? null
                : () {
                    if (_currentStep == 0) {
                      if (_formKeyStep1.currentState?.validate() ?? false) {
                        setState(() {
                          _currentStep = 1;
                          _rfidUidController.clear();
                          _wizardStartTime = DateTime.now();
                          _clearServerTappedCard();
                        });
                      }
                    } else if (_currentStep == 1) {
                      final uid = _rfidUidController.text
                          .trim()
                          .replaceAll(' ', '')
                          .toUpperCase();
                      if (uid.length < 4) return;
                      setState(() {
                        _currentStep = 2;
                        _startLiveFaceDetection();
                      });
                    }
                  },
            icon: const Icon(Icons.arrow_forward),
            label: Text(
              _currentStep == 0 ? 'Tiếp: Quẹt thẻ RFID' : 'Tiếp: Lấy khuôn mặt',
            ),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xff0f766e),
            ),
          )
        else
          FilledButton.icon(
            onPressed: (_submitting || !_faceCaptured || _faceAlreadyRegistered || _isCheckingFace) ? null : _submitEnrollment,
            icon: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check),
            label: Text(
              _submitting ? 'Đang đăng ký...' : 'Hoàn tất đăng ký',
            ),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xff16a34a),
            ),
          ),
      ],
    );
  }
}

class _FaceReticlePainter extends CustomPainter {
  final bool hasFace;
  final double score;
  final List<double>? faceBox;

  _FaceReticlePainter({required this.hasFace, required this.score, this.faceBox});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radiusX = size.width * 0.28;
    final radiusY = size.height * 0.40;

    final paint = Paint()
      ..color = hasFace
          ? (score >= 0.80
              ? const Color(0xff22c55e).withValues(alpha: 0.9)
              : const Color(0xff0ea5e9).withValues(alpha: 0.8))
          : Colors.white.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = hasFace ? 2.5 : 1.8;

    // Vẽ hình oval định vị khuôn mặt
    canvas.drawOval(
      Rect.fromCenter(center: center, width: radiusX * 2, height: radiusY * 2),
      paint,
    );

    // Vẽ 4 góc định vị (Face ID brackets)
    final cornerPaint = Paint()
      ..color = hasFace
          ? (score >= 0.80 ? const Color(0xff22c55e) : const Color(0xff0ea5e9))
          : Colors.white.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    const cornerLen = 18.0;
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
  }

  @override
  bool shouldRepaint(covariant _FaceReticlePainter oldDelegate) =>
      oldDelegate.hasFace != hasFace ||
      oldDelegate.score != score ||
      oldDelegate.faceBox != faceBox;
}
