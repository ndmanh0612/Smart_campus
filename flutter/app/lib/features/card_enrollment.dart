import 'package:flutter/material.dart';
import '../core/campus_api.dart';
import 'shared.dart';
import 'enrollment_wizard.dart';

class CardEnrollmentPage extends StatelessWidget {
  final CampusApi api;
  const CardEnrollmentPage(this.api, {super.key});

  @override
  Widget build(BuildContext context) => DataPanel(
    api: api,
    paths: const [
      '/admin/users',
      '/admin/devices',
      '/admin/rfid-cards',
      '/simulator/events',
    ],
    builder: (context, data) {
      final students = rows(
        data['/admin/users'],
      ).where((row) => row['studentId'] != null && row['active'] != false);
      final readers = rows(data['/admin/devices'])
          .where((row) => row['kind'] == 'RFID_READER' && row['active'] == true)
          .toList();
      final events = data['/simulator/events'] as Map;
      final active = rows(
        events['contexts'],
      ).where((row) => row['purpose'] == 'ENROLLMENT');
      final identities = rows(events['identities']);
      final cards = rows(data['/admin/rfid-cards']);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionTitle(
            'Đăng ký thẻ RFID',
            'Chọn sinh viên, áp thẻ thật vào đầu đọc, rồi xác nhận cấp hoặc thay thẻ.',
          ),
          Surface(
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                ActionButton(
                  'Đăng ký sinh viên trọn gói',
                  () => showEnrollStudentWizardDialog(context, api),
                  icon: Icons.how_to_reg,
                ),
                ActionButton('Cấp / Đổi thẻ từ đầu đọc', () async {
                final form = await formDialog(context, 'Đăng ký thẻ RFID', [
                  FormFieldSpec(
                    'studentId',
                    'Sinh viên',
                    options: {
                      for (final student in students)
                        student['studentId'].toString():
                            '${student['studentCode']} • ${student['name']}',
                    },
                  ),
                  FormFieldSpec(
                    'deviceId',
                    'Đầu đọc',
                    options: options(readers, 'name'),
                  ),
                ]);
                if (form == null) return;
                final reader = readers.firstWhere(
                  (row) => row['id'] == form['deviceId'],
                );
                if (reader['role'] != 'RFID_ENROLLMENT') {
                  await api.request(
                    '/admin/devices/${reader['id']}/role',
                    method: 'PUT',
                    body: {
                      'role': 'RFID_ENROLLMENT',
                      'expectedVersion': reader['configVersion'],
                      'reason': 'Đăng ký thẻ RFID cho sinh viên',
                    },
                  );
                }
                for (var attempt = 0; attempt < 8; attempt++) {
                  final current = rows(
                    await api.request('/admin/devices'),
                  ).firstWhere((row) => row['id'] == reader['id']);
                  if (current['role'] == 'RFID_ENROLLMENT' &&
                      current['ackVersion'] == current['configVersion']) {
                    await api.request(
                      '/enrollment-contexts',
                      method: 'POST',
                      body: form,
                    );
                    api.changed();
                    return;
                  }
                  await Future<void>.delayed(const Duration(milliseconds: 500));
                }
                throw CampusFailure(
                  'DEVICE_NOT_READY',
                  'Đầu đọc chưa xác nhận cấu hình. Kiểm tra cầu nối USB.',
                  409,
                );
              }, icon: Icons.nfc),
              ],
            ),
          ),
          for (final registration in active)
            Builder(
              builder: (context) {
                final studentId = registration['enrollmentStudentId'];
                final student = students
                    .where((row) => row['studentId'] == studentId)
                    .firstOrNull;
                final scan = identities
                    .where(
                      (row) =>
                          row['contextId'] == registration['id'] &&
                          row['source'] == 'REAL' &&
                          row['consumedAt'] == null,
                    )
                    .firstOrNull;
                final oldCard = cards
                    .where(
                      (row) =>
                          row['studentId'] == studentId &&
                          row['status'] == 'ACTIVE',
                    )
                    .firstOrNull;
                return Surface(
                  title: student?['name']?.toString() ?? 'Phiên đăng ký thẻ',
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(scan == null ? 'Đang chờ áp thẻ.' : 'Đã đọc thẻ.'),
                      if (scan != null)
                        ActionButton(
                          oldCard == null
                              ? 'Xác nhận cấp thẻ'
                              : 'Xác nhận thay thẻ',
                          () async {
                            await api.request(
                              '/rfid-cards',
                              method: 'POST',
                              body: {
                                'studentId': studentId,
                                'enrollmentAssertionId': scan['id'],
                                if (oldCard != null)
                                  'replaceCardId': oldCard['id'],
                              },
                            );
                            api.changed();
                            if (context.mounted) {
                              success(context, 'Đã đăng ký thẻ RFID.');
                            }
                          },
                        ),
                      ActionButton('Hủy phiên', () async {
                        await api.request(
                          '/device-contexts/${registration['id']}/cancel',
                          method: 'POST',
                          body: {
                            'reason': 'Quản trị viên hủy phiên đăng ký thẻ',
                          },
                        );
                        api.changed();
                      }, outlined: true),
                    ],
                  ),
                );
              },
            ),
          Surface(
            title: 'Thẻ đã đăng ký',
            child: RecordTable(
              data: cards,
              columns: const {
                'studentCode': 'Mã sinh viên',
                'studentName': 'Họ và tên',
                'status': 'Trạng thái',
                'expiresAt': 'Hết hạn',
              },
            ),
          ),
        ],
      );
    },
  );
}
