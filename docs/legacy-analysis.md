# Phân tích nguồn hiện có và phương án kế thừa

> Thiết kế đã được người dùng duyệt ngày 05/11/2026. Đây là tài liệu thiết kế gốc; xem [trạng thái triển khai](implementation-status.md) và [runbook](SETUP_SMART_CAMPUS.md) cho code, lệnh chạy và bằng chứng hiện hành.

Ngày: 05/11/2026. Trạng thái: **đã đọc nguồn, chưa chạy lại hệ thống cũ**. Thiết kế đã duyệt, phần triển khai/validation xem implementation-status.md; chưa xác nhận hardware MVP hoàn thành.

## 1. Nguồn và giới hạn bằng chứng

- Repository tham khảo: [TapCard](https://github.com/ndmanh0612/tapcard-iotproject). Trang GitHub truy cập được trong lượt này, có các thư mục `express`, `flutter`, `arduino`.
- Đã đọc bản khảo sát có sẵn tại `../.work/tapcard-reference/`, được công cụ `../tools/inspect-tapcard.py` tải và che literal nhạy cảm. Manifest `evidence/tapcard-source.json` ghi 46 file, URL và SHA-256 gốc tại commit `6f600226e3f0f383897ee5d2d607733e5a80c84f`. Đã kiểm lại qua mạng khi chốt triển khai: **46/46 SHA-256 trùng**, commit ghim trùng default branch HEAD tại thời điểm kiểm; chỉ lưu hash metadata ở evidence/tapcard-reverified.json, không lưu raw source chứa literal nhạy cảm.
- Đọc trực tiếp controller/routes/model liên quan điểm danh, middleware auth, entry point, package metadata, firmware và Flutter providers trong snapshot. Bản đã che literal chỉ phục vụ khảo sát, không dùng để build hoặc suy ra giá trị cấu hình.
- Không clone mới: Git báo `cannot change to 'C:/Users/dellcuatri142'`; Python truy cập GitHub API bị lỗi DNS; web truy cập được trang repo nhưng không tải được raw file đã ghim. Ở lượt khảo sát chưa xác nhận HEAD; lượt chốt đã xác minh qua HTTP như evidence mới phía trên. Không cần người dùng cung cấp lại code để thiết kế vì snapshot nguồn đã có, nhưng phải lấy bản đầy đủ trước khi port/build upstream.
- Workspace và `source/` không có `.git`; `git status` không thực hiện được. Không tạo repo/commit, không reset dữ liệu.
- Không chạy lại MongoDB/Flutter upstream, không compile/flash ESP32, không thử RFID/LCD thật. Các log PASS cũ không được tính là kết quả test của lượt này.

## 2. Cấu trúc và luồng TapCard đã quan sát

| Thành phần | Entry point, dependency và trách nhiệm |
| --- | --- |
| Backend upstream | `express/src/index.ts`: Express + TypeScript, kết nối MongoDB qua Mongoose, mount `/auth`, `/user`, `/reader`, `/tag`, `/attendance`; Socket.IO được tạo tại HTTP server |
| Phiên | `attendance.controller.ts`: `startSession` đóng phiên mở của reader trong ngày, tạo phiên `isOpen=true`; `endSession` cập nhật `isOpen=false` theo ID |
| Quét thẻ | `POST /attendance/swipe` → `swipeTag` → reader → giải mã tag AES-CBC → tag/student → tìm phiên reader đang mở → thêm sinh viên → emit realtime → phản hồi LCD |
| Gán thẻ | Reader có `isBindingMode`; thẻ chưa đăng ký được phát `tag-detected` để app xử lý |
| Flutter | `flutter/lib/main.dart` tạo `MultiProvider`; model chứa gọi API/trạng thái; màn hình mở phiên, lịch sử, hồ sơ, gán thẻ; `rfid.model.dart` nối Socket.IO và có logic Wi-Fi Android |
| Firmware | `arduino/arduino.ino`: MFRC522/SPI → ghép UID → AES → HTTP JSON → đọc phản hồi → LCD I2C |

Nghiệp vụ **phải có phiên OPEN trước khi điểm danh** tồn tại trong `swipeTag`. Chưa thấy kiểm tra đăng ký lớp, lịch/phòng hay phân công giảng viên trong `startSession`/`endSession`. Không diễn giải dòng mô tả README về mã hóa là bằng chứng hệ thống chống giả mạo.

## 3. Những vấn đề chứng minh được từ source

| Quan sát | Tác động | Cách xử lý trong thiết kế mới |
| --- | --- | --- |
| `attendance.router.ts` gắn `/swipe` trực tiếp, không `isAuthorized`; body tự khai reader | Không có xác thực thiết bị ở route này | Credential riêng thiết bị, lấy device từ credential; role/binding do server quản lý |
| `isAuthorized` kiểm JWT/tài khoản nhưng không kiểm quyền lớp trong handler start/end | Có xác thực không đồng nghĩa có quyền mở/đóng phiên cụ thể | RBAC + kiểm phân công lớp, phòng, schedule ở application service |
| IV zero trong `swipeTag`; firmware gửi HTTP và có literal cấu hình nhạy cảm | Không có bảo đảm chống replay hay bảo mật truyền tin phù hợp | TLS xác minh CA, credential riêng, challenge dùng một lần + eventId; không tái dùng AES của luồng cũ |
| `createEntity` log key; `swipeTag` log UID; Flutter log thông tin kết nối reader | Rò rỉ dữ liệu qua log | Allowlist trường log, che UID, cấm log PIN/token/embedding |
| UID firmware ghép hex không padding trong vòng đọc byte | Có thể mất byte 0 đứng đầu trong biểu diễn | Hai ký tự hex mỗi byte, uppercase, kiểm 4/7/10 byte; test vector có byte 00/01 |
| Attendance dùng mảng, kiểm `includes` rồi `push/save` | Không có ràng buộc SQL chống race theo phiên/sinh viên | Unique `(session_id, student_id)`, transaction và khóa phiên |
| `io.emit` và CORS socket `*` | Broadcast danh tính/UID không giới hạn lớp | Handshake xác thực, server join room theo quyền, payload tối thiểu |
| Header token cũ được `jwt.verify` trực tiếp | Không tương thích tự động với chuẩn `Bearer` mới | Port client/server cùng contract; không giữ định dạng cũ ngầm định |
| Chưa thấy domain ví/cantin/gửi xe trong snapshot khảo sát | Không có cơ sở nói đã có các module này | Thiết kế mới từng giai đoạn, không hứa tái sử dụng nghiệp vụ chưa tồn tại |

## 4. Prototype thực tế trong workspace

| Tệp hiện có | Đã xác định từ code | Khoảng trống so với yêu cầu mới |
| --- | --- | --- |
| `../backend/server.ts`, `app.ts` | Express, `pg`, Node TypeScript; `/healthz`, `/readyz`, `/v1/device-events`; token thiết bị hash SHA-256, UID HMAC; transaction ghi attendance và ACK dedupe | Chỉ purpose `ATTENDANCE`; chưa có user auth/RBAC, device role, ví posting, simulator hoặc API quản trị |
| `../database/001.sql` | FK/unique, session roster, ledger double-entry có trigger chống sửa; một lượt xe mở/vehicle | Schema prototype: `student_cards`, `classes`, `class_sessions`, vai trò `TEACHER/CANTEEN/PARKING`; thiếu nhiều bảng/trạng thái của thiết kế mới; cache balance/posting chưa hoàn chỉnh |
| `../backend/test/integration.test.ts` | Có 14 test source cho RFID attendance, dedupe/concurrency, thẻ/thiết bị, ledger constraints, rollback | Chưa chạy lại; không đại diện test ví/cantin/gửi xe hay RFID thật |
| `../firmware/rfid_spike/rfid_spike.ino` | TLS CA/NTP, UID padding, UUID, retry cùng payload tối đa 3 lần trong RAM | Cố định ATTENDANCE, chưa role/challenge/config version, chưa queue bền; nhiều lỗi sẽ halt đến restart; chưa compile/flash |
| `../ai-service/app.py`, `runtime.py` | FastAPI/OpenCV smoke; endpoint verify fail-closed 503 | Không phải face recognition sẵn sàng dùng; không đáp ứng simulator mới, không cần chạy để demo |
| `../flutter/app/lib/main.dart` | Camera spike, không phải app nghiệp vụ Smart Campus | Giữ làm thử nghiệm lịch sử; app mới cần dashboard và dữ liệu backend; chưa cần quyền camera cho DEMO |
| `../deploy/compose.yaml` | Blueprint PostgreSQL/backend/AI/proxy, init `001.sql` trên volume mới | Chưa có cấu hình DEMO mới; cần migration runner, worker, health, seed, test khởi động |

Dependencies hiện có được đọc từ `backend/package.json`: Express `5.3.0`, pg `8.23.1`, TypeScript `5.9.3`, Node `>=24 <25`. Đây là metadata đang khai báo, không khẳng định bản mới nhất hay đã cài/chạy trong lượt này. Flutter và Python có lock/manifest riêng; không nâng version trong giai đoạn thiết kế.

## 5. Ma trận kế thừa

| Thành phần | Quyết định | Điều kiện trước khi dùng |
| --- | --- | --- |
| Express/TypeScript + pg trong workspace | Giữ nền tảng, tách dần theo module | Giữ route prototype cô lập đến lúc chuyển contract; test trước/sau từng bước |
| Roster, unique attendance, ACK transaction | Tái sử dụng invariant và test cases | Map sang schema mới, thêm quyền/lịch/phòng/source |
| Ledger append-only/double-entry prototype | Giữ nguyên tắc; nâng cấp posting qua migration | Chứng minh balance cache, holds, hoàn tiền và quyền DB bằng integration tests |
| Firmware MFRC522/LCD, pin map, padding/TLS/UUID | Port chọn lọc | Compile trên board thật, không giữ purpose ATTENDANCE cố định cho các role mới |
| Hai widget `ModernButton`, `ModernTextField` | Đã có bản dùng lại trong workspace | Giữ attribution, xác minh quyền phân phối trước công bố |
| Flutter mở/đóng phiên, lịch sử, gán thẻ | Tham khảo bố cục/flow | Port DTO UUID và API mới, timeout, auth storage; không chép Wi-Fi/password workflow |
| Mongoose models/generic controller | Không dùng làm tầng persistence PostgreSQL | Thiết kế FK và migration thay vì chỉ đổi URL kết nối |
| AES/IV/log bí mật, reader secret API, broadcast UID | Không kế thừa cơ chế | Dùng security boundary ở kiến trúc mới |
| OpenCV models và camera spike | Giữ tệp lịch sử, ngoài runtime demo mặc định | Chỉ xem xét ở giai đoạn camera thật có consent/evaluation |

Không có cơ sở định lượng phần trăm tái sử dụng. `../THIRD_PARTY_NOTICES.md` ghi metadata upstream `GPL-3.0-only`, thiếu LICENSE root trong cây khảo sát; chưa đủ thông tin xác nhận phạm vi license toàn repo. Đây là việc cần xác minh với chủ nguồn trước phân phối, không tự gán license mới.

## 6. Ưu tiên phạm vi

Yêu cầu Smart Campus trong lượt này thay phần định hướng camera thật/Face 1:1/OCR ngoài MVP của tài liệu cũ. Thiết kế mới dùng RFID REAL, Face/OCR/Camera DEMO, Gate SIMULATOR, Payment MOCK. Không xóa hay sửa code/SQL cũ tại giai đoạn 0–1. Xem [kiến trúc](architecture.md), [database](database-design.md) và [roadmap](implementation-plan.md) để duyệt phương án chuyển đổi.
