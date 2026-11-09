import 'dart:async';
import 'package:flutter/material.dart';
import '../core/campus_api.dart';

typedef RowData = Map<String, dynamic>;
List<RowData> rows(dynamic data) => (data as List? ?? [])
    .map((e) => Map<String, dynamic>.from(e as Map))
    .toList();
String display(dynamic value) {
  if (value == null) return '—';
  if (value is bool) return value ? 'Có' : 'Chưa';
  if (value is List) return value.map(display).join(', ');
  const labels = {
    'ACTIVE': 'Đang hoạt động',
    'PENDING_ENTRY': 'Chờ xe vào',
    'EXIT_PENDING': 'Chờ xe ra',
    'COMPLETED': 'Hoàn tất',
    'CANCELLED': 'Đã hủy',
    'EXCEPTION': 'Cần đối soát',
    'OPEN': 'Đang mở',
    'CLOSED': 'Đã đóng',
    'SCHEDULED': 'Chưa mở',
    'PRESENT': 'Có mặt',
    'LATE': 'Đi muộn',
    'ABSENT': 'Vắng',
    'EXCUSED': 'Có phép',
    'AWAITING_PAYMENT': 'Chờ thanh toán',
    'AWAITING_CONFIRMATION': 'Chờ sinh viên xác nhận',
    'AUTHORIZED': 'Đã giữ point',
    'CAPTURED': 'Đã thu point',
    'VOIDED': 'Đã hủy giữ point',
    'PENDING': 'Đang chờ',
    'SUCCEEDED': 'Thành công',
    'FAILED': 'Thất bại',
    'EXPIRED': 'Hết hạn',
    'LOST': 'Báo mất',
    'REVOKED': 'Thu hồi',
    'LOCKED': 'Tạm khóa',
    'DISABLED': 'Ngừng hoạt động',
    'QUEUED': 'Chờ gửi lệnh',
    'OPENED': 'Đã mở mô phỏng',
    'UNKNOWN': 'Chưa rõ trạng thái',
    'PASSAGE_CONFIRMED': 'Xe đã qua',
    'STUDENT': 'Sinh viên',
    'ADMIN': 'Quản trị',
    'LECTURER': 'Giảng viên',
    'PARKING_STAFF': 'Nhân viên bãi xe',
    'CANTEEN_STAFF': 'Nhân viên cantin',
    'REAL': 'THẬT',
    'DEMO': 'MÔ PHỎNG',
    'MOCK': 'MÔ PHỎNG THANH TOÁN',
    'SIMULATOR': 'CỔNG MÔ PHỎNG',
  };
  final text = value.toString();
  if (labels.containsKey(text)) return labels[text]!;
  if (RegExp(r'^\d{4}-\d\d-\d\dT').hasMatch(text)) {
    final time = DateTime.tryParse(text)?.toLocal();
    if (time != null) {
      return '${time.day.toString().padLeft(2, '0')}/${time.month.toString().padLeft(2, '0')} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    }
  }
  return text;
}

String pointText(dynamic value) {
  final text = value?.toString() ?? '0';
  return '${text.replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')} point';
}

class SectionTitle extends StatelessWidget {
  final String title, subtitle;
  const SectionTitle(this.title, this.subtitle, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(color: const Color(0xff64748b)),
        ),
      ],
    ),
  );
}

class Surface extends StatelessWidget {
  final Widget child;
  final String? title;
  const Surface({required this.child, this.title, super.key});
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 20),
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: const BorderSide(color: Color(0xffe2e8f0)),
    ),
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(
              title!,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 18),
          ],
          child,
        ],
      ),
    ),
  );
}

class ModeLabels extends StatelessWidget {
  const ModeLabels({super.key});
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 6,
    children: const [
      Chip(avatar: Icon(Icons.nfc, size: 16), label: Text('RFID THẬT')),
      Chip(label: Text('FACE / OCR DEMO')),
      Chip(label: Text('NẠP POINT MOCK')),
      Chip(label: Text('CỔNG MÔ PHỎNG')),
    ],
  );
}

class DataPanel extends StatefulWidget {
  final CampusApi api;
  final List<String> paths;
  final Widget Function(BuildContext, Map<String, dynamic>) builder;
  const DataPanel({
    required this.api,
    required this.paths,
    required this.builder,
    super.key,
  });
  @override
  State<DataPanel> createState() => _DataPanelState();
}

class _DataPanelState extends State<DataPanel> {
  Map<String, dynamic>? data;
  String? error;
  bool loading = false;
  Timer? timer;
  int revision = -1;
  @override
  void initState() {
    super.initState();
    widget.api.addListener(changed);
    timer = Timer.periodic(const Duration(seconds: 8), (_) => load());
    unawaited(load());
  }

  void changed() {
    if (revision != widget.api.revision) {
      revision = widget.api.revision;
      unawaited(load());
    }
  }

