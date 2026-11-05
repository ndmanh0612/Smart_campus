# API và kế hoạch port Flutter từ TapCard

Backend hiện implement đúng ba operation: GET /healthz, GET /readyz, POST /v1/device-events. Không có compatibility facade cho API MongoDB. Flutter camera spike chưa gọi API, việc gọi ModernButton kế thừa không chứng minh các màn hình cũ đã hoạt động.

| Luồng upstream | API mục tiêu cần port tuần 2 trở đi | DTO và quyền cần sửa |
| --- | --- | --- |
| POST /auth/login, result.secret | POST /v1/auth/login | access_token và user; Bearer thống nhất cả hai phía; không log password |
| GET /user, lọc mobileNo client | GET /v1/me | id UUID, role/scopes từ server, không trả password |
| /reader và scanSSID | GET /v1/devices (người được cấp quyền) | Không trả Wi-Fi password/secret; chọn device theo scope |
| /attendance/start, /end | POST /v1/class-sessions; POST /v1/class-sessions/{id}/close | class_id/roster, device assignment; chỉ GV được phân công |
| GET /attendance, result.students[] | GET /v1/class-sessions/{id}/attendance | Một row/student, status, method, received_at; đúng scope |
| /reader/toggle-binding, tag-detected | Luồng gán thẻ Admin có TTL và scoped event | Không broadcast UID cho mọi client, audit và unique active |
| /attendance/swipe {reader,tag} | POST /v1/device-events | Credential xác định device; event_id,card_uid,purpose; không giữ crypto payload cũ |

Các URL mục tiêu ở bảng chưa được implement. Khi port provider, đổi cùng lúc status code, envelope, field, auth, timeout và lỗi. Không thêm lớp giả response cũ để UI tưởng hoạt động khi chưa kiểm quyền.

Contract prototype device-events: JSON event_id UUIDv4, card_uid 4/7/10 byte biểu diễn 8/14/20hex và purpose=ATTENDANCE. Chỉ nhận ba field; token Bearer riêng thiết bị. 201 RECORDED, 200 ALREADY_RECORDED; retry cùng event/payload trả nguyên status/body đã lưu, kể cả201. 400 INVALID_EVENT,401 DEVICE_UNAUTHORIZED,409 IDEMPOTENCY_CONFLICT,413 BODY_TOO_LARGE,422 CARD_NOT_ACTIVE/NOT_IN_ROSTER/SESSION_NOT_OPEN; lỗi dependency503. Outcome điểm danh không có PAID và không thay ví. Tiền nghiệp vụ tương lai BIGINT trong DB, decimal string khi JSON; giá và phí do server tính.

Face mục tiêu: claimed student_id + capture → quality/detect/align/PAD/embedding/match1:1 → verification purpose/source/terminal/TTL. Dịch vụ AI nội bộ hiện trả503/PAD_NOT_CONFIGURED, không có false success. Thanh toán phải có SV đã đăng nhập xác nhận amount/intent trên app; nhận diện đúng người không là sự đồng ý chi tiền.
