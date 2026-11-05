# SRS — Yêu cầu Smart Campus

> Thiết kế đã được người dùng duyệt ngày 05/11/2026. Đây là tài liệu thiết kế gốc; xem [trạng thái triển khai](implementation-status.md) và [runbook](SETUP_SMART_CAMPUS.md) cho code, lệnh chạy và bằng chứng hiện hành.

Phiên bản thiết kế 0.1, 05/11/2026, **chờ duyệt**. Căn cứ: yêu cầu người dùng trong lượt này và [khảo sát nguồn](legacy-analysis.md). Các giá trị đề xuất dưới đây chưa là chính sách đã được trường phê duyệt.

## 1. Phạm vi và ranh giới

Một `studentId` thống nhất cho tài khoản, RFID, biometric tùy chọn, xe, ví point, cantin, gửi xe, điểm danh. MVP sử dụng **một bộ ESP32 + MFRC522 + LCD thật** đổi vai trò; không dùng mock RFID để nghiệm thu phần cứng.

| Thành phần | Chế độ MVP | Nhãn bắt buộc trên UI/báo cáo |
| --- | --- | --- |
| RFID | REAL | RFID THẬT; trạng thái online/lastSeen, không tự coi HTTP test là quét thật |
| Camera/Face/Liveness/OCR | DEMO, không tải model nặng | DỮ LIỆU MÔ PHỎNG, source=DEMO; không có tuyên bố độ chính xác/PAD |
| Barrier | SIMULATOR | CỔNG MÔ PHỎNG; xác nhận mở cổng và xe qua là hai sự kiện khác nhau |
| Thanh toán nạp point | MOCK, dev/test | NẠP POINT MÔ PHỎNG — KHÔNG PHẢI TIỀN THẬT |
| Ví và nghiệp vụ | Ghi DB dev/test thật | Ledger point trong môi trường thử nghiệm; không hiển thị như tiền ngân hàng |

Không triển khai camera thật, gateway tiền thật, GPU, microservices, Redis hoặc MinIO bắt buộc ở MVP. Thiết kế có adapter; lựa chọn phần cứng/SDK thật sẽ được duyệt sau. Đây là workflow nghiệp vụ có provider mô phỏng, **không phải LLM Agent**.

## 2. Tác nhân và phạm vi quyền

Mọi endpoint kiểm quyền server và quan hệ tài nguyên; ẩn nút UI không thay thế authorization.

| Vai trò | Cho phép | Giới hạn |
| --- | --- | --- |
| STUDENT | `/me`, lịch sử cá nhân, báo mất thẻ, đăng ký xe, yêu cầu top-up mock, đặt PIN/xác nhận chi trả, consent/xóa biometric | Không tự cấp thẻ hiệu lực, cộng point, gửi studentId để tự điểm danh hoặc tự mở barrier |
| LECTURER | Lớp được phân công, mở/đóng phiên, xem realtime, điều chỉnh có lý do, báo cáo | Chỉ lớp của mình; quyền simulator riêng, không phát sinh chỉ vì có role giảng viên |
| PARKING_STAFF | OCR demo, vào/ra, xác minh sai biển, xác nhận xe qua và xử lý ngoại lệ theo grant | Không tự miễn phí/điều chỉnh ví; phải ghi lý do và evidence |
| CANTEEN_STAFF | Sản phẩm/kho/POS; tạo/hủy đơn; yêu cầu charge; refund nếu có grant | Không xem PIN, không tin tổng tiền client; refund có giới hạn, gắn giao dịch gốc |
| ADMIN | Tài khoản/role/device/policy/audit; cấp quyền nhạy cảm | Điều chỉnh point cần permission riêng và lý do; không sửa ledger trực tiếp |

Các permission nhạy cảm: `simulator.use`, `parking.exception.resolve`, `parking.fee.waive`, `canteen.refund`, `wallet.adjust`, `biometric.manage`, `device.configure`. Seed dev cấp `simulator.use` cho admin thử nghiệm; giảng viên/nhân viên chỉ được cấp rõ ràng. Production không có route simulator.

## 3. Use cases và tiêu chí chấp nhận

