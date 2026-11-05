# API contracts và provider schemas

> Mục lục route hiện hành: [api-routes.md](api-routes.md), sinh từ 124 declarations trong app.ts. Các lệnh business thường trả 200, scan/Face accepted có thể trả 202; field thực thi xem handler/service.

> Thiết kế đã được người dùng duyệt ngày 05/11/2026. Đây là tài liệu thiết kế gốc; xem [trạng thái triển khai](implementation-status.md) và [runbook](SETUP_SMART_CAMPUS.md) cho code, lệnh chạy và bằng chứng hiện hành.

05/11/2026, **đề xuất v1 chờ duyệt**, chưa implement. API prototype hiện tại là `/v1/device-events` chỉ ATTENDANCE và khác contract bên dưới. Không thử gọi endpoint thiết kế rồi kết luận code hiện có lỗi.

## 1. Quy ước HTTP và auth

- Base `/api/v1` cho REST nghiệp vụ; `/healthz`, `/readyz` và Socket.IO namespace `/campus` nằm ngoài base này. JSON UTF-8, field camelCase, ID UUID, time ISO-8601 UTC. Point/amount BIGINT trả chuỗi số nguyên không dấu, delta ledger cho phép dấu âm. Trường lạ bị 400. List dùng `?cursor=...&limit=20`, tối đa 100, trả `items,nextCursor`.
- User/device/internal service là ba loại credential riêng. `Authorization: Bearer <opaque-token>`; server tự xác định actor/scope. Web refresh dùng cookie và CSRF/Origin check; không chấp nhận user token cho device callback hoặc ngược lại.
- Response thành công `{data: ..., requestId: "..."}`; lỗi `{error:{code,message,details?},requestId}`. `message` tiếng Việt, client điều khiển bằng code. Không trả stack trace/SQL/secret.
- 200 đọc/update/replay; 201 resource mới; 202 đã nhận nhưng chờ xử lý; 400 schema; 401 thiếu/sai credential; 403 quyền; 404 không có/không được thấy tài nguyên; 409 conflict/duplicate khác payload; 422 vi phạm nghiệp vụ; 429 rate limit + Retry-After; 503 dependency/ready/unknown outcome cần tra trạng thái.
- Mọi mutation nghiệp vụ trừ login/refresh cần `Idempotency-Key` 16–128 ký tự ASCII do client tạo, scope actor+method+route; device scan thay bằng eventId. Body canonical có version, không đưa PIN vào log/cache response. Lặp cùng key trả cùng HTTP/result đã commit; key khác payload trả 409. Unique business key vẫn bảo vệ nếu dùng key mới.
- Update tài nguyên mutable gửi `expectedVersion`; sai version → 409 VERSION_CONFLICT, không last-write-wins ngầm.

Ví dụ lỗi thiếu point:

```json
{
  "error": {
    "code": "INSUFFICIENT_POINTS",
    "message": "Ví chưa đủ point. Vui lòng nạp bổ sung.",
    "details": {"requiredPoints":"5000","availablePoints":"3000","shortfallPoints":"2000"}
  },
  "requestId": "trace-example"
}
```

## 2. Auth, hồ sơ, thẻ và consent

| Method/path | Actor/quyền | Request → kết quả |
| --- | --- | --- |
| POST `/auth/login` | Public, rate limited | email/password → access token/expiry + refresh; không cho body tự chọn role |
| POST `/auth/refresh` | Refresh credential + CSRF với web | rotate token; reuse revoked family → 401 |
| POST `/auth/logout` | User/refresh session | revoke current family; replay an toàn |
| GET/PATCH `/me` | User active | hồ sơ của mình; chỉ field cho phép, không đổi role/studentCode |
| GET `/me/notifications`; POST `/{id}/read` | Chủ notification | snapshot/read marker |
| GET `/me/cards`; POST `/me/cards/{id}/report-lost` | STUDENT sở hữu | reason → LOST ngay, revoke pending assertion/approval |
| POST `/enrollment-contexts` | ADMIN + device.configure | studentId/deviceId/expiry → context role enrollment |
| POST `/rfid-cards` | ADMIN + identity card grant | enrollmentAssertionId/studentId/replaceCardId? → thẻ ACTIVE; consume assertion thật, unique; không nhận UID client thường |
| POST `/rfid-cards/{id}/revoke` | ADMIN | reason/expectedVersion → REVOKED |
| GET/POST `/me/vehicles`; POST `/{id}/revocation-requests` | STUDENT | plate/type hoặc reason; chỉ sửa/thu hồi xe có quyền, không ảnh hưởng session mở ngầm |
| POST `/vehicle-authorizations` | ADMIN hoặc grant riêng | vehicleId/studentId/validity/reason → quyền dùng xe |
| GET/POST `/me/biometric-consents`; POST `/{id}/revoke` | STUDENT | purpose/policyVersion/explicitConsent; backend gán source phù hợp; revoke audit |
| POST `/me/biometric-profiles/enrollment-requests` | STUDENT | consentId; DEMO chỉ fixture, chưa nhận ảnh/embedding thật |
| DELETE `/me/biometric-profiles/{id}` | STUDENT sở hữu | 202 deletion job → GET profile trả ERASED khi xong, không chỉ ẩn UI |
| PUT `/me/wallet-pin` | STUDENT, recent auth | oldPin nếu có/newPin → không trả hash; revoke approval/PIN version cũ |

