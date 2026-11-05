# Trạng thái triển khai Smart Campus

Người dùng đã duyệt thiết kế ngày 05/11/2026. Phần mềm đã triển khai các phân hệ dưới đây. **Chưa đóng nghiệm thu toàn bộ MVP vì chưa flash/quét RFID/LCD thật.** Trạng thái PASS chỉ áp dụng đúng phạm vi bằng chứng.

Bản đồ các tệp: [implementation-files.md](implementation-files.md).

## Source và hành vi

| Phần | File chính | Nội dung |
| --- | --- | --- |
| API/platform | backend/server.ts, backend/src/{app,platform}.ts | REST /api/v1, validation, idempotency, rate limit DB, structured errors, health/readiness |
| Auth | backend/src/auth.ts | Opaque sessions, refresh rotation/reuse revoke, RBAC/resource scope; web HttpOnly cookie + CSRF, native secure refresh storage |
| Identity/device | backend/src/{devices,database}.ts | Student/card/vehicle/consent/profile; enrollment, config/ACK/challenge/event retry; UID HMAC server |
| Ví | backend/src/wallet.ts, SQL post_wallet | Double-entry append-only, top-up MOCK, PIN/app approval, limits, holds/capture/refund/reversal/reconciliation |
| Bãi xe | backend/src/parking.ts | OCR DEMO/correction, policy/pass, occupancy, quote/approval, OPENED khác PASSAGE, UNKNOWN/reconciliation/fencing |
| Cantin | backend/src/canteen.ts | Server price, stock reservation, identity/approval, atomic payment/order/inventory, expiry/cancel/refund |
| Điểm danh | backend/src/attendance.ts | Assigned lecturer mở phiên đúng schedule/room/device, roster snapshot, PRESENT/LATE/ABSENT/EXCUSED, corrections/audit/CSV |
| Providers/realtime | backend/src/{providers,worker}.ts | 5 provider interfaces, fixture DEMO, gate simulator, authenticated Socket.IO rooms, outbox lease/retry/dead letter |
| Web/Android | flutter/app/lib/{main.dart,core,features} | Tiếng Việt, responsive, màn hình từng role, Hardware Simulation Dashboard, dữ liệu API |
| ESP32 | firmware/smart_campus | TLS CA/NTP, config/ACK, pending NVS, bounded retry, LCD action polling; chưa flash |
| Vận hành | deploy, tools/*campus*, tools/verify-flutter.ps1 | Compose bootstrap/runtime/proxy; native SCRAM DB; secret sinh local, builds/packaging |

Migrations 002-campus.sql và 003-operational-indexes.sql thêm schema campus, giữ public. Runtime DB role không sửa ledger/cache balance trực tiếp. Prototype vẫn ở backend/app.ts, backend/prototype-server.ts, database/001.sql; camera spike ở flutter/app/lib/legacy.

Giữ Express + pg + SQL migrations; chưa thêm ORM/Redis. Services tách theo domain ở backend/src/*.ts thay vì nhiều lớp thư mục khi module còn nhỏ. Providers có capture/context input ổn định, kịch bản demo ở cấu hình provider. HTTP business create thường trả 200, scan/Face accepted có thể trả 202, với envelope data/requestId, lỗi có code/message/details; các ví dụ trong thiết kế là thiết kế gốc, route source là contract thực thi; xem [124 route hiện hành](api-routes.md). Không tự import dữ liệu cũ khi chưa chốt mapping/consent.

## Kiểm thử và evidence

- Prototype: **14/14 PASS** — evidence/postgres-integration.tap.
- Campus source cuối: **40/40 PASS**, không skip — evidence/campus-tests.tap. Gồm PostgreSQL grants/migration, HTTP auth/RBAC/CSRF/session rotation, callback/device retry, concurrency ví/kho, PIN lock, parking passage/UNKNOWN/reversal, POS/refund, attendance/consent và Socket.IO thật qua WebSocket.
- API/provider contracts bổ sung: **7/7 PASS** — evidence/campus-contract-tests.tap.
- Regression MVCC: tái hiện số dư cũ khi đợi khóa ví trước sửa; **3/3 targeted PASS** sau sửa — evidence/wallet-snapshot-regression-before-fix.tap và wallet-snapshot-regression-after-fix.tap. Bản sửa khóa wallet trước rồi đọc balance/active holds bằng snapshot mới. Full suite cuối gồm regression này.
- Flutter source cuối: **analyze sạch, 4/4 widget tests, Web release và APK debug PASS** — evidence/flutter-analyze.txt, flutter-test.txt, build-web.txt, build-apk.txt. HTML/manifest metadata được đồng bộ và kiểm từ source sau build; compiled JS không thay đổi. WebAssembly dry-run có cảnh báo từ dependency Socket.IO; bản giao là JavaScript/CanvasKit. Android build có cảnh báo XML version của SDK tools; assembleDebug vẫn PASS.
- ESP32 Dev Module **compile PASS**, source hash khớp source bàn giao — evidence/firmware-compile.json và firmware-compile.txt. Sketch 1.092.524 bytes (83% vùng chương trình), RAM tĩnh 50.920 bytes (15%); không phải đo heap/runtime. Toolchain pin: CLI 1.5.1/core 3.3.12, MFRC522 1.4.12, LiquidCrystal I2C 1.1.2, ArduinoJson 7.4.3. Library LCD có cảnh báo metadata AVR; compile vẫn PASS, LCD thật NOT_RUN.
- Compose: **build/health + E2E phần mềm ba phân hệ + reseed/restart/persistence PASS** — evidence/compose-smoke.json. HTTPS chain/hostname với CA local PASS (không cài trust Windows, không kiểm revocation/thiết bị) — compose-tls.json. Native upgrade/auth/grants và backup/restore riêng PASS — native-smoke.json, native-upgrade-restore.json. Compose restore sau giao dịch PASS: 4 transactions, 8 entries, 0 unbalanced, số dư sinh viên 82000 point — compose-backup-restore.json.

Các lỗi đã sửa có regression: refund khóa ledger bằng runtime role thiếu UPDATE; wallet snapshot cũ sau chờ lock; seed khôi phục role đã revoke; malformed Socket.IO token/ACK. Không nới quyền ghi ledger để né lỗi refund. Seed giữ balance/stock/PIN/consent đã sửa, không tự nạp point khi restart.

- Đóng gói Web/APK/source và SHA-256 **PASS** — evidence/campus-artifacts.json, output/SmartCampus_SHA256SUMS.txt. Archive không chứa .work, active .env, secrets.h, node_modules, SDK, backup hoặc model weights; quét credential dài đã sinh PASS.

## Chưa nghiệm thu và giới hạn

1. **RFID/LCD thật NOT_RUN:** user xác nhận ESP32 Dev Board và trả lời **“chưa có cổng”** khi kiểm COM; chip biến thể/I2C address/điện áp chưa được kiểm. Windows chưa liệt kê serial trong lần kiểm. Chưa flash, quét MFRC522, thử Wi-Fi/TLS/reboot/LCD trên board. HTTP credential fixtures không phải hardware evidence. GĐ3 và RFID-backed acceptance của GĐ4/5 còn mở.
2. **Browser visual E2E NOT_RUN:** công cụ không attach được webview (Timed out waiting for the Browser webview to attach). Widget tests và HTTP checks không chứng minh mọi layout/click flow trên trình duyệt. Chưa chạy APK trên điện thoại thật.
3. **Production chưa sẵn sàng:** chỉ development/test, không tiền thật, face/PAD/OCR model thật hoặc accuracy đã đo. Bootstrap từ chối production/demo. Chưa benchmark tải toàn trường/p95, DB outage sau passage hoặc nghiệm thu vận hành dài hạn.
4. Danh sách API/UI giới hạn 100 bản ghi gần nhất, device/Face events 50; không coi danh sách này là toàn bộ lịch sử khi vượt giới hạn. CSV scope theo phiên, có escape formula.
5. Product có image reference/icon; chưa có upload/object storage cho ảnh thật. Adapter camera/payment/gate thật cần chọn thiết bị, triển khai và đánh giá riêng theo camera guide.
6. APK debug mặc định nối emulator http://10.0.2.2:8081. Điện thoại thật cần build với --dart-define=API_BASE_URL=<URL_API> và TLS phù hợp; chưa release signing/store deployment.

## Chạy và tiếp tục nghiệm thu

Xem [runbook](SETUP_SMART_CAMPUS.md) cho native/Compose, tài khoản local, demo các vai trò, test và backup. Xem [RFID](RFID_SMART_CAMPUS.md) để kiểm cáp data/COM, điện áp LCD, provision secret local, compile/upload và expected/actual từng ca. Không gửi Wi-Fi password hoặc token lên chat.

Credential nằm trong .work/*access.txt, deploy/.env và firmware/smart_campus/secrets.h, bị loại khỏi source package. Artefacts Web/APK/source ở output, được tạo bằng tools/package-campus.py; SHA-256 ở evidence/campus-artifacts.json và output/SmartCampus_SHA256SUMS.txt. Source ZIP loại manifest hash của chính nó để tránh checksum tự tham chiếu. Script kiểm tên archive members và quét secret dài đã sinh trong cả 3 artefact; PIN ngắn không quét theo chuỗi số để tránh false positive, credential files đều bị loại.


## Trạng thái môi trường và kiểm tra cuối

- Compose đã được dừng sau kiểm thử; giữ volume, không dùng down -v. Docker engine được giữ vì có container khác chạy. Native local đã khởi động tại localhost:8081; xem runbook khi cần chạy lại.
- Image MVP được pin theo chính digest cache đã kiểm: evidence/container-images.json. Node base trước build đã resolve đúng digest đó; metadata Web trong final image khớp file host: compose-final-image.json.
- Offline YAML parse, đối chiếu image refs với inspected digests, installer pins với toolchain thực và checksum archive CLI đều PASS: pinned-environment.json. **Docker compose config --quiet sau chỉnh pin chưa chạy:** automatic approval review không thực hiện được vì hạn mức sử dụng; đây không phải kết luận action unsafe. Config/runtime/E2E trước pin đã PASS trên cùng image contents; không báo lần kiểm CLI cuối đã chạy.
