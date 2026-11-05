import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'http_client.dart';

class CampusFailure implements Exception {
  final String code;
  final String message;
  final int status;
  CampusFailure(this.code, this.message, this.status);
  @override
  String toString() => message;
}

class CampusApi extends ChangeNotifier {
  final http.Client client;
  final String origin;
  final FlutterSecureStorage storage;
  final bool enableRealtime;
  String? accessToken;
  String? csrfToken;
  Map<String, dynamic>? user;
  io.Socket? socket;
  bool realtimeConnected = false;
  int revision = 0;
  Timer? refreshTimer;
  Future<bool>? refreshing;
  final Map<String, String> pendingKeys = {};
  final Set<String> seenEvents = {};
  final Set<String> attendanceSubscriptions = {};
  CampusApi({
    http.Client? client,
    String? origin,
    FlutterSecureStorage? storage,
    this.enableRealtime = true,
  }) : client = client ?? campusHttpClient(),
       storage = storage ?? const FlutterSecureStorage(),
       origin =
           origin ??
           const String.fromEnvironment('API_BASE_URL', defaultValue: '');
  String get base => origin.isNotEmpty
      ? origin.replaceAll(RegExp(r'/$'), '')
      : kIsWeb
      ? Uri.base.origin
      : 'http://10.0.2.2:8081';
  List<String> get roles => (user?['roles'] as List? ?? []).cast<String>();
  bool get isStudent => roles.contains('STUDENT');
  bool has(String role) => roles.contains(role) || roles.contains('ADMIN');
  String requestKey() =>
      base64Url.encode(List.generate(24, (_) => Random.secure().nextInt(256)));

  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Object? body,
    bool retryAuth = true,
  }) async {
    final identity = '$method:$path:${jsonEncode(body)}';
    final key = pendingKeys.putIfAbsent(identity, requestKey);
    http.Response? response;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final req = http.Request(method, Uri.parse('$base/api/v1$path'));
        req.headers.addAll({
          'Content-Type': 'application/json',
          'Idempotency-Key': key,
          if (accessToken != null) 'Authorization': 'Bearer $accessToken',
          if (!kIsWeb) 'X-Client-Type': 'native',
          if (csrfToken != null) 'X-CSRF-Token': csrfToken!,
        });
        if (body != null) req.body = jsonEncode(body);
        response = await http.Response.fromStream(
          await client.send(req).timeout(const Duration(seconds: 15)),
        );
        break;
      } on TimeoutException {
        if (attempt == 1) {
          throw CampusFailure(
            'OUTCOME_UNKNOWN',
            'Chưa xác định kết quả. Hãy tải lại trạng thái; thử lại sẽ giữ nguyên mã yêu cầu.',
            503,
          );
        }
      } on http.ClientException {
        if (attempt == 1) {
          throw CampusFailure(
            'NETWORK_ERROR',
            'Không kết nối được máy chủ. Kiểm tra mạng và địa chỉ API.',
            503,
          );
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    if (response == null) {
      throw CampusFailure('NETWORK_ERROR', 'Không nhận được phản hồi.', 503);
    }
    if (response.statusCode < 500) pendingKeys.remove(identity);
    dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      throw CampusFailure(
        'INVALID_RESPONSE',
        'Máy chủ trả phản hồi không đúng định dạng.',
        response.statusCode,
      );
    }
    if (response.statusCode == 401 && retryAuth && !path.startsWith('/auth/')) {
      if (await restore()) {
        return request(path, method: method, body: body, retryAuth: false);
      }
      accessToken = null;
      user = null;
      notifyListeners();
    }
    if (response.statusCode >= 400) {
      final error = decoded['error'] as Map? ?? {};
      throw CampusFailure(
        error['code']?.toString() ?? 'ERROR',
        error['message']?.toString() ?? 'Không thực hiện được yêu cầu.',
        response.statusCode,
      );
    }
    return decoded['data'];
  }

  Future<void> login(String email, String password) async {
    final data = Map<String, dynamic>.from(
      await request(
        '/auth/login',
        method: 'POST',
        body: {'email': email, 'password': password},
      ),
    );
    await acceptSession(data);
  }

  Future<void> acceptSession(Map<String, dynamic> data) async {
    accessToken = data['accessToken'] as String;
    csrfToken = data['csrfToken'] as String? ?? csrfToken;
    if (!kIsWeb && data['refreshToken'] != null) {
      await storage.write(
        key: 'campus_refresh',
        value: data['refreshToken'] as String,
      );
    }
    user = Map<String, dynamic>.from(await request('/me', retryAuth: false));
    refreshTimer?.cancel();
    refreshTimer = Timer(
      const Duration(minutes: 14),
      () => unawaited(restore()),
    );
    connectRealtime();
    notifyListeners();
  }

  Future<bool> restore() {
    if (refreshing != null) return refreshing!;
    refreshing = _restore().whenComplete(() => refreshing = null);
    return refreshing!;
  }

  Future<bool> _restore() async {
    try {
      Map<String, dynamic> body = {};
      if (kIsWeb) {
        csrfToken =
            (await request('/auth/csrf', retryAuth: false))['csrfToken']
                as String;
      } else {
        final refresh = await storage.read(key: 'campus_refresh');
        if (refresh == null) return false;
        body['refreshToken'] = refresh;
      }
      final data = Map<String, dynamic>.from(
        await request(
          '/auth/refresh',
          method: 'POST',
          body: body,
          retryAuth: false,
        ),
      );
      await acceptSession(data);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> logout() async {
    try {
      await request('/auth/logout', method: 'POST', body: {});
    } finally {
      accessToken = null;
      user = null;
      csrfToken = null;
      refreshTimer?.cancel();
      socket?.dispose();
      socket = null;
      if (!kIsWeb) await storage.delete(key: 'campus_refresh');
      notifyListeners();
    }
  }

  void connectRealtime() {
    if (!enableRealtime) return;
    socket?.dispose();
    socket = io.io('$base/campus', {
      'transports': ['websocket'],
      'autoConnect': false,
      'forceNew': true,
      'path': '/socket.io',
      'auth': {'token': accessToken},
    });
    socket!.onConnect((_) {
      for (final sessionId in attendanceSubscriptions) {
        socket!.emit('subscribe-attendance', sessionId);
      }
      realtimeConnected = true;
      revision++;
      notifyListeners();
    });
    socket!.onDisconnect((_) {
      realtimeConnected = false;
      notifyListeners();
    });
    for (final event in [
      'attendance.recorded',
      'attendance.session.opened',
      'attendance.session.closed',
      'parking.session.changed',
      'payment.changed',
      'wallet.changed',
      'canteen.order.changed',
    ]) {
      socket!.on(event, (dynamic data) {
        final eventId = data is Map ? data['eventId']?.toString() : null;
        if (eventId != null && !seenEvents.add(eventId)) return;
        if (seenEvents.length > 1000) seenEvents.clear();
        revision++;
        notifyListeners();
      });
    }
    socket!.connect();
  }

  void subscribeAttendance(String sessionId) {
    attendanceSubscriptions.add(sessionId);
    socket?.emit('subscribe-attendance', sessionId);
  }

  void changed() {
    revision++;
    notifyListeners();
  }

  @override
  void dispose() {
    refreshTimer?.cancel();
    socket?.dispose();
    client.close();
    super.dispose();
  }
}