Public signup không tự cấp STUDENT/LECTURER hay studentId: MVP admin provision hoặc import synthetic có kiểm; việc nối SSO trường là quyết định sau.

## 3. Device API và RFID thật

| Method/path | Actor | Contract |
| --- | --- | --- |
| POST `/admin/devices` | ADMIN device.configure | name/kind/scope → deviceId + credential hiển thị một lần |
| POST `/admin/devices/{id}/rotate-credential` | ADMIN | reason → credential mới; thu hồi cũ theo cửa sổ rotation có audit |
| PUT `/admin/devices/{id}/role` | ADMIN | role/scope/expectedVersion/reason → pending configVersion; 409 DEVICE_BUSY nếu context/command chưa giải quyết |
| GET `/device/config` | Device | deviceId/role/configVersion/context/heartbeat interval; không secret khác |
| POST `/device/config-ack` | Device | deviceId/configVersion → config đã active sau ACK |
| POST `/device/heartbeat` | Device | firmwareVersion/configVersion → serverTime/nextAction; không UID |
| POST `/device/challenges` | Device | deviceId/configVersion/contextId → nonce/challengeId/serverTime/expiresAt |
| POST `/device-events` | Device | scan schema bên dưới → stored ACK; identity/context operation reference |
| GET `/device-events/{eventId}` | Device sở hữu | stored ACK + trạng thái hiện tại và serverTime; không lộ event thiết bị khác |
| GET `/device/pending-actions` | Device | danh sách context chưa xong để recovery sau reboot; không tự execute lại cổng/charge |
| GET `/device/actions/{id}` | Device được gắn context | status/outcome/lcdLines/validUntil; firmware poll đến terminal, hết hạn phải tra app |

Scan request, ví dụ synthetic (không credential thật):

```json
{
  "schemaVersion": 1,
  "eventId": "11111111-1111-4111-8111-111111111111",
  "deviceId": "22222222-2222-4222-8222-222222222222",
  "deviceRole": "PARKING_ENTRY",
  "configVersion": 3,
  "contextId": "33333333-3333-4333-8333-333333333333",
  "challengeId": "44444444-4444-4444-8444-444444444444",
  "nonce": "server-issued-random-value",
  "occurredAt": "2026-11-05T03:00:00.000Z",
  "credential": {"type":"RFID_UID","uid":"01020304"}
}
```

UID uppercase hex 8/14/20 ký tự, server padding không thể phục hồi byte đã mất nên firmware phải gửi đúng. DeviceId/role chỉ assertion phải khớp credential và config server, không tự định tuyến theo body. New event: nonce còn hạn, chưa dùng, đúng context, thời gian lệch <=120s; server time căn cứ tính nghiệp vụ. Duplicate lookup sau device auth và trước challenge expiry check; cùng payload trả ACK cũ kể cả challenge đã consume, khác payload 409. Không replay side effect từ ACK.

ACK có thể là 202 chờ staff/PIN:

```json
{
  "data": {
    "eventId":"11111111-1111-4111-8111-111111111111",
    "source":"REAL",
    "outcome":"IDENTIFIED",
    "actionId":"55555555-5555-4555-8555-555555555555",
    "actionStatus":"AWAITING_OCR",
    "lcdLines":["THE HOP LE","CHO XAC NHAN"],
    "validUntil":"2026-11-05T03:01:00.000Z"
  },
  "requestId":"trace-example"
}
```