| ID | Use case/yêu cầu | Tiêu chí kiểm chứng |
| --- | --- | --- |
| ID-01 | Đăng nhập, logout, khóa tài khoản, RBAC | Token hết hạn/thu hồi và tài khoản khóa bị chặn; ID người khác bị 403/404; không trả password hash |
| ID-02 | Cấp/thay/thu hồi/báo mất RFID | Một UID active và một thẻ active mỗi SV; thay thẻ thu hồi cũ atomically; thẻ LOST/REVOKED/EXPIRED không nhận diện được |
| ID-03 | RFID/Face về cùng studentId | Bản ghi ba domain cùng FK; Face chỉ nhận student fixture dev, không tạo danh tính mới ngầm |
| BIO-01 | Đồng ý, đăng ký/thay/xóa biometric | Consent theo mục đích/version; xóa template và evidence theo chính sách; giữ audit không có biometric; fixture DEMO không là embedding thật |
| DEV-01 | Thiết bị được cấp quyền và đổi role | PARKING_ENTRY/PARKING_EXIT/CANTEEN_POS/RFID_ENROLLMENT; role/configVersion server là căn cứ; không đổi khi có thao tác chờ |
| RFID-01 | Quét phần cứng thật | UID đúng padding, HTTPS CA, device credential; LCD phản hồi từ ACK đúng eventId; lưu log thử thật và ID DB |
| RFID-02 | Retry/mất mạng/chống replay | Cùng event+payload trả lại ACK; khác payload 409; event mới hết challenge bị chặn; offline không trừ point/mở cổng |
| PK-01 | Vào bãi | Scan hoặc Face DEMO hợp lệ + OCR DEMO + authorization xe → PENDING_ENTRY → xác nhận qua cổng → ACTIVE; không hai lượt chiếm cùng xe |
| PK-02 | Ra bãi | Đúng SV, phiên, biển, quyền xe; báo giá snapshot; PIN/app xác nhận nếu phí >0; giữ point; xác nhận xe ra mới capture/COMPLETED |
| PK-03 | Sai biển/thiếu point/không có phiên | Không mở tự động; hiển thị thiếu bao nhiêu; top-up bổ sung hoặc ngoại lệ có quyền; lưu OCR gốc/sửa/lý do |
| PK-04 | Barrier timeout/ACK trễ | Không coi timeout là đã đóng; giữ EXIT_PENDING/EXCEPTION và hold đến khi xác minh; không thu hai lần hoặc tự miễn phí |
| PK-05 | Biểu phí cấu hình | Lượt/giờ/ngày, monthly pass, miễn giảm; version và hiệu lực; test biên giờ/ngày/rounding; không nhận giá client |
| WAL-01 | Top-up mock | PENDING → callback nội bộ tin cậy → SUCCEEDED; callback lặp chỉ cộng một lần; student không gọi endpoint xác nhận |
| WAL-02 | Chi trả/ledger | posted/available balance không âm; double-entry cân bằng, append-only, rollback atomic; hai giao dịch cạnh tranh không overspend |
| WAL-03 | PIN/app approval | UID đơn thuần không đủ; approval gắn student/order/amount/version/device/expiry, một lần; sai PIN bị giới hạn thử |
| WAL-04 | Refund/reversal/điều chỉnh | Tham chiếu giao dịch gốc; tổng hoàn không vượt số đã thu; permission, lý do, audit; không UPDATE ledger |
| CAN-01 | POS/sản phẩm/kho | Backend lấy giá, chụp line item; reserve tồn theo thứ tự khóa ổn định; thiếu tồn không tạo đơn sẵn sàng thanh toán |
| CAN-02 | RFID/Face DEMO checkout | Identity cùng pipeline approval; thanh toán/inventory/order COMPLETED trong một transaction; lặp không bán/trừ hai lần |
| CAN-03 | Hủy/hết hạn/refund | Giải phóng reserve; hoàn point có quyền; hoàn kho chỉ với hàng thực nhận trả, có lý do, không mặc định restock đồ ăn |
| ATT-01 | GV mở phiên | Đúng lớp/phân công/schedule/phòng/device; SCHEDULED → OPEN; không hai phiên OPEN dùng cùng device |
| ATT-02 | Face DEMO attendance | Chỉ OPEN, đúng lớp/roster/phòng/device; PRESENT/LATE từ server receive time; unique session+student; reject unknown/low confidence/liveness fail |
| ATT-03 | Đóng/sửa/báo cáo | Đóng có khóa chống race; sinh ABSENT từ roster chưa có record; EXCUSED có duyệt/lý do; realtime đúng room; CSV chống formula injection |
| SIM-01 | Dashboard mô phỏng | Nhãn đúng từng mode, chọn fixture/tình huống, OCR correction, barrier timeout, last RFID masked, event log và link chi tiết DB qua API chỉ đọc có quyền |
| OPS-01 | Local và vận hành | Compose + migration/seed dev + health/ready; cấu hình thiếu hoặc production bật demo → không start; log structured có request/event ID |

