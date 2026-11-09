import 'package:flutter/material.dart';
import '../core/campus_api.dart';
import 'shared.dart';
import 'live_face_camera.dart';

class StudentHome extends StatelessWidget {
  final CampusApi api;
  const StudentHome(this.api, {super.key});
  @override
  Widget build(BuildContext context) => DataPanel(
    api: api,
    paths: const ['/me/wallet', '/me/notifications', '/me/parking-sessions'],
    builder: (context, data) {
      final wallet = data['/me/wallet'] as Map;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionTitle(
            'Chào ${api.user?['name'] ?? 'bạn'},',
            'Một thẻ sinh viên, kết nối mọi dịch vụ trong khuôn viên.',
          ),
          Container(
            padding: const EdgeInsets.all(28),
            margin: const EdgeInsets.only(bottom: 24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: const LinearGradient(
                colors: [Color(0xff0f766e), Color(0xff115e59)],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'SỐ POINT KHẢ DỤNG',
                  style: TextStyle(color: Colors.white70, letterSpacing: 1.4),
                ),
                const SizedBox(height: 12),
                Text(
                  pointText(wallet['availablePoints']),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Đang giữ: ${pointText(wallet['heldPoints'])}',
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Ví thử nghiệm • Nạp point MOCK, không phải tiền thật',
                  style: TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
          const ModeLabels(),
          const SizedBox(height: 24),
          Surface(
            title: 'Thông báo gần đây',
            child: RecordTable(
              data: rows(data['/me/notifications']),
              columns: const {'message': 'Nội dung', 'createdAt': 'Thời gian'},
            ),
          ),
          Surface(
            title: 'Các lượt gửi xe',
            child: RecordTable(
              data: rows(data['/me/parking-sessions']),
              columns: const {
                'entryPlate': 'Biển số',
                'status': 'Trạng thái',
                'enteredAt': 'Vào bãi',
                'entrySource': 'Nguồn',
              },
            ),
          ),
        ],
      );
    },
  );
}

class WalletPage extends StatelessWidget {
  final CampusApi api;
  const WalletPage(this.api, {super.key});
  @override
  Widget build(BuildContext context) => DataPanel(
    api: api,
    paths: const [
      '/me/wallet',
      '/me/wallet/spending-report',
      '/me/payment-requests',
      '/me/wallet/ledger',
      '/me/topups',
    ],
    builder: (context, data) {
      final wallet = data['/me/wallet'] as Map;
      final rawReport = data['/me/wallet/spending-report'];
      final report = rawReport is Map ? rawReport : null;
      final summary = report?['summary'] is Map ? report!['summary'] as Map : null;
      final transactions = rows(report?['transactions'] ?? data['/me/wallet/ledger']);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionTitle(
            'Ví point & thanh toán',
            'Số dư khả dụng dùng chung cho gửi xe và căng tin. Quẹt thẻ sinh viên thanh toán trực tiếp.',
          ),
          Surface(
            child: Wrap(
              spacing: 32,
              runSpacing: 20,
              children: [
                _amount('Khả dụng', wallet['availablePoints']),
                _amount('Đang giữ', wallet['heldPoints']),
                _amount('Đã ghi sổ', wallet['postedPoints']),
                ActionButton(
                  'Nạp point MOCK',
                  () => submitForm(
                    context,
                    api,
                    'Nạp point mô phỏng — không phải tiền thật',
                    '/me/topups',
                    const [
                      FormFieldSpec(
                        'requestedVnd',
                        'Số VND quy đổi thử nghiệm',
                        kind: 'points',
                        initial: '50000',
                      ),
                    ],
                  ),
                  icon: Icons.add,
                ),
              ],
            ),
          ),
          Surface(
              title: 'Yêu cầu cần bạn xác nhận',
              child: Column(
                children: rows(data['/me/payment-requests'])
                    .map(
                      (p) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.shield_outlined),
                        title: Text(
                          '${p['orderId'] != null ? 'Đơn cantin' : 'Phí gửi xe'} • ${pointText(p['amountPoints'])}',
                        ),
                        subtitle: Text(display(p['status'])),
                        trailing: ActionButton('Xác nhận', () async {
                          final form = await formDialog(
                            context,
                            'Xác nhận ${pointText(p['amountPoints'])}',
                            [
                              FormFieldSpec('pin', 'PIN ví', kind: 'password', initial: api.demoPin ?? '295417'),
                            ],
                          );
                          if (form == null) return;
                          await api.request(
                            '/me/payments/${p['id']}/approvals',
                            method: 'POST',
                            body: {
                              ...form,
                              'expectedSourceVersion': p['sourceVersion'],
                            },
                          );
                          api.changed();
                          if (context.mounted) {
                            success(
                              context,
                              'Đã xác nhận. Giao dịch hoàn tất.',
                            );
                          }
                        }, icon: Icons.check),
                      ),
                    )
                    .toList(),
              ),
            ),
          Surface(
            title: 'Báo cáo chi tiêu & Nạp nhanh',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Nạp tiền nhanh vào ví:',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xff475569)),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    for (final amt in [20000, 50000, 100000, 200000])
                      ActionChip(
                        avatar: const Icon(Icons.add_circle_outline, size: 16, color: Color(0xff16a34a)),
                        label: Text(
                          '+${pointText(amt)}',
                          style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xff15803d)),
                        ),
                        backgroundColor: const Color(0xfff0fdf4),
                        side: const BorderSide(color: Color(0xffbbf7d0)),
                        onPressed: () async {
                          await api.request(
                            '/me/topups',
                            method: 'POST',
                            body: {'requestedVnd': amt.toString()},
                          );
                          api.changed();
                          if (context.mounted) {
                            success(context, 'Đã nạp thành công ${pointText(amt)} vào ví!');
                          }
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                const Text(
                  'Thống kê chi tiêu:',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xff475569)),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    _statCard(
                  'Tổng chi tiêu',
                  summary?['totalSpent'] ?? '0',
                  const Color(0xff0f766e),
                  Icons.shopping_cart_checkout,
                  'Căn tin & Gửi xe',
                ),
                _statCard(
                  'Tổng đã nạp',
                  summary?['totalTopUp'] ?? '0',
                  const Color(0xff16a34a),
                  Icons.arrow_downward,
                  'Tổng tích lũy',
                ),
                _statCard(
                  'Chi Căng tin',
                  summary?['totalCanteen'] ?? '0',
                  const Color(0xffea580c),
                  Icons.restaurant,
                  'Ăn uống & mua sắm',
                ),
                _statCard(
                  'Phí Gửi xe',
                  summary?['totalParking'] ?? '0',
                  const Color(0xff2563eb),
                  Icons.local_parking,
                  'Lượt vào/ra bãi xe',
                ),
                  ],
                ),
              ],
            ),
          ),
          Surface(
            title: 'Lịch sử giao dịch chi tiêu',
            child: transactions.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: Text('Chưa có giao dịch chi tiêu nào.')),
                  )
                : Column(
                    children: transactions.map((t) {
                      final type = t['type']?.toString() ?? '';
                      final isTopUp = type == 'TOP_UP';
                      final isCanteen = type == 'CANTEEN_PAYMENT';
                      final isParking = type == 'PARKING_PAYMENT';
                      final isRefund = type == 'REFUND';

                      final icon = isTopUp
                          ? Icons.add_circle
                          : isCanteen
                          ? Icons.restaurant
                          : isParking
                          ? Icons.local_parking
                          : isRefund
                          ? Icons.replay
                          : Icons.account_balance_wallet;

                      final color = isTopUp
                          ? const Color(0xff16a34a)
                          : isCanteen
                          ? const Color(0xffea580c)
                          : isParking
                          ? const Color(0xff2563eb)
                          : isRefund
                          ? const Color(0xff9333ea)
                          : const Color(0xff64748b);

                      final title = isTopUp
                          ? 'Nạp tiền ví'
                          : isCanteen
                          ? 'Thanh toán Căn tin'
                          : isParking
                          ? 'Phí gửi xe ${t['entryPlate'] != null ? '(${t['entryPlate']})' : ''}'
                          : isRefund
                          ? 'Hoàn tiền'
                          : display(type);

                      final pts = t['amountPoints'] ?? t['deltaPoints'] ?? '0';
                      final prefix = isTopUp || isRefund ? '+' : '-';

                      return Container(
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                        decoration: const BoxDecoration(
                          border: Border(bottom: BorderSide(color: Color(0xfff1f5f9))),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(icon, color: color, size: 22),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    display(t['createdAt']),
                                    style: const TextStyle(fontSize: 12, color: Color(0xff64748b)),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              '$prefix${pointText(pts)}',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                                color: isTopUp || isRefund ? const Color(0xff16a34a) : const Color(0xffdc2626),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
          ),
        ],
      );
    },
  );

  Widget _statCard(String title, dynamic value, Color color, IconData icon, String subtitle) => Container(
    width: 220,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: color.withValues(alpha: 0.25)),
      boxShadow: [
        BoxShadow(
          color: color.withValues(alpha: 0.04),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(title, style: const TextStyle(fontSize: 13, color: Color(0xff64748b), fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 4),
            Icon(icon, color: color, size: 20),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          pointText(value),
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color),
        ),
        const SizedBox(height: 4),
        Text(subtitle, style: const TextStyle(fontSize: 11, color: Color(0xff94a3b8))),
      ],
    ),
  );

  Widget _amount(String title, dynamic value, {Color? color}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title),
      const SizedBox(height: 8),
      Text(
        pointText(value),
        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: color),
      ),
    ],
  );
}