LCD tối đa 16 ký tự/dòng, tiếng Việt không dấu. `IDENTIFIED` không phải `PAID`, không mở cổng từ LCD; firmware chỉ báo thành công nghiệp vụ khi poll action terminal đúng event/context và còn hiệu lực. Không echo raw UID lên staff event log; mask `****0304`. Response business codes: CARD_NOT_ACTIVE, STUDENT_INACTIVE, DEVICE_ROLE_MISMATCH, DEVICE_BUSY, CONTEXT_EXPIRED, CHALLENGE_EXPIRED, REPLAY_DETECTED, IDEMPOTENCY_CONFLICT. 429/5xx/timeout retry giữ nguyên event+payload có backoff, tối đa 3; 4xx hiển thị từ chối và đợi thao tác mới, không halt vô hạn như prototype.

## 4. Parking API

| Method/path | Quyền | Request và hành vi |
| --- | --- | --- |
| POST `/parking/entry-contexts` | PARKING_STAFF | lotId/deviceId → context cho scan; Face DEMO dùng virtual context có simulator grant |
| POST `/parking/entries` | PARKING_STAFF | identityAssertionId/contextId/ocrObservationId → 201 PENDING_ENTRY, gate command; backend tự tìm xe/authorization/policy |
| GET `/parking/sessions`; GET `/{id}` | Staff theo lot; STUDENT chỉ `/me/parking-sessions` | current state, plate đã che theo quyền, fee/payment/gate status |
| POST `/parking/sessions/{id}/exit-contexts` | PARKING_STAFF | deviceId/expectedVersion → context bound session |
| POST `/parking/sessions/{id}/exit-quotes` | PARKING_STAFF | identityAssertionId/ocrObservationId/expectedVersion → quoteId/settlementCycle/amount/policy/expiry/approvalRequired, paymentId nếu phí>0; reject mismatched owner/plate |
| POST `/parking/sessions/{id}/exit-authorizations` | PARKING_STAFF | quoteId/approvalId/expectedVersion → 202 EXIT_PENDING + hold + command; approval bắt buộc nếu amount>0 |
| POST `/parking/ocr-observations/{id}/corrections` | Staff có grant review | correctedPlate/reason/evidenceRef/expectedVersion → append correction; confidence gốc không bị thay thành 1 |
| POST `/parking/sessions/{id}/exceptions` | parking.exception.resolve | type/reason/evidenceRef/proposedAction → case; không tự chuyển trạng thái |
| POST `/parking/sessions/{id}/exception-resolutions` | parking.exception.resolve; waiver thêm parking.fee.waive | resolution/reason/evidenceRef/expectedVersion → transition guard + tài chính tương ứng |
| POST `/parking/gate-commands/{id}/passage-confirmations` | PARKING_STAFF có scope, provider chỉ simulator dev/test | observedPassage/reason/evidenceRef → ghi durable event + capture nếu exit; không nhận source client tự khai |
| GET `/parking/gate-commands/{id}` | Staff scope | QUEUED/DISPATCHED/OPENED/PASSAGE_CONFIRMED/FAILED/UNKNOWN/REVOKED |
| GET/POST `/admin/parking-fee-policies`; POST `/{id}/activate` | ADMIN policy grant | versioned mode/parameters/effective window, activation audit |
| POST `/admin/parking-passes` | ADMIN | student/vehicle/lot/validity/type → entitlement |

OCR observation do demo provider tạo, client chỉ nhận ID; không cho POST parking nhận object `{source:'REAL',confidence:1}`. Mọi override có state guards, không có endpoint `forceComplete=true` chung chung. Có nhiều payment attempt nhưng chỉ một capture/session/settlementCycle. Chỉ full reversal có bằng chứng xe chưa ra và fence lệnh cũ mới cho resolution tăng cycle; partial refund không cho charge lại. Trường hợp phí 0 trả approvalRequired=false kèm entitlement reason, không tạo payment/hold/ledger delta=0. approvalId trong exit-authorizations chỉ được bỏ khi quote có phí 0 đã kiểm server.

## 5. Wallet và payment API

