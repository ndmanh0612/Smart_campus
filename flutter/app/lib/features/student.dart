import 'package:flutter/material.dart';
import '../core/campus_api.dart';
import 'shared.dart';

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
      '/me/payment-requests',
      '/me/wallet/ledger',
      '/me/topups',
    ],
    builder: (context, data) {
      final wallet = data['/me/wallet'] as Map;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionTitle(
            'Ví point & thanh toán',
            'Xem nội dung và số point trước khi xác nhận bằng PIN trên tài khoản của bạn.',
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
                          const [
                            FormFieldSpec('pin', 'PIN ví', kind: 'password'),
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
                            'Đã xác nhận. Nhân viên sẽ hoàn tất giao dịch.',
                          );
                        }
                      }, icon: Icons.check),
                    ),
                  )
                  .toList(),
            ),
          ),
          Surface(
            title: 'Sổ cái point',
            child: RecordTable(
              data: rows(data['/me/wallet/ledger']),
              columns: const {
                'type': 'Loại giao dịch',
                'deltaPoints': 'Thay đổi point',
                'createdAt': 'Thời gian',
              },
            ),
          ),
          Surface(
            title: 'Lịch sử nạp MOCK',
            child: RecordTable(
              data: rows(data['/me/topups']),
              columns: const {
                'requestedVnd': 'VND thử nghiệm',
                'amountPoints': 'Point',
                'status': 'Trạng thái',
                'provider': 'Nguồn',
              },
            ),
          ),
        ],
      );
    },
  );
  Widget _amount(String title, dynamic value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title),
      const SizedBox(height: 8),
      Text(
        pointText(value),
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
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
    paths: const ['/me/biometric-consents', '/me/biometric-profiles'],
    builder: (context, data) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle(
          'Dữ liệu khuôn mặt',
          'Hiện chỉ dùng hồ sơ mẫu DEMO, không thu ảnh hay embedding thật. Bạn có thể thu hồi đồng ý theo từng mục đích.',
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
            actions: (r) => r['revokedAt'] == null
                ? Wrap(
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
