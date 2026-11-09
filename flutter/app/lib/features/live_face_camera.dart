import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../core/campus_api.dart';

class LiveFaceCamera extends StatefulWidget {
  const LiveFaceCamera(this.api, {required this.enrolled, super.key});

  final CampusApi api;
  final bool enrolled;

  @override
  State<LiveFaceCamera> createState() => _LiveFaceCameraState();
}

class _LiveFaceCameraState extends State<LiveFaceCamera> {
  Uint8List? frame;
  Completer<void>? stopPreview;
  DateTime? lastFrame;
  String status = 'Đang chờ video trực tiếp…';
  int matches = 0;

  @override
  void initState() {
    super.initState();
    unawaited(preview());
    unawaited(recognize());
  }

  bool get frameIsLive =>
      lastFrame != null &&
      DateTime.now().difference(lastFrame!) < const Duration(seconds: 2);

  @override
  void dispose() {
    stopPreview?.complete();
    final current = frame;
    if (current != null) unawaited(MemoryImage(current).evict());
    super.dispose();
  }

  Future<void> preview() async {
    while (mounted) {
      final stop = Completer<void>();
      stopPreview = stop;
      try {
        final api = widget.api;
        final request = http.AbortableRequest(
          'GET',
          Uri.parse('${api.base}/api/v1/me/face-pilot/video'),
          abortTrigger: stop.future,
        )..headers['Authorization'] = 'Bearer ${api.accessToken}';
        final response = await api.client
            .send(request)
            .timeout(const Duration(seconds: 5));
        if (response.statusCode == 200) {
          var pending = Uint8List(0);
          await for (final chunk in response.stream.timeout(
            const Duration(seconds: 5),
          )) {
            if (!mounted) return;
            final buffer = Uint8List(pending.length + chunk.length)
              ..setRange(0, pending.length, pending)
              ..setRange(pending.length, pending.length + chunk.length, chunk);
            var offset = 0;
            Uint8List? latest;
            final bytes = ByteData.sublistView(buffer);
            while (buffer.length - offset >= 4) {
              final length = bytes.getUint32(offset);
              if (length < 4 || length > 2 * 1024 * 1024) {
                throw const FormatException('Invalid camera frame size');
              }
              if (buffer.length - offset - 4 < length) break;
              latest = Uint8List.sublistView(
                buffer,
                offset + 4,
                offset + 4 + length,
              );
              offset += 4 + length;
            }
            pending = Uint8List.sublistView(buffer, offset);
            if (latest != null) {
              final previous = frame;
              setState(() {
                frame = latest;
                lastFrame = DateTime.now();
              });
              if (previous != null) unawaited(MemoryImage(previous).evict());
            }
          }
        } else {
          await response.stream.drain<void>();
        }
      } catch (_) {
        // Reconnect after a camera or network interruption.
      } finally {
        if (!stop.isCompleted) stop.complete();
        stopPreview = null;
      }
      if (!mounted) return;
      final previous = frame;
      setState(() {
        frame = null;
        lastFrame = null;
        matches = 0;
        status = 'Đang kết nối lại camera…';
      });
      if (previous != null) unawaited(MemoryImage(previous).evict());
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  }

  Future<void> recognize() async {
    while (mounted) {
      if (widget.enrolled && frameIsLive) {
        try {
          final result = await widget.api.request(
            '/me/face-pilot',
            method: 'POST',
            body: {'action': 'verify'},
          );
          if (!mounted) return;
          setState(() {
            final matched = result['status'] == 'MATCH';
            matches = matched ? matches + 1 : 0;
            status = matches >= 2
                ? 'Đã nhận dạng · ${result['score']}'
                : matched
                ? 'Đang xác nhận lại…'
                : 'Không khớp mẫu đã đăng ký';
          });
        } on CampusFailure catch (error) {
          if (!mounted) return;
          setState(() {
            matches = 0;
            status = error.message;
          });
        } catch (_) {
          if (!mounted) return;
          setState(() {
            matches = 0;
            status = 'Đang kết nối lại để nhận dạng…';
          });
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 900));
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: AspectRatio(
          aspectRatio: 4 / 3,
          child: ColoredBox(
            color: Colors.black,
            child: frame == null
                ? const Center(child: CircularProgressIndicator())
                : Image.memory(
                    frame!,
                    gaplessPlayback: true,
                    fit: BoxFit.contain,
                  ),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Text(
        !frameIsLive
            ? 'Đang chờ video trực tiếp…'
            : widget.enrolled
            ? status
            : 'Video trực tiếp · Căn khuôn mặt trước khi chụp mẫu',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: matches >= 2 && widget.enrolled ? Colors.green.shade700 : null,
        ),
      ),
    ],
  );
}