| Method/path | Quyền | Request → kết quả |
| --- | --- | --- |
| GET `/me/wallet`; GET `/me/wallet/ledger`; GET `/me/wallet/transactions` | STUDENT | posted/held/availablePoints; transaction/entry source, receipt; không chỉ balance cache |
| POST `/me/topups` | STUDENT, dev/test MOCK | requestedVnd hoặc points theo contract duy nhất; đề xuất requestedVnd chuỗi dương → backend conversion snapshot, PENDING/mock=true |
| GET `/me/topups/{id}` | Chủ topup | status/amount/mock label; không có trường client-set SUCCEEDED |
| POST `/internal/mock-payment-callbacks` | Mock worker credential, dev/test only | callbackId/topupId/providerReference/status/amountPoints/bodyHash → verify/match → post một lần |
| GET `/me/payment-requests`; GET `/me/payments/{id}` | STUDENT sở hữu | merchant/order/session/amount/device/expiry, approvalRequired |
| POST `/me/payments/{id}/approvals` | STUDENT recent auth | pin hoặc method APP với recent-auth challenge đã kiểm, expectedSourceVersion → approvalId bound amount; không nhận studentId |
| POST `/refunds` | canteen.refund hoặc parking.exception.resolve | originalTransactionId/items?/amountPoints/reason/restock info → refund receipt theo quyền/limits |
| GET `/refunds/{id}` | Staff scope/chủ giao dịch read-only | original reference, amount/status |
| POST `/admin/wallet-adjustments` | wallet.adjust | studentId/deltaPoints/reason/expectedVersion → balanced posting + audit |
| GET `/admin/wallet-reconciliation` | ADMIN tài chính | discrepancy summary và references; không sửa ledger qua GET |

Trusted callback dùng bearer riêng, private network + TLS; mock client chọn scenario không được chọn amount credited hoặc bypass worker. Gateway thật tương lai có adapter xác minh signature/status server-to-server. Amount callback không khớp topup snapshot → 422 CALLBACK_AMOUNT_MISMATCH, không cộng point.

## 6. Cantin API

| Method/path | Quyền | Request → kết quả |
| --- | --- | --- |
| GET `/canteen/categories`; GET `/canteen/products` | User active | catalog, giá point, available stock phù hợp quyền |
| POST/PATCH `/canteen/categories`; POST/PATCH `/canteen/products` | CANTEEN_STAFF catalog grant | field allowlist + expectedVersion, price server version |
| POST `/canteen/inventory-adjustments` | CANTEEN_STAFF inventory grant | productId/delta/reason/expectedVersion → movement, không âm tồn/reserved |
| GET `/canteen/inventory-movements` | Staff scope | lịch sử nhập/reserve/bán/return |
| POST `/canteen/orders` | CANTEEN_STAFF | items:[productId,quantity] → backend total/snapshot/reservation/expiry; không nhận giá |
| PATCH `/canteen/orders/{id}` | Staff scope | items/expectedVersion → reprice/reserve/invalidate approval atomically |
| POST `/canteen/orders/{id}/checkout-contexts` | CANTEEN_STAFF | deviceId/expectedVersion → CANTEEN_POS context |
| POST `/canteen/orders/{id}/identify` | CANTEEN_STAFF | identityAssertionId/contextId → bind student, create payment request; không charge |
| POST `/canteen/orders/{id}/payments` | CANTEEN_STAFF | paymentId/approvalId/expectedVersion → atomic charge+stock+COMPLETED receipt |
| POST `/canteen/orders/{id}/cancel` | Staff scope | reason/version → release reservation nếu chưa completed |
| GET `/canteen/orders`; GET `/{id}`; GET `/me/canteen-orders` | Staff scope/chủ | order/payment/refund/receipt snapshot |

Errors: INSUFFICIENT_STOCK, RESERVATION_EXPIRED, PRODUCT_UNAVAILABLE, ORDER_VERSION_CHANGED, APPROVAL_REQUIRED/EXPIRED, PAYMENT_ALREADY_CAPTURED. Sau lỗi mạng client GET order/payment hoặc retry cùng key, không tạo đơn mới tự động.

## 7. Attendance/học vụ/realtime