class CardsPage extends StatelessWidget {
  final CampusApi api;
  const CardsPage(this.api, {super.key});
  @override
  Widget build(BuildContext context) => DataPanel(
    api: api,
    paths: const ['/me/cards'],
    builder: (context, data) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle(
          'Thẻ sinh viên',
          'Báo mất ngay để khóa nhận diện bằng thẻ. Cấp hoặc thay thẻ cần quét RFID thật tại bàn quản trị.',
        ),
        Surface(
          child: RecordTable(
            data: rows(data['/me/cards']),
            columns: const {
              'status': 'Trạng thái',
              'createdAt': 'Ngày cấp',
              'expiresAt': 'Hết hiệu lực',
            },
            actions: (r) => r['status'] == 'ACTIVE'
                ? ActionButton(
                    'Báo mất',
                    () => submitForm(
                      context,
                      api,
                      'Báo mất thẻ',
                      '/me/cards/${r['id']}/report-lost',
                      const [
                        FormFieldSpec('reason', 'Lý do', kind: 'multiline'),
                      ],
                    ),
                    outlined: true,
                  )
                : const Text('—'),
          ),
        ),
      ],
    ),
  );
}

class VehiclesPage extends StatelessWidget {
  final CampusApi api;
  const VehiclesPage(this.api, {super.key});
  @override
  Widget build(BuildContext context) => DataPanel(
    api: api,
    paths: const ['/me/vehicles'],
    builder: (context, data) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle(
          'Phương tiện của tôi',
          'Xe đăng ký mới cần quản trị duyệt quyền sử dụng trước khi vào bãi.',
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: ActionButton(
            'Đăng ký xe',
            () => submitForm(
              context,
              api,
              'Đăng ký phương tiện',
              '/me/vehicles',
              const [
                FormFieldSpec('plate', 'Biển số'),
                FormFieldSpec(
                  'vehicleType',
                  'Loại xe',
                  options: {
                    'MOTORCYCLE': 'Xe máy',
                    'CAR': 'Ô tô',
                    'BICYCLE': 'Xe đạp',
                  },
                ),
              ],
            ),
            icon: Icons.add,
          ),
        ),
        const SizedBox(height: 20),
        Surface(
          child: RecordTable(
            data: rows(data['/me/vehicles']),
            columns: const {
              'rawPlate': 'Biển số',
              'vehicleType': 'Loại xe',
              'authorized': 'Được phép sử dụng',
              'validTo': 'Hạn sử dụng',
            },
          ),
        ),
      ],
    ),
  );
}

