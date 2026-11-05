import 'package:flutter/material.dart';
import '../core/campus_api.dart';
import 'shared.dart';

class ParkingPage extends StatefulWidget {
  final CampusApi api;
  const ParkingPage(this.api, {super.key});
  @override
  State<ParkingPage> createState() => _ParkingPageState();
}

class _ParkingPageState extends State<ParkingPage> {
  String? contextId, identityId, observationId, sessionId, quoteId, paymentId;
  int? version;
  String purpose = 'PARKING_ENTRY', plate = '59-A1 123.45';
  String amount = '0';
  CampusApi get api => widget.api;
  Future<void> prepare(
    List<RowData> terminals,
    List<RowData> sessions,
    List<RowData> lots,
    bool exit,
  ) async {
    final candidates = terminals
        .where((r) => r['role'] == (exit ? 'PARKING_EXIT' : 'PARKING_ENTRY'))
        .toList();
    final active = sessions.where((s) => s['status'] == 'ACTIVE').toList();
    final form = await formDialog(
      context,
      exit ? 'Chuẩn bị lấy xe' : 'Chuẩn bị lượt vào bãi',
      [
        FormFieldSpec(
          'deviceId',
          'Nguồn nhận diện',
          options: options(candidates, 'name'),
        ),
        if (exit)
          FormFieldSpec(
            'sessionId',
            'Lượt xe đang gửi',
            options: {
              for (final s in active)
                s['id'].toString(): '${s['entryPlate']} • ${s['studentCode']}',
            },
          )
        else
          FormFieldSpec('lotId', 'Bãi xe', options: options(lots, 'name')),
      ],
    );
    if (form == null) return;
    RowData result;
    if (exit) {
      final selected = active.firstWhere((s) => s['id'] == form['sessionId']);
      version = selected['version'] as int;
      sessionId = selected['id'] as String;
      result = Map<String, dynamic>.from(
        await api.request(
          '/parking/sessions/$sessionId/exit-contexts',
          method: 'POST',
          body: {'deviceId': form['deviceId'], 'expectedVersion': version},
        ),
      );
    } else {
      result = Map<String, dynamic>.from(
        await api.request(
          '/parking/entry-contexts',
          method: 'POST',
          body: form,
        ),
      );
      sessionId = null;
    }
    if (!mounted) return;
    setState(() {
      purpose = exit ? 'PARKING_EXIT' : 'PARKING_ENTRY';
      contextId = result['id'] as String;
      identityId = null;
      observationId = null;
      quoteId = null;
      paymentId = null;
    });
    api.changed();
  }