| Method/path | Quyền | Contract |
| --- | --- | --- |
| GET `/lecturer/class-sections` | LECTURER | chỉ phân công còn hiệu lực |
| POST `/attendance/sessions` | LECTURER assigned | scheduleId/deviceIds → SCHEDULED; backend xác định room/section/time |
| POST `/attendance/sessions/{id}/open` | LECTURER assigned | expectedVersion → OPEN + roster snapshot + device binding |
| POST `/attendance/sessions/{id}/close`; POST `/{id}/cancel` | LECTURER assigned | reason khi cancel, version → đóng atomically; close tạo ABSENT |
| GET `/attendance/sessions/{id}`; GET `/{id}/records` | GV assigned / SV chỉ own record | state/version/record list theo quyền |
| POST `/attendance/sessions/{id}/adjustment-requests` | STUDENT roster | requestedStatus/reason, tự suy studentId từ token |
| POST `/attendance/adjustment-requests/{id}/decisions` | GV assigned | APPROVED/REJECTED/reason → correction/audit |
| PATCH `/attendance/records/{id}` | GV assigned correction grant | status/reason/expectedVersion → correction history + audit |
| GET `/attendance/sessions/{id}/report?format=csv`; GET `/me/attendance` | GV assigned / chủ SV | report scoped; escape formula cells |
| GET/POST/PATCH `/admin/academic-terms`, `/courses`, `/class-sections`, `/classrooms`, `/schedules` | ADMIN academic grant | validated CRUD soft status, expectedVersion |
| POST `/admin/class-sections/{id}/enrollments`; POST `/{id}/teaching-assignments` | ADMIN academic grant | studentIds/lecturerId+validity; không tự đăng ký để vượt roster |

Không có production endpoint cho student tự POST studentId/face confidence để điểm danh. Trong dev/test chỉ route simulator ingest có quyền. Errors: SESSION_NOT_OPEN, NOT_ENROLLED, DEVICE_ROOM_MISMATCH, OUTSIDE_TIME_WINDOW, NOT_ASSIGNED_LECTURER; duplicate đúng event/student trả record cũ.

Socket.IO namespace `/campus`, handshake access token, không token query string. Server quyết định join `user:{id}`, `attendance:{sessionId}`, `parking:{lotId}`, `pos:{contextId}`, `device:{id}` sau scope check; không chấp nhận client tự join room arbitrary. Revoke/expiry disconnect và reauth. Event envelope `{eventId,type,aggregateId,aggregateVersion,occurredAt,source,data}`. Types: `attendance.recorded`, `attendance.session.closed`, `parking.session.changed`, `payment.changed`, `wallet.changed`, `device.status.changed`, `notification.created`. Không UID/PIN/embedding trong payload. At-least-once: client dedupe eventId; reconnect GET REST snapshot, không suy có đủ event.

## 8. Simulator/admin/health

Chỉ register simulator khi dev/test + SIMULATOR_ENABLED + simulator.use; source/purpose do server set và audit actor. Production route 404 và guard từ chối start cấu hình DEMO, không chỉ ẩn UI.

| Method/path | Request/kết quả |
| --- | --- |
| GET `/simulator/status`; GET `/simulator/students` | Provider modes, fixture danh sách synthetic, device lastSeen/last masked UID/config; không trả credentials |
| POST `/simulator/face-events` | contextId/deviceId/sessionId nếu attendance/studentFixtureId/scenario/eventId → provider result và domain outcome qua chung service |
| POST `/simulator/ocr-observations` | contextId/rawText/scenario → stored observationId/raw+normalized/confidence/source DEMO |
| POST `/simulator/gate-scenarios` | commandId/scenario OPENED/FAIL_BEFORE_OPEN/TIMEOUT_UNKNOWN/LATE_ACK/PASSAGE → durable provider event; không cho user bỏ qua state guard |
| POST `/simulator/mock-topup-scenarios` | topupId/scenario SUCCESS/FAIL/DUPLICATE_CALLBACK/DELAY → yêu cầu worker, không trực tiếp cộng point |
| GET `/simulator/events`; GET `/simulator/events/{id}` | read model event/result/linked business IDs theo scope, không SQL console |
| GET/POST/PATCH `/admin/users`; GET `/admin/roles`; PUT `/admin/users/{id}/roles` | ADMIN user/role grant, field allowlist, audit; ngăn tự gỡ admin cuối cùng |
| GET `/admin/audit-logs`; GET `/admin/reports` | quyền audit/report scope, filter/cursor; không raw biometric |
| GET `/healthz`; GET `/readyz` | public liveness/ready tối thiểu; ready 503 nếu DB/migration/provider guard chưa đạt, chi tiết ops có auth |

