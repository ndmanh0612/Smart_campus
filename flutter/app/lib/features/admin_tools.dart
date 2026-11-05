import 'package:flutter/material.dart';
import '../core/campus_api.dart';
import 'shared.dart';

class AdminToolsPage extends StatelessWidget {
  final CampusApi api;
  const AdminToolsPage(this.api, {super.key});
  @override
  Widget build(BuildContext context) => DataPanel(
    api: api,
    paths: const [
      '/admin/settings',
      '/admin/users',
      '/admin/vehicles',
      '/parking/lots',
      '/admin/rfid-cards',
      '/admin/devices',
      '/admin/class-sections',
    ],
    builder: (context, data) {
      final users = rows(data['/admin/users']),
          students = users.where((u) => u['studentId'] != null).toList(),
          lecturers = users.where((u) => u['lecturerId'] != null).toList();
      final settings = data['/admin/settings'] as Map;
      final limits = rows(
        settings['settings'],
      ).firstWhere((s) => s['key'] == 'wallet_limits');
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionTitle(
            'Cấu hình & phân quyền',
            'Thay đổi có lý do và audit; biểu phí hoặc tỷ lệ mới không làm thay đổi giao dịch đã ghi sổ.',
          ),
          Surface(
            title: 'Ví point thử nghiệm',
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                ActionButton(
                  'Hạn mức giao dịch',
                  () => submitForm(
                    context,
                    api,
                    'Hạn mức ví',
                    '/admin/settings/wallet-limits',
                    [
                      FormFieldSpec(
                        'transactionPoints',
                        'Tối đa point/giao dịch',
                        kind: 'points',
                        initial: limits['value']['transactionPoints']
                            .toString(),
                      ),
                      FormFieldSpec(
                        'dailyPoints',
                        'Tối đa point/ngày',
                        kind: 'points',
                        initial: limits['value']['dailyPoints'].toString(),
                      ),
                      const FormFieldSpec(
                        'reason',
                        'Lý do thay đổi',
                        kind: 'multiline',
                      ),
                    ],
                    method: 'PUT',
                    extra: {'expectedVersion': limits['version']},
                  ),
                  icon: Icons.tune,
                ),
                ActionButton(
                  'Tỷ lệ point / VND',
                  () => submitForm(
                    context,
                    api,
                    'Đổi tỷ lệ cho lần nạp sau',
                    '/admin/settings/point-conversion',
                    const [
                      FormFieldSpec('version', 'Tên phiên bản mới'),
                      FormFieldSpec(
                        'pointsPerVnd',
                        'Số point trên 1 VND thử nghiệm',
                        kind: 'integer',
                        initial: '1',
                      ),
                      FormFieldSpec(
                        'reason',
                        'Lý do thay đổi',
                        kind: 'multiline',
                      ),
                    ],
                    method: 'PUT',
                  ),
                  outlined: true,
                ),
              ],
            ),
          ),
          Surface(
            title: 'Phân quyền và phân công',
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                ActionButton('Đổi vai trò chính', () async {
                  final f = await formDialog(
                    context,
                    'Thay toàn bộ vai trò hiện tại bằng vai trò đã chọn',
                    [
                      FormFieldSpec(
                        'userId',
                        'Tài khoản',
                        options: options(users, 'email'),
                      ),
                      const FormFieldSpec(
                        'role',
                        'Vai trò mới',
                        options: {
                          'ADMIN': 'Quản trị',
                          'STUDENT': 'Sinh viên (cần hồ sơ)',
                          'LECTURER': 'Giảng viên (cần hồ sơ)',
                          'PARKING_STAFF': 'Nhân viên bãi xe',
                          'CANTEEN_STAFF': 'Nhân viên cantin',
                        },
                      ),
                      const FormFieldSpec('reason', 'Lý do', kind: 'multiline'),
                    ],
                  );
                  if (f == null) return;
                  await api.request(
                    '/admin/users/${f['userId']}/roles',
                    method: 'PUT',
                    body: {
                      'roles': [f['role']],
                      'reason': f['reason'],
                    },
                  );
                  api.changed();
                }, icon: Icons.badge_outlined),
                ActionButton('Phân công giảng viên', () async {
                  final f = await formDialog(
                    context,
                    'Giao lớp cho giảng viên',
                    [
                      FormFieldSpec(
                        'sectionId',
                        'Lớp học phần',
                        options: options(
                          rows(data['/admin/class-sections']),
                          'code',
                        ),
                      ),
                      FormFieldSpec(
                        'lecturerId',
                        'Giảng viên',
                        options: {
                          for (final l in lecturers)
                            l['lecturerId'].toString(): l['name'].toString(),
                        },
                      ),
                    ],
                  );
                  if (f == null) return;
                  await api.request(
                    '/admin/class-sections/${f['sectionId']}/teaching-assignments',
                    method: 'POST',
                    body: {'lecturerId': f['lecturerId']},
                  );
                  api.changed();
                }, outlined: true),
              ],
            ),
          ),
          Surface(
            title: 'Vé tháng / miễn giảm gửi xe',
            child: ActionButton('Cấp vé hoặc mức giảm', () async {
              final f = await formDialog(
                context,
                'Quyền miễn giảm có thời hạn',
                [
                  FormFieldSpec(
                    'studentId',
                    'Sinh viên',
                    options: {
                      for (final s in students)
                        s['studentId'].toString():
                            '${s['studentCode']} • ${s['name']}',
                    },
                  ),
                  FormFieldSpec(
                    'vehicleId',
                    'Xe đã đăng ký',
                    options: options(rows(data['/admin/vehicles']), 'rawPlate'),
                  ),
                  FormFieldSpec(
                    'lotId',
                    'Bãi xe',
                    options: options(rows(data['/parking/lots']), 'name'),
                  ),
                  FormFieldSpec(
                    'validFrom',
                    'Hiệu lực từ',
                    initial: DateTime.now().toUtc().toIso8601String(),
                  ),
                  FormFieldSpec(
                    'validTo',
                    'Hết hiệu lực',
                    initial: DateTime.now()
                        .add(const Duration(days: 30))
                        .toUtc()
                        .toIso8601String(),
                  ),
                  const FormFieldSpec(
                    'discountPercent',
                    'Phần trăm giảm (100 = miễn toàn bộ)',
                    kind: 'integer',
                    initial: '100',
                  ),
                  const FormFieldSpec(
                    'reason',
                    'Lý do / loại vé',
                    kind: 'multiline',
                  ),
                ],
              );
              if (f == null) return;
              final percent = f.remove('discountPercent') as int;
              await api.request(
                '/admin/parking-passes',
                method: 'POST',
                body: {...f, 'discountBps': percent * 100},
              );
              api.changed();
            }, icon: Icons.confirmation_number_outlined),
          ),
          Surface(
            title: 'Quản lý thẻ RFID',
            child: RecordTable(
              data: rows(data['/admin/rfid-cards']),
              columns: const {
                'studentCode': 'Sinh viên',
                'status': 'Trạng thái',
                'expiresAt': 'Hết hạn',
              },
              actions: (c) => c['status'] == 'ACTIVE'
                  ? ActionButton(
                      'Thu hồi',
                      () => submitForm(
                        context,
                        api,
                        'Thu hồi thẻ',
                        '/rfid-cards/${c['id']}/revoke',
                        const [
                          FormFieldSpec('reason', 'Lý do', kind: 'multiline'),
                        ],
                      ),
                      outlined: true,
                    )
                  : const Text('—'),
            ),
          ),
          Surface(
            title: 'Khóa / mở thiết bị',
            child: RecordTable(
              data: rows(data['/admin/devices']),
              columns: const {
                'name': 'Tên thiết bị',
                'active': 'Đang hoạt động',
                'role': 'Vai trò',
              },
              actions: (d) => ActionButton(
                d['active'] == true ? 'Khóa' : 'Mở lại',
                () => submitForm(
                  context,
                  api,
                  'Thay đổi trạng thái thiết bị',
                  '/admin/devices/${d['id']}/status',
                  const [FormFieldSpec('reason', 'Lý do', kind: 'multiline')],
                  extra: {'active': d['active'] != true},
                ),
                outlined: true,
              ),
            ),
          ),
        ],
      );
    },
  );
}