  Future<void> load() async {
    if (loading) return;
    loading = true;
    try {
      final results = await Future.wait(
        widget.paths.map((p) => widget.api.request(p)),
      );
      if (mounted) {
        setState(() {
          data = Map.fromIterables(widget.paths, results);
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      loading = false;
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    widget.api.removeListener(changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (error != null)
        Surface(
          child: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.red),
              const SizedBox(width: 12),
              Expanded(child: Text(error!)),
              TextButton(onPressed: load, child: const Text('Thử lại')),
            ],
          ),
        ),
      if (data == null && error == null)
        const Padding(
          padding: EdgeInsets.all(48),
          child: Center(child: CircularProgressIndicator()),
        ),
      if (data != null) widget.builder(context, data!),
    ],
  );
}

class RecordTable extends StatelessWidget {
  final List<RowData> data;
  final Map<String, String> columns;
  final Widget Function(RowData)? actions;
  const RecordTable({
    required this.data,
    required this.columns,
    this.actions,
    super.key,
  });
  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Text('Chưa có dữ liệu.'),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        dataRowMinHeight: 44,
        dataRowMaxHeight: double.infinity,
        headingRowColor: const WidgetStatePropertyAll(Color(0xfff1f5f9)),
        columns: [
          ...columns.values.map((v) => DataColumn(label: Text(v))),
          if (actions != null) const DataColumn(label: Text('Thao tác')),
        ],
        rows: data
            .map(
              (row) => DataRow(
                cells: [
                  ...columns.keys.map(
                    (k) => DataCell(
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 260),
                        child: Text(
                          display(row[k]),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                  if (actions != null) DataCell(Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: actions!(row))),
                ],
              ),
            )
            .toList(),
      ),
    );
  }
}

class ActionButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final Future<void> Function()? action;
  final bool outlined;
  const ActionButton(
    this.label,
    this.action, {
    this.icon,
    this.outlined = false,
    super.key,
  });
  @override
  State<ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<ActionButton> {
  bool busy = false;
  Future<void> run() async {
    if (busy || widget.action == null) return;
    setState(() => busy = true);
    try {
      await widget.action!();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: const Color(0xff991b1b),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final icon = busy
        ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(widget.icon ?? Icons.arrow_forward, size: 18);
    return widget.outlined
        ? OutlinedButton.icon(
            onPressed: widget.action == null || busy ? null : run,
            icon: icon,
            label: Text(widget.label),
            style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
          )
        : FilledButton.icon(
            onPressed: widget.action == null || busy ? null : run,
            icon: icon,
            label: Text(widget.label),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xff0f766e), visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
          );
  }
}

class FormFieldSpec {
  final String keyName, label, kind;
  final String? initial;
  final Map<String, String>? options;
  final bool required;
  const FormFieldSpec(
    this.keyName,
    this.label, {
    this.kind = 'text',
    this.initial,
    this.options,
    this.required = true,
  });
}

Future<RowData?> formDialog(
  BuildContext context,
  String title,
  List<FormFieldSpec> specs,
) {
  return showDialog<RowData>(
    context: context,
    builder: (context) {
      final form = GlobalKey<FormState>();
      final controllers = {
        for (final s in specs)
          s.keyName: TextEditingController(text: s.initial ?? ''),
      };
      final selections = {
        for (final s in specs)
          if (s.options != null)
            s.keyName:
                s.initial ??
                (s.options!.isEmpty ? null : s.options!.keys.first),
      };
      return StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Form(
                key: form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: specs
                      .map(
                        (s) => Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: s.options != null
                              ? DropdownButtonFormField<String>(
                                  initialValue: selections[s.keyName],
                                  isExpanded: true,
                                  decoration: InputDecoration(
                                    labelText: s.label,
                                  ),
                                  items: s.options!.entries
                                      .map(
                                        (e) => DropdownMenuItem(
                                          value: e.key,
                                          child: Text(
                                            e.value,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (v) =>
                                      setState(() => selections[s.keyName] = v),
                                  validator: (v) => s.required && v == null
                                      ? 'Cần chọn một giá trị'
                                      : null,
                                )
                              : TextFormField(
                                  controller: controllers[s.keyName],
                                  decoration: InputDecoration(
                                    labelText: s.label,
                                  ),
                                  obscureText: s.kind == 'password',
                                  maxLines: s.kind == 'multiline' ? 3 : 1,
                                  keyboardType:
                                      s.kind == 'integer' || s.kind == 'points'
                                      ? TextInputType.number
                                      : TextInputType.text,
                                  validator: (v) {
                                    if (s.required &&
                                        (v == null || v.trim().isEmpty)) {
                                      return 'Không được bỏ trống';
                                    }
                                    if (s.kind == 'integer' &&
                                        int.tryParse(v ?? '') == null) {
                                      return 'Cần nhập số nguyên';
                                    }
                                    if (s.kind == 'points' &&
                                        !RegExp(r'^-?\d+$').hasMatch(v ?? '')) {
                                      return 'Cần nhập số point nguyên';
                                    }
                                    return null;
                                  },
                                ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Đóng'),
            ),
            FilledButton(
              onPressed: () {
                if (!form.currentState!.validate()) return;
                final result = <String, dynamic>{};
                for (final s in specs) {
                  final text = controllers[s.keyName]!.text.trim();
                  final value = s.options != null
                      ? selections[s.keyName]
                      : s.kind == 'integer'
                      ? int.parse(text)
                      : text;
                  if (s.required ||
                      value != null && value.toString().isNotEmpty) {
                    result[s.keyName] = value;
                  }
                }
                Navigator.pop(context, result);
              },
              child: const Text('Xác nhận'),
            ),
          ],
        ),
      );
    },
  );
}

Future<void> submitForm(
  BuildContext context,
  CampusApi api,
  String title,
  String path,
  List<FormFieldSpec> specs, {
  String method = 'POST',
  RowData extra = const {},
}) async {
  final data = await formDialog(context, title, specs);
  if (data == null) return;
  await api.request(path, method: method, body: {...data, ...extra});
  api.changed();
}

Map<String, String> options(
  List<RowData> data,
  String label, {
  String key = 'id',
}) => {for (final r in data) r[key].toString(): display(r[label])};
void success(BuildContext context, String message) => ScaffoldMessenger.of(
  context,
).showSnackBar(SnackBar(content: Text(message)));

void error(BuildContext context, String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: const Color(0xff991b1b)));
