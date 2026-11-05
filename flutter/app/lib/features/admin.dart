import 'package:flutter/material.dart';
import '../core/campus_api.dart';
import 'shared.dart';

class AdminPage extends StatelessWidget {
  final CampusApi api;
  const AdminPage(this.api, {super.key});
  @override
  Widget build(BuildContext context) => DataPanel(
    api: api,
    paths: const [
      '/admin/users',
      '/admin/devices',
      '/admin/vehicles',
      '/admin/parking-fee-policies',
      '/parking/lots',
      '/admin/wallet-reconciliation',
      '/admin/roles',
    ],
    builder: (context, data) {
      final users = rows(data['/admin/users']),
          students = users.where((u) => u['studentId'] != null).toList(),
          devices = rows(data['/admin/devices']);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionTitle(
            'Quản trị hệ thống',
            'Quản lý tài khoản, RFID, thiết bị, chính sách và đối soát point thử nghiệm.',
          ),
          Surface(
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                ActionButton(
                  'Thêm tài khoản',
                  () => submitForm(
                    context,
                    api,
                    'Tài khoản mới',
                    '/admin/users',
                    const [
                      FormFieldSpec('email', 'Email'),
                      FormFieldSpec('name', 'Họ tên'),
                      FormFieldSpec(
                        'password',
                        'Mật khẩu, tối thiểu 12 ký tự',
                        kind: 'password',
                      ),
                      FormFieldSpec(
                        'role',
                        'Vai trò',
                        options: {
                          'STUDENT': 'Sinh viên',
                          'LECTURER': 'Giảng viên',
                          'PARKING_STAFF': 'Nhân viên bãi xe',
                          'CANTEEN_STAFF': 'Nhân viên cantin',
                        },
                      ),
                      FormFieldSpec(
                        'code',
                        'Mã sinh viên / giảng viên / nhân viên',
                      ),
                    ],
                  ),
                  icon: Icons.person_add_alt,
                ),
                ActionButton(
                  'Điều chỉnh point',
                  () => submitForm(
                    context,
                    api,
                    'Điều chỉnh point có audit',
                    '/admin/wallet-adjustments',
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
                      const FormFieldSpec(
                        'deltaPoints',
                        'Point tăng hoặc giảm',
                        kind: 'points',
                      ),
                      const FormFieldSpec('reason', 'Lý do', kind: 'multiline'),
                    ],
                  ),
                  outlined: true,
                ),
                ActionButton(
                  'Chuẩn bị cấp RFID thật',
                  () => submitForm(
                    context,
                    api,
                    'Bước 1: chọn sinh viên và reader RFID_ENROLLMENT',
                    '/enrollment-contexts',
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
                        'deviceId',
                        'Đầu đọc thật',
                        options: options(
                          devices
                              .where(
                                (d) =>
                                    d['kind'] == 'RFID_READER' &&
                                    d['role'] == 'RFID_ENROLLMENT',
                              )
                              .toList(),
                          'name',
                        ),
                      ),
                    ],
                  ),
                  outlined: true,
                ),
              ],
            ),
          ),
          Surface(
            title: 'Tài khoản',
            child: RecordTable(
              data: users,
              columns: const {
                'name': 'Họ tên',
                'email': 'Email',
                'roles': 'Vai trò',
                'status': 'Trạng thái',
              },
              actions: (u) => ActionButton(
                'Trạng thái',
                () => submitForm(
                  context,
                  api,
                  'Trạng thái tài khoản',
                  '/admin/users/${u['id']}/status',
                  const [
                    FormFieldSpec(
                      'status',
                      'Trạng thái',
                      options: {
                        'ACTIVE': 'Hoạt động',
                        'LOCKED': 'Tạm khóa',
                        'DISABLED': 'Ngừng hoạt động',
                      },
                    ),
                    FormFieldSpec('reason', 'Lý do', kind: 'multiline'),
                  ],
                ),
                outlined: true,
              ),
            ),
          ),
          Surface(
            title: 'Thiết bị',
            child: RecordTable(
              data: devices,
              columns: const {
                'name': 'Tên thiết bị',
                'kind': 'Loại',
                'role': 'Vai trò',
                'configVersion': 'Phiên bản',
                'ackVersion': 'Đã xác nhận',
                'lastSeenAt': 'Liên hệ gần nhất',
              },
              actions: (d) => d['kind'] == 'RFID_READER'
                  ? ActionButton(
                      'Đổi vai trò',
                      () => submitForm(
                        context,
                        api,
                        'Đổi vai trò; ESP32 sẽ nhận và ACK cấu hình',
                        '/admin/devices/${d['id']}/role',
                        const [
                          FormFieldSpec(
                            'role',
                            'Vai trò mới',
                            options: {
                              'RFID_ENROLLMENT': 'Cấp thẻ',
                              'PARKING_ENTRY': 'Cổng vào bãi',
                              'PARKING_EXIT': 'Cổng ra bãi',
                              'CANTEEN_POS': 'POS cantin',
                            },
                          ),
                          FormFieldSpec('reason', 'Lý do', kind: 'multiline'),
                        ],
                        method: 'PUT',
                        extra: {'expectedVersion': d['configVersion']},
                      ),
                      outlined: true,
                    )
                  : const Text('Thiết bị DEMO'),
            ),
          ),
          Surface(
            title: 'Phương tiện chờ / đã duyệt',
            child: RecordTable(
              data: rows(data['/admin/vehicles']),
              columns: const {
                'rawPlate': 'Biển số',
                'vehicleType': 'Loại xe',
                'authorized': 'Được phép',
              },
              actions: (v) => ActionButton(
                'Duyệt quyền',
                () => submitForm(
                  context,
                  api,
                  'Xác nhận quyền dùng xe',
                  '/vehicle-authorizations',
                  const [
                    FormFieldSpec(
                      'reason',
                      'Căn cứ xác minh',
                      kind: 'multiline',
                    ),
                  ],
                  extra: {'vehicleId': v['id'], 'studentId': v['studentId']},
                ),
                outlined: true,
              ),
            ),
          ),
          Surface(
            title: 'Biểu phí gửi xe',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ActionButton(
                  'Tạo phiên bản phí',
                  () => submitForm(
                    context,
                    api,
                    'Biểu phí mới',
                    '/admin/parking-fee-policies',
                    [
                      FormFieldSpec(
                        'lotId',
                        'Bãi xe',
                        options: options(rows(data['/parking/lots']), 'name'),
                      ),
                      const FormFieldSpec('version', 'Tên phiên bản'),
                      const FormFieldSpec(
                        'mode',
                        'Cách tính',
                        options: {
                          'PER_VISIT': 'Theo lượt',
                          'PER_HOUR': 'Theo giờ, làm tròn lên',
                          'PER_DAY': 'Theo block 24 giờ',
                        },
                      ),
                      const FormFieldSpec(
                        'unitPoints',
                        'Point mỗi đơn vị',
                        kind: 'points',
                      ),
                      const FormFieldSpec(
                        'graceMinutes',
                        'Phút miễn đầu lượt',
                        kind: 'integer',
                        initial: '0',
                      ),
                      const FormFieldSpec(
                        'dailyCap',
                        'Trần mỗi block 24 giờ (không bắt buộc)',
                        kind: 'points',
                        required: false,
                      ),
                    ],
                  ),
                  icon: Icons.add,
                ),
                const SizedBox(height: 16),
                RecordTable(
                  data: rows(data['/admin/parking-fee-policies']),
                  columns: const {
                    'version': 'Phiên bản',
                    'mode': 'Cách tính',
                    'unitPoints': 'Phí point',
                    'graceMinutes': 'Phút miễn',
                    'active': 'Đang áp dụng',
                  },
                  actions: (p) => p['active'] == true
                      ? const Text('Đang áp dụng')
                      : ActionButton('Kích hoạt', () async {
                          await api.request(
                            '/admin/parking-fee-policies/${p['id']}/activate',
                            method: 'POST',
                            body: {},
                          );
                          api.changed();
                        }, outlined: true),
                ),
              ],
            ),
          ),
          Surface(
            title: 'Đối soát sổ cái',
            child: rows(data['/admin/wallet-reconciliation']).isEmpty
                ? const Row(
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        color: Color(0xff0f766e),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Số dư cache khớp tổng ledger tại thời điểm kiểm tra.',
                        ),
                      ),
                    ],
                  )
                : RecordTable(
                    data: rows(data['/admin/wallet-reconciliation']),
                    columns: const {
                      'kind': 'Tài khoản',
                      'balancePoints': 'Cache',
                      'ledgerPoints': 'Ledger',
                    },
                  ),
          ),
        ],
      );
    },
  );
}

