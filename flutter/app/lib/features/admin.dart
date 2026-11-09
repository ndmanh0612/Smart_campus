import 'package:flutter/material.dart';
import '../core/campus_api.dart';
import 'shared.dart';
import 'enrollment_wizard.dart';

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
      '/admin/face-profiles',
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
                  'Đăng ký sinh viên trọn gói',
                  () => showEnrollStudentWizardDialog(context, api),
                  icon: Icons.how_to_reg,
                ),
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
                'studentCode': 'MSSV',
                'roles': 'Vai trò',
                'status': 'Trạng thái',
              },
              actions: (u) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ActionButton(
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
                  const SizedBox(width: 8),
                  if (u['id'] != api.user?['id'])
                    ActionButton(
                      'Xóa',
                      () => _showDeleteOrSettleDialog(
                        context,
                        api,
                        userId: u['id'].toString(),
                        userName: u['name'].toString(),
                        userEmail: u['email']?.toString(),
                        studentId: u['studentId']?.toString(),
                        studentCode: u['studentCode']?.toString(),
                      ),
                      outlined: true,
                      icon: Icons.delete_outline,
                    ),
                ],
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
            title: 'Phương tiện & Thẻ xe sinh viên',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ActionButton(
                  'Đăng ký thẻ xe cho sinh viên',
                  () => submitForm(
                    context,
                    api,
                    'Đăng ký phương tiện gửi xe',
                    '/admin/vehicles',
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
                        'plate',
                        'Biển số xe (VD: 59-A1 123.45)',
                      ),
                      const FormFieldSpec(
                        'vehicleType',
                        'Loại phương tiện',
                        options: {
                          'MOTORCYCLE': 'Xe máy',
                          'BICYCLE': 'Xe đạp điện / xe đạp',
                          'CAR': 'Ô tô',
                        },
                        initial: 'MOTORCYCLE',
                      ),
                    ],
                  ),
                  icon: Icons.two_wheeler_outlined,
                ),
                const SizedBox(height: 16),
                RecordTable(
                  data: rows(data['/admin/vehicles']),
                  columns: const {
                    'rawPlate': 'Biển số',
                    'studentCode': 'Mã sinh viên',
                    'studentName': 'Họ và tên',
                    'vehicleType': 'Loại xe',
                    'authorized': 'Đã duyệt',
                  },
                  actions: (v) => v['authorized'] == true
                      ? const Text('Đã duyệt')
                      : ActionButton(
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
              ],
            ),
          ),
          Surface(
            title: 'Hồ sơ khuôn mặt sinh viên',
            child: RecordTable(
              data: rows(data['/admin/face-profiles']),
              columns: const {
                'studentCode': 'Mã sinh viên',
                'studentName': 'Họ và tên',
                'enrolled': 'Đã có mẫu',
                'model': 'Mô hình AI',
                'enrolledAt': 'Thời gian lưu',
              },
              actions: (s) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (s['enrolled'] == true)
                    ActionButton(
                      'Xóa mẫu',
                      () async {
                        await api.request(
                          '/admin/face-pilot',
                          method: 'POST',
                          body: {'studentId': s['studentId'], 'action': 'erase'},
                        );
                        api.changed();
                        if (context.mounted) {
                          success(context, 'Đã xóa mẫu khuôn mặt.');
                        }
                      },
                      outlined: true,
                    )
                  else
                    const Text('Chưa có mẫu'),
                  const SizedBox(width: 8),
                  ActionButton(
                    'Xóa sinh viên',
                    () => _showDeleteOrSettleDialog(
                      context,
                      api,
                      userId: (s['userId'] ?? '').toString(),
                      userName: s['studentName'].toString(),
                      userEmail: s['email']?.toString(),
                      studentId: s['studentId'].toString(),
                      studentCode: s['studentCode'].toString(),
                    ),
                    outlined: true,
                    icon: Icons.delete_outline,
                  ),
                ],
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


Future<void> _showDeleteOrSettleDialog(
  BuildContext context,
  CampusApi api, {
  required String userId,
  required String userName,
  String? userEmail,
  String? studentId,
  String? studentCode,
}) async {
  Map<String, dynamic>? preview;
  try {
    final res = await api.request('/admin/users/$userId/delete-preview');
    if (res is Map) {
      preview = Map<String, dynamic>.from(res);
    }
  } catch (e) {
    if (context.mounted) {
      error(context, 'Không tải được thông tin tài khoản: $e');
    }
    return;
  }

  if (preview == null || !context.mounted) return;

  final hasTransactions = preview['hasTransactions'] == true;
  final balancePoints = preview['balancePoints']?.toString() ?? '0';
  final txCount = preview['transactionCount'] ?? 0;
  final studentName = preview['name']?.toString() ?? userName;
  final email = preview['email']?.toString() ?? userEmail ?? '';
  final sCode = preview['studentCode']?.toString() ?? studentCode ?? '';

  // TRƯỜNG HỢP 1: Tài khoản chưa từng nạp tiền / chưa có giao dịch -> Xóa sạch 100%
  if (!hasTransactions) {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.delete_forever, color: Color(0xffdc2626), size: 48),
        title: const Text('Xác nhận xóa tài khoản'),
        content: Text(
          'Tài khoản "$studentName" ($email) chưa từng nạp tiền hoặc phát sinh giao dịch tài chính.\n\n'
          'Thao tác này sẽ xóa sạch 100% tài khoản, thẻ RFID và dữ liệu khuôn mặt khỏi cơ sở dữ liệu.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xffdc2626)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xác nhận xóa sạch 100%'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await api.request('/admin/users/$userId', method: 'DELETE');
        api.changed();
        if (context.mounted) {
          success(context, 'Đã xóa người dùng "$studentName" thành công.');
        }
      } catch (e) {
        if (context.mounted) {
          error(context, 'Xóa không thành công: $e');
        }
      }
    }
    return;
  }

  // TRƯỜNG HỢP 2: Tài khoản ĐÃ TỪNG NẠP TIỀN / CÓ GIAO DỊCH
  // POPUP 1: Hiển thị số dư hiện tại & cảnh báo kiểm toán
  final proceedToSettle = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.account_balance_wallet_outlined, color: Color(0xffd97706), size: 48),
      title: const Text('Thông tin số dư & Lịch sử giao dịch'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Họ tên: $studentName'
              '${sCode.isNotEmpty ? "\nMSSV: $sCode" : ""}'
              '${email.isNotEmpty ? "\nEmail: $email" : ""}',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xfffffbeb),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xfffcd34d), width: 1.5),
              ),
              child: Column(
                children: [
                  const Text('Số dư ví hiện tại:', style: TextStyle(fontSize: 13, color: Color(0xff92400e))),
                  const SizedBox(height: 4),
                  Text(
                    '$balancePoints point',
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xffb45309)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '(Đã phát sinh $txCount giao dịch trong hệ thống)',
                    style: const TextStyle(fontSize: 12, color: Color(0xff92400e)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              '⚠️ Lưu ý kiểm toán:\n'
              'Sinh viên này đã có lịch sử nạp tiền hoặc chi tiêu trong quá khứ. Theo quy định kiểm toán tài chính, các chứng từ giao dịch kế toán sẽ được lưu giữ để đối soát doanh thu, không được xóa cứng làm sai lệch sổ cái.\n\n'
              'Nếu tiếp tục, hệ thống sẽ chuyển sang bước Hoàn tiền tất toán số dư cho sinh viên, đồng thời thu hồi thẻ RFID và xóa khuôn mặt để bạn có thể cấp cho người khác ngay lập tức.',
              style: TextStyle(fontSize: 12.5, color: Colors.black87, height: 1.4),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Hủy'),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: const Color(0xff0f766e)),
          onPressed: () => Navigator.pop(ctx, true),
          icon: const Icon(Icons.arrow_forward),
          label: const Text('Vẫn tiếp tục'),
        ),
      ],
    ),
  );

  if (proceedToSettle != true || !context.mounted) return;

  // POPUP 2: Hoàn tiền cho sinh viên & Thu hồi tài khoản
  final confirmedSettle = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.assignment_return_outlined, color: Color(0xff0f766e), size: 48),
      title: const Text('Hoàn tiền cho sinh viên & Thu hồi'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xfff0fdf4),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xff86efac)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.currency_exchange, color: Color(0xff16a34a), size: 30),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Số tiền hoàn trả lại sinh viên:', style: TextStyle(fontSize: 12, color: Color(0xff166534))),
                        Text(
                          '$balancePoints point',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xff15803d)),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Thủ quỹ hoàn trả tiền mặt hoặc chuyển khoản cho sinh viên. Hệ thống tự động ghi nhận bút toán tất toán số dư về 0 point.',
                          style: TextStyle(fontSize: 11, color: Color(0xff166534)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Danh sách tác vụ tự động thực hiện:\n'
              '✔️ Tất toán số dư ví về 0 point\n'
              '✔️ Thu hồi thẻ RFID (thẻ được giải phóng để cấp cho người khác ngay)\n'
              '✔️ Xóa khuôn mặt AI (camera bãi xe/cổng không còn nhận diện)\n'
              '✔️ Khóa ví điện tử & hủy quyền đăng nhập của sinh viên\n'
              '✔️ Bảo toàn chứng từ lịch sử giao dịch phục vụ đối soát kế toán',
              style: TextStyle(fontSize: 12.5, color: Colors.black87, height: 1.45),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Quay lại'),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: const Color(0xff0f766e)),
          onPressed: () => Navigator.pop(ctx, true),
          icon: const Icon(Icons.check_circle_outline),
          label: const Text('Xác nhận Hoàn tiền & Thu hồi'),
        ),
      ],
    ),
  );

  if (confirmedSettle == true && context.mounted) {
    try {
      final res = await api.request(
        '/admin/users/$userId/settle-and-deactivate',
        method: 'POST',
        body: {'reason': 'Hoàn tiền tất toán số dư & thu hồi tài khoản sinh viên'},
      );
      api.changed();
      if (context.mounted) {
        final refundAmt = (res is Map ? res['refundedPoints'] : null) ?? balancePoints;
        success(
          context,
          'Đã hoàn tất hoàn trả $refundAmt point và thu hồi thẻ RFID, khuôn mặt cho "$studentName"! Thẻ và khuôn mặt đã sẵn sàng để cấp cho người khác.',
        );
      }
    } catch (e) {
      if (context.mounted) {
        error(context, 'Xử lý thu hồi không thành công: $e');
      }
    }
  }
}
