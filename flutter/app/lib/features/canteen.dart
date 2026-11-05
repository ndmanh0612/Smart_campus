import 'package:flutter/material.dart';
import '../core/campus_api.dart';
import 'shared.dart';

class CanteenPage extends StatefulWidget {
  final CampusApi api;
  const CanteenPage(this.api, {super.key});
  @override
  State<CanteenPage> createState() => _CanteenPageState();
}

class _CanteenPageState extends State<CanteenPage> {
  final Map<String, int> cart = {};
  String? orderId, contextId, identityId;
  CampusApi get api => widget.api;
  @override
  Widget build(BuildContext context) => DataPanel(
    key: ValueKey(orderId),
    api: api,
    paths: [
      '/canteen/products',
      '/canteen/orders',
      '/simulator/status',
      '/simulator/students',
      '/simulator/events',
      if (orderId != null) '/canteen/orders/$orderId',
    ],
    builder: (context, data) {
      final products = rows(data['/canteen/products']),
          orders = rows(data['/canteen/orders']);
      final terminals = rows(
        (data['/simulator/status'] as Map)['devices'],
      ).where((d) => d['role'] == 'CANTEEN_POS').toList();
      final students = rows(data['/simulator/students']);
      final identities = rows((data['/simulator/events'] as Map)['identities'])
          .where((i) => i['contextId'] == contextId && i['consumedAt'] == null)
          .toList();
      final identity =
          identityId ??
          (identities.isEmpty ? null : identities.first['id'] as String);
      final detail = data['/canteen/orders/$orderId'] as Map?;
      final payments = rows(detail?['payments']);
      final ready = payments
          .where(
            (p) =>
                p['status'] == 'AWAITING_CONFIRMATION' &&
                p['approvalId'] != null,
          )
          .firstOrNull;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionTitle(
            'Cantin • Điểm bán hàng',
            'Giá và tồn kho do máy chủ xác nhận. Sinh viên tự nhập PIN trên tài khoản của mình.',
          ),
          const ModeLabels(),
          const SizedBox(height: 20),
          Surface(
            title: 'Chọn món',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: products
                      .map(
                        (p) => SizedBox(
                          width: 235,
                          child: Card(
                            color: const Color(0xfff0fdfa),
                            elevation: 0,
                            child: Padding(
                              padding: const EdgeInsets.all(18),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.restaurant_outlined,
                                    size: 30,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    p['name'].toString(),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 18,
                                    ),
                                  ),
                                  Text(pointText(p['pricePoints'])),
                                  Text('Khả dụng: ${p['available']}'),
                                  Row(
                                    children: [
                                      IconButton(
                                        onPressed: (cart[p['id']] ?? 0) > 0
                                            ? () => setState(
                                                () => cart[p['id']] =
                                                    (cart[p['id']] ?? 0) - 1,
                                              )
                                            : null,
                                        icon: const Icon(
                                          Icons.remove_circle_outline,
                                        ),
                                      ),
                                      Text('${cart[p['id']] ?? 0}'),
                                      IconButton(
                                        onPressed:
                                            p['active'] == true &&
                                                p['available'] > 0
                                            ? () => setState(
                                                () => cart[p['id']] =
                                                    (cart[p['id']] ?? 0) + 1,
                                              )
                                            : null,
                                        icon: const Icon(
                                          Icons.add_circle_outline,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 16),
                ActionButton(
                  'Tạo đơn & giữ hàng',
                  cart.values.every((v) => v == 0)
                      ? null
                      : () async {
                          final r = await api.request(
                            '/canteen/orders',
                            method: 'POST',
                            body: {
                              'items': cart.entries
                                  .where((e) => e.value > 0)
                                  .map(
                                    (e) => {
                                      'productId': e.key,
                                      'quantity': e.value,
                                    },
                                  )
                                  .toList(),
                            },
                          );
                          if (mounted) {
                            setState(() {
                              orderId = r['id'] as String;
                              cart.clear();
                              contextId = null;
                              identityId = null;
                            });
                          }
                          api.changed();
                        },
                  icon: Icons.shopping_bag_outlined,
                ),
              ],
            ),
          ),
          if (detail != null)
            Surface(
              title: 'Đơn đang thao tác • ${pointText(detail['totalPoints'])}',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Trạng thái: ${display(detail['status'])}'),
                  const SizedBox(height: 16),
                  if (detail['status'] == 'AWAITING_PAYMENT')
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        ActionButton('Chuẩn bị nhận thẻ / Face DEMO', () async {
                          final f = await formDialog(
                            context,
                            'Chọn nguồn nhận diện',
                            [
                              FormFieldSpec(
                                'deviceId',
                                'Thiết bị',
                                options: options(terminals, 'name'),
                              ),
                            ],
                          );
                          if (f == null) return;
                          final r = await api.request(
                            '/canteen/orders/$orderId/checkout-contexts',
                            method: 'POST',
                            body: {...f, 'expectedVersion': detail['version']},
                          );
                          if (mounted) {
                            setState(() => contextId = r['id'] as String);
                          }
                          api.changed();
                        }, outlined: true),
                        if (contextId != null)
                          ActionButton('Hủy lần xác thực', () async {
                            await api.request(
                              '/device-contexts/$contextId/cancel',
                              method: 'POST',
                              body: {
                                'reason':
                                    'Nhân viên hủy để quét lại thẻ hoặc nhận diện lại',
                              },
                            );
                            if (mounted) {
                              setState(() {
                                contextId = null;
                                identityId = null;
                              });
                            }
                            api.changed();
                          }, outlined: true),
                        if (contextId != null)
                          ActionButton('Face DEMO', () async {
                            final f =
                                await formDialog(context, 'Sinh viên mẫu', [
                                  FormFieldSpec(
                                    'studentFixtureId',
                                    'Sinh viên',
                                    options: options(students, 'name'),
                                  ),
                                ]);
                            if (f == null) return;
                            final r = await api.request(
                              '/simulator/face-events',
                              method: 'POST',
                              body: {
                                ...f,
                                'contextId': contextId,
                                'scenario': 'SUCCESS',
                              },
                            );
                            if (mounted) {
                              setState(
                                () => identityId =
                                    r['identityAssertionId'] as String,
                              );
                            }
                            api.changed();
                          }, outlined: true),
                        if (identity != null && detail['studentId'] == null)
                          ActionButton('Gửi yêu cầu thanh toán', () async {
                            await api.request(
                              '/canteen/orders/$orderId/identify',
                              method: 'POST',
                              body: {'identityAssertionId': identity},
                            );
                            if (mounted) setState(() => contextId = null);
                            api.changed();
                          }, icon: Icons.send_outlined),
                        if (ready != null)
                          ActionButton('Hoàn tất thu point', () async {
                            await api.request(
                              '/canteen/orders/$orderId/payments',
                              method: 'POST',
                              body: {
                                'paymentId': ready['id'],
                                'approvalId': ready['approvalId'],
                                'expectedVersion': detail['version'],
                              },
                            );
                            api.changed();
                          }, icon: Icons.check),
                        ActionButton('Hủy đơn', () async {
                          await api.request(
                            '/canteen/orders/$orderId/cancel',
                            method: 'POST',
                            body: {'reason': 'Nhân viên hủy đơn tại POS'},
                          );
                          if (mounted) setState(() => contextId = null);
                          api.changed();
                        }, outlined: true),
                      ],
                    ),
                  if (detail['studentId'] != null &&
                      ready == null &&
                      detail['status'] == 'AWAITING_PAYMENT')
                    const Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: Text(
                        'Đã xác định sinh viên. Chờ sinh viên mở Ví & thanh toán để nhập PIN xác nhận.',
                      ),
                    ),
                ],
              ),
            ),
          Surface(
            title: 'Đơn gần đây',
            child: RecordTable(
              data: orders,
              columns: const {
                'totalPoints': 'Tổng point',
                'status': 'Trạng thái',
                'createdAt': 'Thời gian',
              },
              actions: (o) => TextButton(
                onPressed: () => setState(() => orderId = o['id'] as String),
                child: const Text('Mở đơn'),
              ),
            ),
          ),
        ],
      );
    },
  );
}

