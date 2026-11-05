import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;

Future<String> exportReport(String name, String content) async {
  final blob = web.Blob(
    ['\ufeff$content'.toJS].toJS,
    web.BlobPropertyBag(type: 'text/csv;charset=utf-8'),
  );
  final url = web.URL.createObjectURL(blob);
  final link = web.HTMLAnchorElement()
    ..href = url
    ..download = name;
  link.click();
  Timer(const Duration(seconds: 5), () => web.URL.revokeObjectURL(url));
  return 'Đã tải báo cáo CSV.';
}
