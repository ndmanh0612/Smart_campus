# Bằng chứng cần bổ sung khi có thiết bị

Người dùng xác nhận ngày05/11 hiện không có ESP32/điện thoại sẵn để thử. Checklist này không được đánh PASS từ kết quả HTTP giả lập hoặc widget test.

## RFID và LCD

1. Ghi chính xác tên board ESP32, reader, LCD backpack, core và version từng library; kiểm mức điện áp, dây nguồn/GND và I2C pullup trước nối.
2. Compile firmware, lưu log. Không flash một board chưa xác nhận model. Chụp sơ đồ dây không có token/SSID/password trong ảnh.
3. Tạo DB dev riêng, cấp student/card/device/session/roster và token/CA riêng; UID HMAC phía backend, không đưa HMAC key lên ESP32. Không dùng script test TRUNCATE vào DB dev/thật.
4. Quét thẻ, đối chiếu LCD và record DB, ghi event/attendance ID. Thử quét lại/ACK mất vẫn một record; khóa thẻ, hết hạn, ngoài roster và phiên đóng phải bị từ chối. Token device sai hoặc CA sai không thành công.
5. Mỗi lần test ghi actual, timestamp, source version và người chạy. Không in UID/token/ảnh thật vào log nộp báo cáo.

## Camera Web và Android

| Ca | Expected | Actual và evidence |
| --- | --- | --- |
| Web localhost/HTTPS allow | Preview mở sau thao tác, chụp có ảnh | Chưa chạy trên camera thật |
| Web deny hoặc không có camera | Lỗi có hướng dẫn, không crash | Chưa chạy |
| Android allow/deny | Permission đúng, app không tự mở camera khi khởi động | Chưa chạy máy thật |
| Pause/resume | Dừng camera khi inactive; mở lại theo thao tác, không màn hình crash | Chưa chạy máy thật |
| Chụp/xóa hiển thị | Ảnh xem được/xóa khỏi UI, không tự upload | Chưa chạy máy thật |
| Kết quả Face | Chưa có PAD/threshold thì không VERIFIED | AI HTTP fail-closed đã có test; chưa là kiểm camera/matching |

Build Web/APK và widget test chỉ là bằng chứng riêng về build/UI. APK tuần1 ký debug để thử, không dùng tên “APK production đã ký phát hành”. Mẫu demo camera dùng người đã đồng ý; không thu/commit ảnh Face thật hoặc dùng ảnh người khác thay cho kết quả thiết bị.

## Mẫu ghi một lần chạy

ID ca: …; ngày/giờ: …; người thực hiện: …; model thiết bị/OS: …; source/model hash: …; điều kiện mạng/ánh sáng: …; expected: …; actual: …; PASS/FAIL/NOT RUN: …; file log/video đã ẩn dữ liệu: …; lỗi và hạn xử lý: ….

Trước buổi báo cáo, nếu chưa có các evidence này thì giữ tiêu chí3 “chưa đủ”, trình phần đã có và đề nghị giảng viên xác nhận ngày bổ sung. Không có thiết bị là điều kiện thiếu thực tế, không là bằng chứng bản code không dùng được hoặc đã dùng được.