## 9. Provider ports ổn định (đề xuất nội bộ, không phải API thư viện có sẵn)

Mọi result schema version 1, correlation eventId/deviceId/timestamp và source. IDs là do server/context cấp; provider không tự tin payload user. Các signature dưới đây là interface **sẽ viết**, không khẳng định package nào cung cấp sẵn.

| Port/method | Input | Output |
| --- | --- | --- |
| CameraCaptureProvider.capture | trusted context, captureRequestId | CaptureResult: captureId/evidenceRef nullable/capturedAt/source/metadata |
| FaceRecognitionProvider.recognize | captureRef, purpose, allowedIdentityScope | FaceResult schema bên dưới; scope lớp/fixture do server kiểm |
| LivenessProvider.evaluate | captureRef/context | LivenessResult: status PASS/FAIL/UNKNOWN, confidence nullable, source, event/device/timestamp; DemoLivenessProvider không là PAD thật |
| LicensePlateRecognitionProvider.recognize | captureRef hoặc demoObservation context | OcrResult schema bên dưới |
| GateControllerProvider.execute/query | commandId/sessionId/phase/expiresAt/fencingVersion | GateResult: status DISPATCHED/OPENED/FAILED/UNKNOWN, passage CONFIRMED/NOT_CONFIRMED/UNKNOWN, providerEventId/source SIMULATOR hoặc REAL |

Implementations MVP: DemoCameraProvider, DemoFaceProvider, DemoLivenessProvider, DemoOCRProvider, SimulatedGateProvider. DEMO Face identity chỉ fixture synthetic trong DB dev/test; scenario gồm SUCCESS, UNKNOWN, LOW_CONFIDENCE, LIVENESS_FAIL, MULTIPLE_FACES, TIMEOUT. Low confidence dùng policy fixture, không tuyên bố threshold dùng được ngoài thực tế.

```json
{
  "schemaVersion":1,
  "eventId":"11111111-1111-4111-8111-111111111111",
  "deviceId":"22222222-2222-4222-8222-222222222222",
  "timestamp":"2026-11-05T03:00:00.000Z",
  "source":"DEMO",
  "identity":{"studentId":"66666666-6666-4666-8666-666666666666"},
  "confidence":0.98,
  "livenessStatus":"PASS",
  "recognitionStatus":"MATCH",
  "evidenceRef":null,
  "modelVersion":"demo-v1"
}
```

Face thất bại: identity=null; recognitionStatus MATCH/NO_MATCH/LOW_CONFIDENCE/ERROR; confidence number [0,1] hoặc null khi không đo được; liveness PASS/FAIL/UNKNOWN. MATCH vẫn bị reject nếu liveness!=PASS hoặc ngoài scope/consent. Confidence fixture không có ý nghĩa xác suất đo thực nghiệm.

```json
{
  "schemaVersion":1,
  "eventId":"77777777-7777-4777-8777-777777777777",
  "deviceId":"22222222-2222-4222-8222-222222222222",
  "timestamp":"2026-11-05T03:00:01.000Z",
  "rawText":"59-A1 123.45",
  "normalizedPlate":"59A112345",
  "confidence":0.95,
  "evidenceRef":null,
  "source":"DEMO",
  "recognitionStatus":"READ",
  "normalizationVersion":"vn-plate-v1"
}
```

OCR status READ/UNREADABLE/LOW_CONFIDENCE/ERROR; raw/normalized null khi unreadable. Normalization do backend/shared normalizer kiểm lại, không mù quáng tin string provider. Correction là record khác tham chiếu observation gốc. evidenceRef là ID private store/fixture, không URL bất kỳ do user truyền để backend fetch (tránh SSRF).

Timeout provider map PROVIDER_TIMEOUT, không fallback từ fail/unknown sang MATCH. Event IDs/payload schema phải có contract tests với adapter giả khi triển khai; chúng không thay hardware acceptance. API OpenAPI machine-readable và codegen Flutter sẽ được tạo cùng GĐ2–7, chưa có trong giai đoạn tài liệu này.