class HistoryPage extends StatelessWidget {
  final CampusApi api;
  const HistoryPage(this.api, {super.key});
  @override
  Widget build(BuildContext context) => DataPanel(
    api: api,
    paths: const [
      '/me/parking-sessions',
      '/me/canteen-orders',
      '/me/attendance',
    ],
    builder: (context, data) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle(
          'Lịch sử dịch vụ',
          'Dữ liệu lấy trực tiếp từ tài khoản của bạn trên máy chủ.',
        ),
        Surface(
          title: 'Gửi xe',
          child: RecordTable(
            data: rows(data['/me/parking-sessions']),
            columns: const {
              'entryPlate': 'Biển số',
              'status': 'Trạng thái',
              'enteredAt': 'Vào bãi',
              'exitedAt': 'Ra bãi',
            },
          ),
        ),
        Surface(
          title: 'Mua hàng cantin',
          child: RecordTable(
            data: rows(data['/me/canteen-orders']),
            columns: const {
              'totalPoints': 'Tổng point',
              'status': 'Trạng thái',
              'createdAt': 'Thời gian',
            },
          ),
        ),
        Surface(
          title: 'Điểm danh',
          child: RecordTable(
            data: rows(data['/me/attendance']),
            columns: const {
              'status': 'Kết quả',
              'source': 'Nguồn',
              'receivedAt': 'Thời gian',
              'sessionStatus': 'Phiên',
            },
          ),
        ),
      ],
    ),
  );
}