class AcademicAdminPage extends StatelessWidget {
  final CampusApi api;
  const AcademicAdminPage(this.api, {super.key});
  @override
  Widget build(BuildContext context) => DataPanel(
    api: api,
    paths: const [
      '/admin/academic-terms',
      '/admin/courses',
      '/admin/classrooms',
      '/admin/class-sections',
      '/admin/schedules',
      '/admin/users',
    ],
    builder: (context, data) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle(
          'Quản lý học vụ',
          'Tạo kỳ học, môn, lớp, phòng và từng buổi học. Giảng viên chỉ thao tác lớp được phân công.',
        ),
        Surface(
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              ActionButton(
                'Thêm kỳ học',
                () => submitForm(
                  context,
                  api,
                  'Kỳ học mới',
                  '/admin/academic-terms',
                  const [
                    FormFieldSpec('code', 'Mã kỳ học'),
                    FormFieldSpec('startsAt', 'Bắt đầu (YYYY-MM-DD)'),
                    FormFieldSpec('endsAt', 'Kết thúc (YYYY-MM-DD)'),
                  ],
                ),
                outlined: true,
              ),
              ActionButton(
                'Thêm môn',
                () => submitForm(
                  context,
                  api,
                  'Môn học',
                  '/admin/courses',
                  const [
                    FormFieldSpec('code', 'Mã môn'),
                    FormFieldSpec('name', 'Tên môn'),
                  ],
                ),
                outlined: true,
              ),
              ActionButton(
                'Thêm phòng',
                () => submitForm(
                  context,
                  api,
                  'Phòng học',
                  '/admin/classrooms',
                  const [
                    FormFieldSpec('code', 'Mã phòng'),
                    FormFieldSpec('name', 'Tên phòng'),
                  ],
                ),
                outlined: true,
              ),
              ActionButton(
                'Thêm lớp',
                () => submitForm(
                  context,
                  api,
                  'Lớp học phần',
                  '/admin/class-sections',
                  [
                    FormFieldSpec(
                      'termId',
                      'Học kỳ',
                      options: options(
                        rows(data['/admin/academic-terms']),
                        'code',
                      ),
                    ),
                    FormFieldSpec(
                      'courseId',
                      'Môn học',
                      options: options(rows(data['/admin/courses']), 'name'),
                    ),
                    const FormFieldSpec('code', 'Mã lớp'),
                  ],
                ),
                icon: Icons.add,
              ),
              ActionButton(
                'Thêm lịch',
                () => submitForm(context, api, 'Buổi học', '/admin/schedules', [
                  FormFieldSpec(
                    'sectionId',
                    'Lớp',
                    options: options(
                      rows(data['/admin/class-sections']),
                      'code',
                    ),
                  ),
                  FormFieldSpec(
                    'classroomId',
                    'Phòng',
                    options: options(rows(data['/admin/classrooms']), 'name'),
                  ),
                  const FormFieldSpec(
                    'startsAt',
                    'Bắt đầu (ví dụ 2026-11-05T07:00:00+07:00)',
                  ),
                  const FormFieldSpec('endsAt', 'Kết thúc (có múi giờ)'),
                ]),
                outlined: true,
              ),
            ],
          ),
        ),
        Surface(
          title: 'Lớp học phần',
          child: RecordTable(
            data: rows(data['/admin/class-sections']),
            columns: const {'code': 'Mã lớp'},
            actions: (s) => ActionButton(
              'Ghi danh',
              () => submitForm(
                context,
                api,
                'Đăng ký sinh viên vào lớp',
                '/admin/class-sections/${s['id']}/enrollments',
                [
                  FormFieldSpec(
                    'studentId',
                    'Sinh viên',
                    options: {
                      for (final u in rows(
                        data['/admin/users'],
                      ).where((u) => u['studentId'] != null))
                        u['studentId'].toString(): u['name'].toString(),
                    },
                  ),
                ],
              ),
              outlined: true,
            ),
          ),
        ),
        Surface(
          title: 'Lịch học',
          child: RecordTable(
            data: rows(data['/admin/schedules']),
            columns: const {'startsAt': 'Bắt đầu', 'endsAt': 'Kết thúc'},
          ),
        ),
      ],
    ),
  );
}

class AuditPage extends StatelessWidget {
  final CampusApi api;
  const AuditPage(this.api, {super.key});
  @override
  Widget build(BuildContext context) => DataPanel(
    api: api,
    paths: const ['/admin/audit-logs'],
    builder: (context, data) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle(
          'Nhật ký kiểm toán',
          'Mọi thao tác nhạy cảm có người thực hiện, thời gian và lý do. Ledger và audit không được sửa trực tiếp.',
        ),
        Surface(
          child: RecordTable(
            data: rows(data['/admin/audit-logs']),
            columns: const {
              'action': 'Thao tác',
              'reason': 'Lý do',
              'createdAt': 'Thời gian',
              'resourceId': 'Đối tượng',
            },
          ),
        ),
      ],
    ),
  );
}
