# Quyết định kế thừa TapCard cho SmartCard

Ngày kiểm tra 05/11/2026. Đã tải để khảo sát 46 file tại commit **6f600226e3f0f383897ee5d2d607733e5a80c84f**. Manifest có URL/hash: evidence/tapcard-source.json. Không chạy ứng dụng MongoDB upstream nên mọi kết luận dưới đây về cấu trúc là kết quả đọc source, không là kết quả vận hành.

## Phần giữ và phần chuyển đổi

| File hoặc nhóm file upstream | Quyết định | Thay đổi cần làm | Trạng thái bản xây lại |
| --- | --- | --- | --- |
| flutter/lib/core/widgets/modern_button.dart | Dùng lại component | Giữ attribution, chuyển withOpacity sang alpha tương đương | Đã gọi trong camera spike; analyze/widget/Web đạt, APK xem evidence |
| flutter/lib/core/widgets/modern_textfield.dart | Dùng lại component cho form | Giữ validator/controller, nối form mới | Đã copy; chưa dùng ở màn hình đăng nhập |
| flutter/lib/model/theme.model.dart | Có thể giữ theme | Kiểm GoogleFonts/CardThemeData trên SDK chốt; không cần kéo mọi dependency chỉ vì theme | Chưa tích hợp |
| flutter/lib/main.dart | Giữ cách tổ chức Provider nếu tiếp tục app cũ | Chỉ đăng ký provider đã chuyển API, thêm camera/Face; không import hàng loạt model cũ | Thiết kế kế thừa, chưa tích hợp |
| screen/login_screen.dart, register_screen.dart | Giữ bố cục và form | Nối auth mới; DTO đăng nhập tách User, không round-trip password; lỗi/timeout có kiểm soát | Backlog tuần 2 |
| screen/home_screen.dart | Giữ cấu trúc tab hồ sơ/lịch sử/điểm danh/gán thẻ | Tab theo quyền ở server; thêm ví/dịch vụ khi có API, không chỉ ẩn UI | Backlog tuần 2–5 |
| screen/tab_attendance_form.dart | Giữ Stepper mở phiên/thiết bị | Thêm chọn lớp/roster; start/end theo class_session, chỉ GV được phân công | Backlog tuần 2 |
| screen/tab_history.dart, tab_profile.dart | Giữ trình bày | Dùng /me, attendance của đúng chủ thể; không tải mọi user rồi lọc trên client | Backlog tuần 2 |
| screen/tab_tag_binding.dart | Giữ quy trình chọn SV và gán thẻ | Quyền Admin, xác nhận người/thẻ, unique UID active, audit; scoped event thay broadcast UID | Backlog tuần 2 |
| model/*.model.dart | Sửa DTO và API, không dùng nguyên trạng | _id → UUID id; result/secret → schema mới; không chứa password trong UserResponse; timeout/cancel, kiểu dữ liệu kiểm tra | Chưa port các provider |
| model/rfid.model.dart | Giữ ý tưởng realtime, tách phần Wi-Fi | Không để Web phải scan/kết nối Wi-Fi; Web/Android gọi cùng server. Socket có auth/room và snapshot sau reconnect | Chưa tích hợp |
| arduino/arduino.ino | Giữ luồng MFRC522 → UID → LCD và chân đề xuất | UID phải padding hai hex/byte; HTTPS CA, token riêng, UUID event retry cố định, chỉ ACK hợp lệ báo thành công | Luồng đã đối chiếu, firmware mới viết; chưa compile/flash |
| express/src/index.ts và routes | Giữ Express/TypeScript và ý tưởng route theo domain | Tách service/SQL transaction, validation/auth; runtime mới đang Express 5 còn upstream 4, không chép handler chưa kiểm kiểu | Backend spike mới có test PostgreSQL |
| auth.config.ts, auth.middleware.ts | Giữ ý tưởng hash password, token, user active | Thay lookup Mongoose, kiểm quyền tài nguyên, bỏ log nhạy cảm, revoke/session; không copy toàn middleware | Auth người dùng chưa implement |
| models Mongoose, generic.controller.ts | Xây lại truy cập dữ liệu | SQL/FK/unique/migration và transaction; không thay connection string rồi dùng lại .find/.save/.populate | SQL mới chạy test |
| attendance.controller.ts swipeTag/startSession/endSession | Giữ nghiệp vụ mở/đóng phiên, đọc thẻ, phản hồi | Roster, khóa phiên, unique attendance và event dedupe; không dùng includes → push/save làm invariant | RFID mới 14 test PASS |
| .env, AES key, IP/reader ID trong firmware, cấu hình ký debug | Không mang giá trị cấu hình sang | Credential/CA riêng theo môi trường; không copy bí mật, signing production làm sau | Có .env.example/secrets.example.h trống |

Không có cơ sở báo một tỷ lệ phần trăm “tái sử dụng”. Hiện tái sử dụng code trực tiếp là hai widget; các màn hình/provider còn lại là ứng viên đã khảo sát, chưa port hoặc build thành công. Stack Express/Flutter/ESP32 và luồng nghiệp vụ được kế thừa, nhưng điều đó không đồng nghĩa toàn bộ source cũ tương thích PostgreSQL.

## Những điểm bắt buộc sửa trước khi tích hợp

1. attendance.router.ts gắn /swipe trực tiếp vào swipeTag, không middleware device auth. Firmware mới phải được backend xác định device qua credential, không tin reader tự khai trong payload.
2. swipeTag dùng IV zero, log UID; createEntity log base64Key/secretKey; loginUser log rawPassword và hash. Giữ nghiệp vụ nhưng bỏ các log và cơ chế truyền không phù hợp.
3. Firmware upstream ghép String(byte, HEX) không padding. Hai byte 01 23 có thể thành chuỗi khác kỳ vọng; bản mới luôn hai ký tự mỗi byte. Đây là đọc code, chưa đo trên thẻ thật.
4. UserProvider đọc token từ result.secret và gửi Authorization nguyên chuỗi; middleware upstream jwt.verify trực tiếp header. Nếu đổi Bearer phải đổi cả hai phía, không sửa một phía rồi nói tương thích.
5. Reader/Wi-Fi secret không là hồ sơ thiết bị cho mọi người dùng. Không dùng việc điện thoại kết nối SSID làm bằng chứng quyền mở phiên.
6. Mảng students trong attendance document đổi thành attendance_records theo session_id/student_id. UUID và FK không là ObjectId; mọi DTO/JSON parser phải port cùng API.

## Thứ tự kế thừa để đạt mốc

W1: kiểm component UI và phần cứng, chốt contract/schema và test prototype. W2: port auth/user/card/attendance providers cùng backend PostgreSQL, giữ UI cần thiết; chạy RFID → DB → Web/Android. W3: thêm camera/Face 1:1, không dựng lại giao diện đã dùng được. W4–5: ví, ledger, căn tin và gửi xe là phần mới vì không thấy trong source khảo sát. Cách làm này giữ giá trị repo tham khảo và giới hạn phạm vi sửa ở từng bước.

Đọc THIRD_PARTY_NOTICES.md trước khi công bố code kế thừa. Metadata license đã ghi nhận chưa đủ để kết luận quyền sở hữu của toàn repo. Không dùng .work snapshot đã che literal để build; đó chỉ là bản đọc tham chiếu.
