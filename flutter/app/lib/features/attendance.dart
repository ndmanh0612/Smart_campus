import 'package:flutter/material.dart';
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
  CampusApi get api => widget.api;
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
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionTitle(
            'Lớp học & điểm danh',
            'Giảng viên phải mở phiên đúng lớp, phòng và thiết bị trước khi Face DEMO ghi nhận.',
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
                      'Chọn camera DEMO đúng phòng',
                      [
                        FormFieldSpec(
                          'deviceId',
                          'Camera mô phỏng',
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
              actions: (s) => Row(mainAxisSize: MainAxisSize.min,
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: () {
                      setState(() => selected = s['id'] as String);
                      api.subscribeAttendance(s['id'] as String);
                    },
                    child: const Text('Theo dõi'),
                  ),
                  if (s['status'] == 'SCHEDULED')
                    ActionButton('Mở phiên', () async {
                      await api.request(
                        '/attendance/sessions/${s['id']}/open',
                        method: 'POST',
                        body: {'expectedVersion': s['version']},
                      );
                      api.subscribeAttendance(s['id'] as String);
                      if (mounted) setState(() => selected = s['id'] as String);
                      api.changed();
                    }),
                  if (s['status'] == 'OPEN')
                    ActionButton('Đóng phiên', () async {
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
              title: 'Theo dõi phiên đã chọn',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      if (current['status'] == 'OPEN')
                        ActionButton('Điểm danh Face DEMO', () async {
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
                        }, icon: Icons.face),
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
                  RecordTable(
                    data: rows(data['/attendance/sessions/$selected/records']),
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
