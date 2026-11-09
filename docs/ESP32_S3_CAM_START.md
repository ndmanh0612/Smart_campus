# Chạy thử ESP32-S3 CAM

## Phần cứng đã xác định

- ESP32-S3 N16R8, flash 16 MB và PSRAM OPI 8 MB.
- Cảm biến OV3660 được driver esp32-camera hỗ trợ. Profile chân camera cần mã PCB hoặc sơ đồ của đúng bo.

## Mốc 1 — Lấy ảnh JPEG qua Wi-Fi

1. Xác định tên và revision in trên PCB, mã module/cảm biến và cổng USB dùng để nạp.
   Dùng sơ đồ của đúng board để chọn cấu hình camera, PSRAM và flash.
2. Cắm cáp USB dữ liệu và chạy `Get-PnpDevice -PresentOnly -Class Ports` trước và sau khi cắm.
   Chọn COM USB mới xuất hiện.
3. Trong Arduino IDE, mở ví dụ **ESP32 → Camera → CameraWebServer** của core Espressif.
   Chọn đúng profile camera trong `board_config.h`. Với board ngoài danh sách,
   đối chiếu từng GPIO với sơ đồ hãng trước khi sửa `camera_pins.h`.
   Đặt Wi-Fi trong bản sketch local và giữ thông tin đó ngoài Git.
4. Upload, mở Serial Monitor ở 115200 baud, reset và lấy IP từ log.
   Dùng PC cùng mạng thử `curl.exe --fail --max-time 10 http://IP_CUA_ESP32/capture -o capture.jpg`.
5. Mở ảnh và kiểm tra ảnh JPEG đọc được. Thử lấy ảnh nhiều lần, sau đó khởi động
   lại board và thử lại. Dùng mạng thử nghiệm riêng và vật mẫu.

Firmware `firmware/smart_campus` phục vụ đầu đọc RFID MFRC522 và LCD.
CameraWebServer dùng cho phép thử camera độc lập.

## Mốc 2 — Kết nối vào Smart Campus

Giữ backend demo chạy riêng trong khi xác minh camera. Sau khi mốc 1 đạt,
thêm adapter lấy JPEG theo giao diện `CameraProvider` trong
`backend/src/providers.ts`. Ràng buộc camera với cấu hình thiết bị phía server,
giới hạn thời gian và kích thước ảnh, trả lỗi khi nguồn ảnh mất kết nối.
Kiểm thử capture riêng trước khi nối inference hoặc tạo bản ghi nghiệp vụ.
Xem `docs/camera-integration-guide.md` cho các mốc nhận diện, liveness và OCR.

## Đăng ký và đối sánh khuôn mặt trên máy thử

Chạy backend development trên `127.0.0.1` với biến môi trường
`FACE_PILOT_CAMERA=http://IP_CUA_ESP32/capture`. Python trên máy backend cần
OpenCV, NumPy và hai model YuNet, SFace khớp checksum trong `models/manifest.json`.

Đăng nhập tài khoản sinh viên và vào **Đăng ký khuôn mặt** để xem video
OV3660. Đồng ý chụp mẫu một lần. Sau khi có mẫu, app tự đối sánh 1:1
với mẫu của tài khoản đang đăng nhập khi màn hình này mở. Backend dùng
một kết nối MJPEG tới camera ở cổng 81 và lấy khung mới nhất cho cả video
và đối sánh. Mỗi lần chụp yêu cầu đúng một
khuôn mặt đủ lớn trong khung. App chỉ lưu vector mẫu trong
`.work/face-profiles` và có nút xóa mẫu.

Ngưỡng cosine 0,50 là cấu hình thử nghiệm chưa hiệu chỉnh trên OV3660.
Mục này chưa kiểm tra liveness và kết quả không tạo quyền mở cổng hay thanh toán.