class InventoryPage extends StatelessWidget {
  final CampusApi api;
  const InventoryPage(this.api, {super.key});
  @override
  Widget build(BuildContext context) => DataPanel(
    api: api,
    paths: const [
      '/canteen/products',
      '/canteen/categories',
      '/canteen/inventory-movements',
      '/refunds',
    ],
    builder: (context, data) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle(
          'Hàng hóa & tồn kho',
          'Nhập hàng, thay đổi giá bán và theo dõi biến động kho.',
        ),
        Surface(
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              ActionButton(
                'Thêm danh mục',
                () => submitForm(
                  context,
                  api,
                  'Danh mục mới',
                  '/canteen/categories',
                  const [FormFieldSpec('name', 'Tên danh mục')],
                ),
                outlined: true,
              ),
              ActionButton(
                'Thêm sản phẩm',
                () => submitForm(
                  context,
                  api,
                  'Sản phẩm mới',
                  '/canteen/products',
                  [
                    FormFieldSpec(
                      'categoryId',
                      'Danh mục',
                      options: options(
                        rows(data['/canteen/categories']),
                        'name',
                      ),
                    ),
                    const FormFieldSpec('sku', 'Mã hàng'),
                    const FormFieldSpec('name', 'Tên sản phẩm'),
                    const FormFieldSpec(
                      'pricePoints',
                      'Giá point',
                      kind: 'points',
                    ),
                    const FormFieldSpec(
                      'initialStock',
                      'Tồn ban đầu',
                      kind: 'integer',
                      initial: '0',
                    ),
                  ],
                ),
                icon: Icons.add,
              ),
              ActionButton(
                'Điều chỉnh kho',
                () => submitForm(
                  context,
                  api,
                  'Nhập / điều chỉnh hàng',
                  '/canteen/inventory-adjustments',
                  [
                    FormFieldSpec(
                      'productId',
                      'Sản phẩm',
                      options: options(rows(data['/canteen/products']), 'name'),
                    ),
                    const FormFieldSpec(
                      'delta',
                      'Số lượng tăng hoặc giảm',
                      kind: 'integer',
                    ),
                    const FormFieldSpec('reason', 'Lý do', kind: 'multiline'),
                  ],
                ),
                outlined: true,
              ),
              ActionButton(
                'Hoàn point',
                () => submitForm(
                  context,
                  api,
                  'Hoàn point giao dịch gốc',
                  '/refunds',
                  const [
                    FormFieldSpec(
                      'originalTransactionId',
                      'Mã giao dịch trên biên lai',
                    ),
                    FormFieldSpec(
                      'amountPoints',
                      'Số point hoàn',
                      kind: 'points',
                    ),
                    FormFieldSpec('reason', 'Lý do', kind: 'multiline'),
                  ],
                ),
                outlined: true,
              ),
            ],
          ),
        ),
        Surface(
          title: 'Sản phẩm',
          child: RecordTable(
            data: rows(data['/canteen/products']),
            columns: const {
              'name': 'Tên sản phẩm',
              'pricePoints': 'Giá point',
              'onHand': 'Tồn thực',
              'reserved': 'Đang giữ',
              'active': 'Đang bán',
            },
            actions: (p) => ActionButton(
              'Sửa',
              () => submitForm(
                context,
                api,
                'Giá và trạng thái bán',
                '/canteen/products/${p['id']}',
                [
                  FormFieldSpec(
                    'name',
                    'Tên sản phẩm',
                    initial: p['name'].toString(),
                  ),
                  FormFieldSpec(
                    'pricePoints',
                    'Giá point mới',
                    kind: 'points',
                    initial: p['pricePoints'].toString(),
                  ),
                ],
                method: 'PATCH',
                extra: {'active': true, 'expectedVersion': p['priceVersion']},
              ),
              outlined: true,
            ),
          ),
        ),
        Surface(
          title: 'Biến động kho',
          child: RecordTable(
            data: rows(data['/canteen/inventory-movements']),
            columns: const {
              'kind': 'Loại',
              'quantityDelta': 'Thay đổi',
              'reason': 'Lý do',
              'createdAt': 'Thời gian',
            },
          ),
        ),
        Surface(
          title: 'Hoàn point',
          child: RecordTable(
            data: rows(data['/refunds']),
            columns: const {
              'amountPoints': 'Point hoàn',
              'reason': 'Lý do',
              'createdAt': 'Thời gian',
            },
          ),
        ),
      ],
    ),
  );
}