class ReportsPage extends StatelessWidget {
  final CampusApi api;
  const ReportsPage(this.api, {super.key});
  @override
  Widget build(BuildContext context) => DataPanel(
    api: api,
    paths: const ['/admin/reports'],
    builder: (context, data) {
      final r = data['/admin/reports'] as Map;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionTitle(
            'Báo cáo vận hành',
            'Thống kê point trong DB thử nghiệm. Doanh thu ròng đã trừ REFUND/REVERSAL; không phải báo cáo tiền thật.',
          ),
          Surface(
            title: 'Point thu ròng theo ngày',
            child: RecordTable(
              data: rows(r['revenue']),
              columns: const {
                'day': 'Ngày',
                'service': 'Dịch vụ',
                'netPoints': 'Point ròng',
              },
            ),
          ),
          Surface(
            title: 'Trạng thái gửi xe',
            child: RecordTable(
              data: rows(r['parking']),
              columns: const {'status': 'Trạng thái', 'count': 'Số lượt'},
            ),
          ),
          Surface(
            title: 'Kết quả điểm danh',
            child: RecordTable(
              data: rows(r['attendance']),
              columns: const {'status': 'Kết quả', 'count': 'Số bản ghi'},
            ),
          ),
          Surface(
            title: 'Hàng đợi thông báo',
            child: Text(
              'Đang chờ: ${r['outbox']['pending']} • Cần xử lý lỗi: ${r['outbox']['deadLetter']}',
            ),
          ),
        ],
      );
    },
  );
}