  @override
  Widget build(BuildContext context) {
    final paths = [
      '/parking/lots',
      '/parking/sessions',
      '/parking/gate-commands',
      '/simulator/status',
      '/simulator/students',
      '/simulator/events',
      if (sessionId != null) '/parking/sessions/$sessionId',
    ];
    return DataPanel(
      key: ValueKey(sessionId),
      api: api,
      paths: paths,
      builder: (context, data) {
        final sessions = rows(data['/parking/sessions']),
            gates = rows(data['/parking/gate-commands']);
        final terminals = rows((data['/simulator/status'] as Map)['devices']);
        final students = rows(data['/simulator/students']);
        final identities =
            rows((data['/simulator/events'] as Map)['identities'])
                .where(
                  (i) => i['contextId'] == contextId && i['consumedAt'] == null,
                )
                .toList();
        final actualIdentity =
            identityId ??
            (identities.isEmpty ? null : identities.first['id'] as String);
        final detail = data['/parking/sessions/$sessionId'] as Map?;
        final payments = rows(detail?['payments']);
        final approval = payments
            .where((p) => p['id'] == paymentId && p['approvalId'] != null)
            .firstOrNull;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionTitle(
              'Điều hành bãi xe',
              'RFID thật hoặc Face DEMO → OCR DEMO → xác minh xe → cổng mô phỏng.',
            ),
            const ModeLabels(),
            const SizedBox(height: 20),
            Surface(
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  ActionButton(
                    'Chuẩn bị xe vào',
                    () => prepare(
                      terminals,
                      sessions,
                      rows(data['/parking/lots']),
                      false,
                    ),
                    icon: Icons.login,
                  ),
                  ActionButton(
                    'Chuẩn bị xe ra',
                    () => prepare(
                      terminals,
                      sessions,
                      rows(data['/parking/lots']),
                      true,
                    ),
                    icon: Icons.logout,
                    outlined: true,
                  ),
                ],
              ),
            ),
            if (contextId != null)
              Surface(
                title: purpose == 'PARKING_ENTRY'
                    ? 'Lượt vào đang xử lý'
                    : 'Lượt ra đang xử lý',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      actualIdentity == null
                          ? 'Chờ quét thẻ MFRC522 thật, hoặc chọn Face DEMO bên dưới.'
                          : 'Đã nhận diện sinh viên. Hãy xác minh biển số.',
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        ActionButton(
                          'Face DEMO',
                          () async {
                            final f = await formDialog(
                              context,
                              'Nhận diện khuôn mặt mô phỏng',
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
                                  },
                                ),
                              ],
                            );
                            if (f == null) return;
                            final r = await api.request(
                              '/simulator/face-events',
                              method: 'POST',
                              body: {...f, 'contextId': contextId},
                            );
                            if (mounted) {
                              setState(
                                () => identityId =
                                    r['identityAssertionId'] as String,
                              );
                            }
                            api.changed();
                          },
                          outlined: true,
                          icon: Icons.face,
                        ),
                        if (quoteId == null)
                          ActionButton('Hủy lần xác thực', () async {
                            await api.request(
                              '/device-contexts/$contextId/cancel',
                              method: 'POST',
                              body: {
                                'reason':
                                    'Nhân viên hủy để chuẩn bị lại lượt xác thực',
                              },
                            );
                            if (mounted) {
                              setState(() {
                                contextId = null;
                                identityId = null;
                                observationId = null;
                              });
                            }
                            api.changed();
                          }, outlined: true),
                        ActionButton(
                          'Nhập biển số OCR DEMO',
                          () async {
                            final f = await formDialog(
                              context,
                              'Biển số mô phỏng',
                              [
                                FormFieldSpec(
                                  'rawText',
                                  'Biển số',
                                  initial: plate,
                                ),
                                const FormFieldSpec(
                                  'scenario',
                                  'Tình huống OCR',
                                  options: {
                                    'SUCCESS': 'Đọc được',
                                    'LOW_CONFIDENCE': 'Độ tin cậy thấp',
                                    'UNREADABLE': 'Không đọc được',
                                  },
                                ),
                              ],
                            );
                            if (f == null) return;
                            final r = await api.request(
                              '/simulator/ocr-observations',
                              method: 'POST',
                              body: {...f, 'contextId': contextId},
                            );
                            if (mounted) {
                              setState(() {
                                observationId = r['id'] as String;
                                plate = f['rawText'] as String;
                              });
                            }
                            api.changed();
                          },
                          outlined: true,
                          icon: Icons.directions_car_outlined,
                        ),
                        if (observationId != null)
                          ActionButton(
                            'Xác minh / sửa OCR',
                            () => submitForm(
                              context,
                              api,
                              'Lưu xác minh biển số',
                              '/parking/ocr-observations/$observationId/corrections',
                              [
                                FormFieldSpec(
                                  'correctedPlate',
                                  'Biển số đã xác minh',
                                  initial: plate,
                                ),
                                const FormFieldSpec(
                                  'reason',
                                  'Lý do xác minh',
                                  kind: 'multiline',
                                ),
                              ],
                            ),
                            outlined: true,
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Biển số: ${observationId == null ? 'Chưa nhập' : plate}',
                    ),
                    const SizedBox(height: 16),
                    ActionButton(
                      purpose == 'PARKING_ENTRY'
                          ? 'Tạo lượt vào bãi'
                          : 'Tính phí lấy xe',
                      actualIdentity == null || observationId == null
                          ? null
                          : () async {
                              if (purpose == 'PARKING_ENTRY') {
                                await api.request(
                                  '/parking/entries',
                                  method: 'POST',
                                  body: {
                                    'identityAssertionId': actualIdentity,
                                    'ocrObservationId': observationId,
                                  },
                                );
                                if (mounted) setState(() => contextId = null);
                              } else {
                                final q = await api.request(
                                  '/parking/sessions/$sessionId/exit-quotes',
                                  method: 'POST',
                                  body: {
                                    'identityAssertionId': actualIdentity,
                                    'ocrObservationId': observationId,
                                    'expectedVersion': version,
                                  },
                                );
                                if (mounted) {
                                  setState(() {
                                    quoteId = q['quoteId'] as String;
                                    paymentId = q['paymentId'] as String?;
                                    amount = q['amountPoints'] as String;
                                  });
                                }
                              }
                              api.changed();
                            },
                      icon: Icons.check_circle_outline,
                    ),
                    if (quoteId != null) ...[
                      const SizedBox(height: 20),
                      Text(
                        'Phí lấy xe: ${pointText(amount)}',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(
                        amount == '0'
                            ? 'Có chính sách miễn phí hợp lệ.'
                            : approval == null
                            ? 'Sinh viên cần mở Ví & thanh toán trên tài khoản của mình để xác nhận bằng PIN.'
                            : 'Sinh viên đã xác nhận. Có thể yêu cầu mở cổng mô phỏng.',
                      ),
                      const SizedBox(height: 12),
                      ActionButton(
                        'Yêu cầu mở cổng',
                        amount != '0' && approval == null
                            ? null
                            : () async {
                                await api.request(
                                  '/parking/sessions/$sessionId/exit-authorizations',
                                  method: 'POST',
                                  body: {
                                    'quoteId': quoteId,
                                    'expectedVersion': version,
                                    if (approval != null)
                                      'approvalId': approval['approvalId'],
                                  },
                                );
                                if (mounted) setState(() => contextId = null);
                                api.changed();
                              },
                        icon: Icons.lock_open,
                      ),
                    ],
                  ],
                ),
              ),
            Surface(
              title: 'Lệnh cổng mô phỏng',
              child: RecordTable(
                data: gates,
                columns: const {
                  'phase': 'Hướng',
                  'status': 'Trạng thái',
                  'createdAt': 'Thời gian',
                },
                actions: (g) => Wrap(
                  spacing: 8,
                  children: [
                    if (['OPENED', 'UNKNOWN'].contains(g['status']))
                      ActionButton('Xe đã qua', () async {
                        await api.request(
                          '/parking/gate-commands/${g['id']}/passage-confirmations',
                          method: 'POST',
                          body: {
                            'reason': 'Nhân viên xác nhận passage mô phỏng',
                            'providerEventId': api.requestKey(),
                          },
                        );
                        api.changed();
                      }, icon: Icons.done),
                    if (['OPENED', 'UNKNOWN'].contains(g['status']))
                      ActionButton('Xe chưa qua', () async {
                        final current = await api.request(
                          '/parking/sessions/${g['sessionId']}',
                        );
                        if (!context.mounted) return;
                        await submitForm(
                          context,
                          api,
                          'Xác minh xe chưa qua cổng',
                          '/parking/sessions/${g['sessionId']}/exception-resolutions',
                          const [
                            FormFieldSpec('reason', 'Lý do', kind: 'multiline'),
                            FormFieldSpec(
                              'evidenceNote',
                              'Bằng chứng xác minh',
                              kind: 'multiline',
                            ),
                          ],
                          extra: {
                            'resolution': g['phase'] == 'ENTRY'
                                ? 'CANCEL_ENTRY'
                                : 'VEHICLE_STILL_INSIDE',
                            'expectedVersion': current['version'],
                          },
                        );
                      }, outlined: true),
                  ],
                ),
              ),
            ),
            Surface(
              title: 'Lịch sử và phiên hiện hành',
              child: RecordTable(
                data: sessions,
                columns: const {
                  'entryPlate': 'Biển số',
                  'studentCode': 'Sinh viên',
                  'status': 'Trạng thái',
                  'entrySource': 'Nguồn',
                  'enteredAt': 'Vào bãi',
                },
                actions: (s) => s['status'] == 'COMPLETED'
                    ? ActionButton(
                        'Đối soát thu phí',
                        () => submitForm(
                          context,
                          api,
                          'Chỉ xác nhận khi đã chứng minh xe chưa ra; hoàn phí cũ và mở chu kỳ mới',
                          '/parking/sessions/${s['id']}/exception-resolutions',
                          const [
                            FormFieldSpec('reason', 'Lý do', kind: 'multiline'),
                            FormFieldSpec(
                              'evidenceNote',
                              'Bằng chứng xe chưa ra',
                              kind: 'multiline',
                            ),
                          ],
                          extra: {
                            'resolution': 'REVERSE_CAPTURE',
                            'expectedVersion': s['version'],
                          },
                        ),
                        outlined: true,
                      )
                    : const Text('—'),
              ),
            ),
          ],
        );
      },
    );
  }
}
