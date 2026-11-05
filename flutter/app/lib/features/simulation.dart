import 'package:flutter/material.dart';
import '../core/campus_api.dart';
import 'shared.dart';

class SimulationPage extends StatelessWidget {
  final CampusApi api;
  const SimulationPage(this.api, {super.key});
  @override
  Widget build(BuildContext context) => DataPanel(
    api: api,
    paths: [
      '/simulator/status',
      '/simulator/students',
      '/simulator/events',
      if (api.roles.contains('ADMIN')) '/admin/rfid-cards',
      if (api.has('PARKING_STAFF')) '/parking/gate-commands',
    ],
    builder: (context, data) {
      final status = data['/simulator/status'] as Map,
          events = data['/simulator/events'] as Map;
      final contexts = rows(events['contexts']),
          students = rows(data['/simulator/students']);
      final contextMap = {for (final c in contexts) c['id'].toString(): c};
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionTitle(
            'Hardware Simulation Dashboard',
            'RFID được đọc từ phần cứng thật. Face/OCR, cổng và nạp point là mô phỏng có phân quyền.',
          ),
          const ModeLabels(),
          const SizedBox(height: 20),
          Surface(
            title: 'Thiết bị và tín hiệu gần nhất',
            child: RecordTable(
              data: rows(status['devices']),
              columns: const {
                'name': 'Thiết bị',
                'kind': 'Loại',
                'role': 'Vai trò',
                'lastSeenAt': 'Liên hệ gần nhất',
                'lastUidMask': 'UID đã che',
                'ackVersion': 'Phiên bản đã nhận',
              },
            ),
          ),
          Surface(
            title: 'Tình huống nhận diện DEMO',
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                ActionButton(
                  'Tạo Face DEMO',
                  () => submitForm(
                    context,
                    api,
                    'Mô phỏng khuôn mặt',
                    '/simulator/face-events',
                    [
                      FormFieldSpec(
                        'contextId',
                        'Thao tác đang chờ',
                        options: {
                          for (final c in contexts.where(
                            (c) => c['purpose'] != 'ENROLLMENT',
                          ))
                            c['id'].toString(): display(c['purpose']),
                        },
                      ),
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
                          'TIMEOUT': 'Timeout',
                        },
                      ),
                    ],
                  ),
                  icon: Icons.face,
                ),
                if (api.has('PARKING_STAFF'))
                  ActionButton(
                    'Tạo OCR DEMO',
                    () => submitForm(
                      context,
                      api,
                      'Mô phỏng đọc biển số',
                      '/simulator/ocr-observations',
                      [
                        FormFieldSpec(
                          'contextId',
                          'Thao tác xe đang chờ',
                          options: {
                            for (final c in contexts.where(
                              (c) => [
                                'PARKING_ENTRY',
                                'PARKING_EXIT',
                              ].contains(c['purpose']),
                            ))
                              c['id'].toString(): display(c['purpose']),
                          },
                        ),
                        const FormFieldSpec(
                          'rawText',
                          'Biển số',
                          initial: '59-A1 123.45',
                        ),
                        const FormFieldSpec(
                          'scenario',
                          'Tình huống',
                          options: {
                            'SUCCESS': 'Đọc được',
                            'LOW_CONFIDENCE': 'Độ tin cậy thấp',
                            'UNREADABLE': 'Không đọc được',
                            'TIMEOUT': 'Timeout',
                          },
                        ),
                      ],
                    ),
                    outlined: true,
                  ),
                if (api.has('PARKING_STAFF'))
                  ActionButton(
                    'Mô phỏng lỗi cổng',
                    () => submitForm(
                      context,
                      api,
                      'Tình huống barrier',
                      '/simulator/gate-scenarios',
                      [
                        FormFieldSpec(
                          'commandId',
                          'Lệnh cổng',
                          options: {
                            for (final g
                                in rows(data['/parking/gate-commands']).where(
                                  (g) => [
                                    'QUEUED',
                                    'DISPATCHED',
                                    'OPENED',
                                    'UNKNOWN',
                                  ].contains(g['status']),
                                ))
                              g['id'].toString():
                                  '${g['phase']} • ${display(g['status'])}',
                          },
                        ),
                        const FormFieldSpec(
                          'scenario',
                          'Tình huống',
                          options: {
                            'TIMEOUT_UNKNOWN':
                                'Timeout, không rõ đã mở hay chưa',
                            'FAIL_BEFORE_OPEN': 'Thất bại trước khi mở',
                            'LATE_ACK': 'ACK đến trễ',
                          },
                        ),
                      ],
                      extra: {'providerEventId': api.requestKey()},
                    ),
                    outlined: true,
                  ),
              ],
            ),
          ),
          Surface(
            title: 'Thao tác đang chờ',
            child: RecordTable(
              data: contexts,
              columns: const {
                'purpose': 'Mục đích',
                'status': 'Trạng thái',
                'expiresAt': 'Hết hạn',
              },
            ),
          ),
          Surface(
            title: 'Kết quả định danh mới nhất',
            child: RecordTable(
              data: rows(events['identities']),
              columns: const {
                'source': 'Nguồn',
                'expiresAt': 'Hết hạn',
                'consumedAt': 'Đã sử dụng',
              },
              actions: (i) =>
                  api.roles.contains('ADMIN') &&
                      i['consumedAt'] == null &&
                      contextMap[i['contextId']]?['purpose'] == 'ENROLLMENT'
                  ? ActionButton(
                      rows(data['/admin/rfid-cards']).any(
                            (c) =>
                                c['studentId'] == i['studentId'] &&
                                c['status'] == 'ACTIVE',
                          )
                          ? 'Xác nhận thay thẻ'
                          : 'Xác nhận cấp thẻ',
                      () async {
                        final oldCard = rows(data['/admin/rfid-cards'])
                            .where(
                              (c) =>
                                  c['studentId'] == i['studentId'] &&
                                  c['status'] == 'ACTIVE',
                            )
                            .firstOrNull;
                        await api.request(
                          '/rfid-cards',
                          method: 'POST',
                          body: {
                            'enrollmentAssertionId': i['id'],
                            'studentId': i['studentId'],
                            if (oldCard != null) 'replaceCardId': oldCard['id'],
                          },
                        );
                        api.changed();
                        if (context.mounted) {
                          success(context, 'Đã cấp thẻ RFID từ lần quét thật.');
                        }
                      },
                      icon: Icons.nfc,
                    )
                  : const Text('—'),
            ),
          ),
          Surface(
            title: 'Event RFID thật (UID đã che)',
            child: RecordTable(
              data: rows(events['rfid']),
              columns: const {
                'eventId': 'Mã sự kiện',
                'source': 'Nguồn',
                'createdAt': 'Nhận lúc',
              },
            ),
          ),
          Surface(
            title: 'Event Face DEMO',
            child: RecordTable(
              data: rows(events['face']),
              columns: const {
                'scenario': 'Tình huống',
                'source': 'Nguồn',
                'createdAt': 'Thời gian',
              },
            ),
          ),
        ],
      );
    },
  );
}
