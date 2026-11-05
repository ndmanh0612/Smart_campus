import 'package:flutter/services.dart';

Future<String> exportReport(String name, String content) async {
  await Clipboard.setData(ClipboardData(text: content));
  return 'Đã sao chép nội dung CSV. Có thể dán vào bảng tính hoặc tệp CSV.';
}