## 4. Invariants bắt buộc

1. Mọi nguồn identity đều qua cùng kiểm tra tài khoản/thẻ/consent theo mục đích; provider không được ghi attendance, ví, đơn hay mở cổng trực tiếp.
2. Cấm simulator ở production kể cả có admin token. `source=DEMO` do server gán, không tin field client.
3. Chỉ ledger đã POSTED làm thay đổi posted balance. Holds giảm available balance nhưng chưa là doanh thu. Balance cache cập nhật cùng transaction với ledger.
4. Một xe chưa xác nhận ra vẫn giữ occupancy, kể cả EXCEPTION. Không xóa phiên để né unique constraint.
5. Không có tiền thật trong MVP. Tỷ lệ mặc định 1 point = 1 VND chỉ để hiển thị/test, versioned; không đổi giá trị ledger cũ khi đổi tỷ lệ.
6. Thời gian nghiệp vụ do server kiểm soát, lưu UTC; hiển thị Asia/Ho_Chi_Minh. Clock ESP32 không là căn cứ tính phí hay PRESENT/LATE.
7. Lệnh cổng có TTL/fencing, idempotent và trạng thái riêng; “đã gửi”, “đã mở”, “xe đã qua” khác nhau.

## 5. Yêu cầu phi chức năng đề xuất

Các số sau là **mục tiêu nghiệm thu dev**, chưa đo: 1.000 fixture SV, 10 client staff, 20 request đồng thời; p95 API đọc <500 ms, nhận scan → ACK <2 s trên mạng local không fault injection; refresh realtime <2 s sau commit. Flow cần nhân viên/PIN không tính vào latency xử lý server.

- Availability chưa cam kết SLA production; lỗi DB/AI/mạng phải từ chối an toàn, không mở cổng hoặc báo thanh toán thành công.
- Validation DTO strict, body size limit, timeout DB/network, rate limit theo user/device/IP, log không secret/UID nguyên vẹn. Health liveness không lộ config; ready kiểm migration và provider policy.
- Backup DB mã hóa; diễn tập restore trước dữ liệu thật. Không publish DB/FastAPI; tách DB và secret dev/test/production.
- UI tiếng Việt, responsive, hỗ trợ bàn phím, lỗi có hướng xử lý; tiền/point lưu integer và JSON dạng chuỗi để không mất chính xác.
- Dashboard không đưa SQL console/secret lên trình duyệt; “xem DB” nghĩa là read model API đã kiểm quyền.

## 6. Mặc định cần duyệt, không cản thiết kế

| Quyết định | Đề xuất | Khi cần chốt |
| --- | --- | --- |
| Web quản trị | Flutter Web dùng cùng monorepo Flutter, layout riêng staff/student; tránh thêm React stack ở MVP | Trước GĐ7 |
| Xác nhận chi trả | PIN ví trong app của SV sau khi thấy amount; có thể dùng app approval thay PIN cho lần sau bằng session riêng | Trước GĐ2/GĐ4 |
| Giới hạn dev | 100.000 point/giao dịch, 500.000/ngày/SV; PIN 5 lần sai/15 phút; versioned config | Trước test thanh toán; không coi là chính sách trường |
| Attendance | Mở từ 15 phút trước đến hết lịch; muộn sau 10 phút từ scheduled start; điều chỉnh có lý do | Trước GĐ6 |
| Retention dev | Không ảnh/embedding thật; event payload nhạy cảm 7 ngày, metadata/audit/ledger fixture 90 ngày hoặc reset DB test rõ ràng | Trước thu dữ liệu thật phải có chính sách riêng được duyệt |
| Biểu phí/xe dùng chung | Seed phí synthetic, không phát hành biểu phí trường; một xe có nhiều authorization nhưng mỗi lượt gắn một SV chịu phí | Trước GĐ4 |
| Board/LCD | Pin classic ESP32 theo yêu cầu; kiểm board, điện áp và LCD address trước flash | GĐ3; cần thiết bị để nghiệm thu thật |

Không có quyết định thiếu nào ngăn việc lập thiết kế. **Cần duyệt bộ thiết kế trước GĐ2**, đúng yêu cầu người dùng. Checklist MVP và test matrix nằm ở [implementation-plan.md](implementation-plan.md).