class ConsentPage extends StatelessWidget {
  final CampusApi api;
  const ConsentPage(this.api, {super.key});
  @override
  Widget build(BuildContext context) => DataPanel(
    api: api,
    paths: const [
      '/me/biometric-consents',
      '/me/biometric-profiles',
      '/me/face-pilot',
    ],
    builder: (context, data) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle(
          'Đăng ký khuôn mặt',
          'Quản lý mẫu thử trên camera OV3660 và hồ sơ mô phỏng.',
        ),
        Builder(
          builder: (context) {
            final faceInfo = data['/me/face-pilot'] as Map? ?? {};
            final studentCode = faceInfo['studentCode']?.toString() ??
                api.user?['studentCode']?.toString() ??
                '---';
            final studentName = faceInfo['studentName']?.toString() ??
                api.user?['name']?.toString() ??
                'Sinh viên';
            final isEnrolled = faceInfo['enrolled'] == true;
            return Surface(
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 22,
                    backgroundColor: Color(0xffccfbf1),
                    child: Icon(Icons.person, color: Color(0xff0f766e)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          studentName,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Mã số sinh viên (MSSV): $studentCode',
                          style: const TextStyle(
                            color: Color(0xff64748b),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isEnrolled
                          ? const Color(0xffdcfce7)
                          : const Color(0xfff1f5f9),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isEnrolled
                            ? const Color(0xff86efac)
                            : const Color(0xffcbd5e1),
                      ),
                    ),
                    child: Text(
                      isEnrolled ? 'ĐÃ CÓ MẪU (SFace)' : 'CHƯA ĐĂNG KÝ',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isEnrolled
                            ? const Color(0xff166534)
                            : const Color(0xff64748b),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        if ((data['/me/face-pilot'] as Map?)?['enabled'] == true)
          Surface(
            title: 'Thử nhận dạng bằng camera thật',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Đứng trước camera, đủ sáng và để một khuôn mặt trong khung. '
                  'Thử nghiệm chỉ lưu mẫu đặc trưng trên máy chủ local. '
                  'Kết quả chưa dùng để mở cổng hoặc thanh toán.',
                ),
                const SizedBox(height: 12),
                LiveFaceCamera(
                  api,
                  enrolled: (data['/me/face-pilot'] as Map)['enrolled'] == true,
                ),
                const SizedBox(height: 12),
                if ((data['/me/face-pilot'] as Map)['enrolled'] == true)
                  ActionButton('Xóa mẫu thật', () async {
                    await api.request(
                      '/me/face-pilot',
                      method: 'POST',
                      body: {'action': 'erase'},
                    );
                    api.changed();
                  }, outlined: true)
                else
                  ActionButton('Đăng ký khuôn mặt bằng OV3660', () async {
                    final consent = await showDialog<bool>(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        title: const Text('Đồng ý chụp mẫu khuôn mặt'),
                        content: const Text(
                          'Camera sẽ chụp một ảnh ngay khi bạn đồng ý. App lưu mẫu đặc trưng trên máy chủ thử nghiệm. Bạn có thể xóa mẫu bất cứ lúc nào.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () =>
                                Navigator.pop(dialogContext, false),
                            child: const Text('Hủy'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(dialogContext, true),
                            child: const Text('Đồng ý và chụp'),
                          ),
                        ],
                      ),
                    );
                    if (consent != true) return;
                    await api.request(
                      '/me/face-pilot',
                      method: 'POST',
                      body: {'action': 'enroll', 'consent': true},
                    );
                    api.changed();
                    if (context.mounted) {
                      success(
                        context,
                        'Đã lưu mẫu. App sẽ tự nhận dạng trên video.',
                      );
                    }
                  }, icon: Icons.camera_alt_outlined),
              ],
            ),
          ),
        if (!rows(data['/me/biometric-profiles']).any(
          (profile) =>
              profile['purpose'] == 'PARKING' && profile['status'] == 'ACTIVE',
        ))
          Align(
            alignment: Alignment.centerLeft,
            child: ActionButton('Đăng ký khuôn mặt gửi xe (DEMO)', () async {
              final agreed = await showDialog<bool>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('Đồng ý đăng ký hồ sơ mẫu'),
                  content: const Text(
                    'Hồ sơ này dùng để thử lựa chọn quên thẻ tại bãi xe. '
                    'Bản DEMO không thu ảnh hay dữ liệu sinh trắc. '
                    'Bạn có thể thu hồi đồng ý bất cứ lúc nào.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('Hủy'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: const Text('Đồng ý đăng ký'),
                    ),
                  ],
                ),
              );
              if (agreed != true) return;
              final consents = rows(
                await api.request('/me/biometric-consents'),
              );
              final consent =
                  consents
                      .where(
                        (row) =>
                            row['purpose'] == 'PARKING' &&
                            row['source'] == 'DEMO' &&
                            row['revokedAt'] == null,
                      )
                      .firstOrNull ??
                  await api.request(
                    '/me/biometric-consents',
                    method: 'POST',
                    body: {
                      'purpose': 'PARKING',
                      'policyVersion': 'fixture-v1',
                      'explicitConsent': true,
                    },
                  );
              await api.request(
                '/me/biometric-profiles/enrollment-requests',
                method: 'POST',
                body: {'consentId': consent['id']},
              );
              api.changed();
              if (context.mounted) {
                success(context, 'Đã đăng ký hồ sơ khuôn mặt DEMO cho bãi xe.');
              }
            }, icon: Icons.face),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: ActionButton(
            'Đồng ý cho hồ sơ mẫu',
            () => submitForm(
              context,
              api,
              'Đồng ý mô phỏng xử lý dữ liệu',
              '/me/biometric-consents',
              const [
                FormFieldSpec(
                  'purpose',
                  'Mục đích',
                  options: {
                    'PARKING': 'Gửi xe',
                    'CANTEEN': 'Cantin',
                    'ATTENDANCE': 'Điểm danh',
                  },
                ),
              ],
              extra: {'policyVersion': 'fixture-v1', 'explicitConsent': true},
            ),
            icon: Icons.verified_user_outlined,
          ),
        ),
        const SizedBox(height: 20),
        Surface(
          child: RecordTable(
            data: rows(data['/me/biometric-consents']),
            columns: const {
              'purpose': 'Mục đích',
              'source': 'Nguồn',
              'grantedAt': 'Ngày đồng ý',
              'revokedAt': 'Thu hồi',
            },
            actions: (r) => r['revokedAt'] == null ? Row(mainAxisSize: MainAxisSize.min, 
                    spacing: 8,
                    children: [
                      if (!rows(data['/me/biometric-profiles']).any(
                        (p) =>
                            p['purpose'] == r['purpose'] &&
                            p['status'] == 'ACTIVE',
                      ))
                        ActionButton('Đăng ký hồ sơ DEMO', () async {
                          await api.request(
                            '/me/biometric-profiles/enrollment-requests',
                            method: 'POST',
                            body: {'consentId': r['id']},
                          );
                          api.changed();
                        }, outlined: true),
                      ActionButton('Thu hồi', () async {
                        await api.request(
                          '/me/biometric-consents/${r['id']}/revoke',
                          method: 'POST',
                          body: {},
                        );
                        api.changed();
                      }, outlined: true),
                    ],
                  )
                : const Text('Đã thu hồi'),
          ),
        ),
        Surface(
          title: 'Hồ sơ nhận diện mô phỏng',
          child: RecordTable(
            data: rows(data['/me/biometric-profiles']),
            columns: const {
              'purpose': 'Mục đích',
              'source': 'Nguồn',
              'status': 'Trạng thái',
              'erasedAt': 'Đã xóa',
            },
            actions: (p) => p['status'] == 'ACTIVE'
                ? ActionButton('Xóa hồ sơ', () async {
                    await api.request(
                      '/me/biometric-profiles/${p['id']}',
                      method: 'DELETE',
                      body: {},
                    );
                    api.changed();
                  }, outlined: true)
                : const Text('Đã xóa'),
          ),
        ),
      ],
    ),
  );
}

class SecurityPage extends StatelessWidget {
  final CampusApi api;
  const SecurityPage(this.api, {super.key});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SectionTitle(
        'Hồ sơ & bảo mật',
        'Thẻ RFID chỉ xác định danh tính. Mọi khoản chi point cần PIN ví do bạn nhập trên tài khoản của mình.',
      ),
      Surface(
        title: api.user?['name']?.toString(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(api.user?['email']?.toString() ?? ''),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                ActionButton(
                  'Đổi tên hiển thị',
                  () => submitForm(context, api, 'Hồ sơ cá nhân', '/me', const [
                    FormFieldSpec('name', 'Họ tên'),
                  ], method: 'PATCH'),
                  outlined: true,
                ),
                ActionButton(
                  'Đặt / đổi PIN ví',
                  () => submitForm(
                    context,
                    api,
                    'Bảo mật ví point',
                    '/me/wallet-pin',
                    const [
                      FormFieldSpec(
                        'oldPin',
                        'PIN hiện tại (bỏ trống nếu chưa đặt)',
                        kind: 'password',
                        required: false,
                      ),
                      FormFieldSpec(
                        'newPin',
                        'PIN mới, từ 6 đến 12 chữ số',
                        kind: 'password',
                      ),
                    ],
                    method: 'PUT',
                  ),
                  icon: Icons.lock_outline,
                ),
              ],
            ),
          ],
        ),
      ),
    ],
  );
}
