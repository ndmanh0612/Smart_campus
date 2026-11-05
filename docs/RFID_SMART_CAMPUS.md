# ESP32 Dev Board, MFRC522 và LCD1602

Người dùng xác nhận ESP32 Dev Board. Người dùng đã kiểm và trả lời **“chưa có cổng”**; Windows chưa liệt kê serial trong các lần kiểm; **không tự đoán cổng để flash**. Compile target tham chiếu classic ESP32 là `esp32:esp32:esp32`, không dùng target này cho ESP32-S3/C3 nếu chưa đối chiếu model/chip.

## 1. Nối dây

| Module | Chân | Classic ESP32 |
| --- | --- | --- |
| MFRC522 | SDA/SS | GPIO5 |
| MFRC522 | RST | GPIO4 |
| MFRC522 | SCK | GPIO18 |
| MFRC522 | MISO | GPIO19 |
| MFRC522 | MOSI | GPIO23 |
| MFRC522 | VCC/GND | 3.3V/GND |
| LCD1602 I2C | SDA/SCL | GPIO21/GPIO22 |
| LCD1602 I2C | GND | GND chung |

Kiểm sơ đồ board, nguồn và backpack LCD thực tế. Không mặc định pull-up SDA/SCL lên 5V an toàn với GPIO ESP32; đo/kiểm module và dùng chuyển mức nếu cần. Địa chỉ 0x27 trong template chỉ là mặc định cần xác minh bằng I2C scan. Không dùng GPIO22 cho RST vì LCD đang dùng SCL22.

## 2. Toolchain và compile

```powershell
python tools/install-arduino.py
.\tools\compile-firmware.ps1
```

Công cụ cài riêng `.work/toolchains/arduino`, kiểm SHA-256 CLI archive từ release chính thức, ghi version core/library vào `docs/evidence/firmware-toolchain.json`. Installer pin CLI 1.5.1 (kèm SHA-256 cố định), ESP32 core 3.3.12, MFRC522 1.4.12, LiquidCrystal I2C 1.1.2 và ArduinoJson 7.4.3. Không đổi PATH toàn máy. Compile nguồn cuối đã PASS theo evidence/firmware-compile.json; cảnh báo metadata AVR của LCD chưa thay thế kiểm LCD thật. Compile mặc định dùng bản sao `secrets.example.h` ở thư mục build riêng, secret trống; **binary này chỉ để kiểm compile và sẽ fail-closed khi chạy, không phải bản đã provision để flash**.

Firmware source mới: `firmware/smart_campus/smart_campus.ino`. Spike cũ được giữ ở `firmware/rfid_spike` làm tham khảo, khác API nên không dùng để nghiệm thu Smart Campus.

## 3. Provision đúng môi trường

1. Copy `secrets.example.h` thành `secrets.h` trong thư mục firmware; tệp bị ignore. Điền Wi-Fi, DEVICE_ID, DEVICE_TOKEN riêng, HTTPS API_ORIGIN và ROOT_CA. Không paste các giá trị này vào chat/log/báo cáo.
2. Native API chỉ nghe loopback HTTP. Để ESP32 truy cập HTTPS trong LAN, dùng proxy TLS phù hợp. Với Compose local: đặt APP_DOMAIN thành IP LAN hoặc hostname thật resolve được trên ESP32, PUBLIC_ORIGIN thành URL Web tương ứng, rồi recreate proxy/backend theo config. Không dùng `localhost` từ ESP32 để trỏ tới máy tính.
3. Cổng HTTPS Compose được publish ở 8443. Ví dụ API_ORIGIN là `https://<IP_LAN>:8443`, certificate phải có SAN đúng địa chỉ đó. ROOT_CA lấy từ CA nội bộ Caddy của môi trường này; chỉ root certificate là public, không copy private key.
4. Có thể copy CA bằng `docker compose --env-file deploy/.env -f deploy/compose.yaml cp proxy:/data/caddy/pki/authorities/local/root.crt .work/campus-root-ca.crt`. Nhúng PEM public này vào ROOT_CA theo cú pháp raw string C++ trong secrets.h. Không dùng `setInsecure()` để bỏ qua TLS.
5. DEVICE_ID/credential reader seed ở tệp access của đúng môi trường hoặc tạo thiết bị mới trong API admin. Không tái dùng token native cho DB Compose hoặc ngược lại.
6. DEVICE_ROLE chỉ là nhãn khởi động. Backend role/configVersion là căn cứ; ESP32 đọc config và ACK trước khi server cấp context/challenge.

Firmware lưu pending event/action trong Preferences để recovery sau reboot. NVS mặc định chưa bảo đảm chống đọc khi bị tiếp cận vật lý; production cần thiết kế provisioning/secure boot/flash encryption phù hợp board. Không coi UID hoặc firmware này là thẻ chống clone.

## 4. Xác định COM và flash

- Dùng cáp USB truyền dữ liệu, cắm board và xem Device Manager → Ports (COM & LPT), hoặc `arduino-cli board list` với config local. Nếu không có cổng: kiểm cáp, driver USB-UART đúng module và kết nối; không thay driver không rõ chip.
- Xác nhận chip/board phù hợp target. Mở sketch bằng Arduino IDE với các version thư viện đã chốt, hoặc compile bản đã provision bằng `compile-firmware.ps1 -Provisioned`.
- Chỉ upload khi đã có số COM thật và user chọn đúng board. Lệnh tham chiếu: `arduino-cli --config-file .work/toolchains/arduino/arduino-cli.yaml upload --fqbn esp32:esp32:esp32 --port COM_THUC_TE .work/firmware-build/smart_campus`.
- Mở serial 115200; firmware log HTTP status, không log UID/Wi-Fi/token. Không flash binary compile-check có secret trống.

## 5. Luồng kiểm trên một reader thật

1. Backend/admin đặt RFID_ENROLLMENT, ESP32 nhận config/ACK. Admin tạo context cho sinh viên mẫu, quét MFRC522, dashboard hiện REAL event và identity. Xác nhận cấp/thay thẻ, LCD báo đã gán.
2. Đổi PARKING_ENTRY khi không busy. Admin/staff tạo entry context, quét thẻ, OCR DEMO, tạo lượt và xác nhận cổng mô phỏng/xe vào; đối chiếu ACTIVE trong DB.
3. Đổi CANTEEN_POS. Tạo đơn và context, quét thẻ, sinh viên xác nhận PIN trên app, staff thu point. LCD phản ánh trạng thái order qua action polling; kiểm ledger/kho/receipt.
4. Đổi PARKING_EXIT. Quét thẻ trong context đúng session, OCR, quote/PIN, giữ point, xác nhận passage. Kiểm chỉ một PARKING_PAYMENT, COMPLETED và LCD phù hợp.
5. Đổi role khi pending phải DEVICE_BUSY; không giả định có nhiều reader. Terminal DEMO chỉ để thử Face, không thay bước scan thật này.

## 6. Các ca lỗi bắt buộc và recovery

| Ca | Kết quả cần thấy |
| --- | --- |
| Thẻ chưa gán/lost/revoked/expired | API từ chối; không ghi tiền/điểm danh/mở cổng; LCD báo từ chối |
| UID có byte 00/01 | Đủ hai ký tự hex/byte, không mất 0 đầu |
| Token/DEVICE_ID/role/configVersion sai | Từ chối, không tự nhận role từ body |
| Quét nhanh hoặc giữ thẻ | Debounce, không tạo nhiều payment/session |
| Mất Wi-Fi/CA sai/NTP chưa đồng bộ | Không báo nghiệp vụ thành công/offline, không bỏ TLS |
| ACK mất | Retry cùng payload/eventId tối đa 3; sau đó chỉ query trạng thái; serial `r` thử lại cùng event, không tạo event mới |
| Reboot lúc pending | Nạp lại payload/action từ NVS, tra kết quả server; không tự mở cổng hoặc trừ point |
| Context hết hạn hoặc sai phiên | Từ chối và tạo context mới có quyền; không backdate sự kiện |
| Thiếu point/đối soát cổng | App báo thiếu; cổng không tự mở; LCD chờ/xử lý ngoại lệ, không báo PAID từ IDENTIFIED |

Ghi evidence gồm model/chip/COM/library versions, thời gian, test ID, eventId/actionId/record/transaction ID, expected/actual, ảnh LCD đã lọc dữ liệu, PASS/FAIL/NOT_RUN. Không chụp secrets.h, token, UID nguyên vẹn hoặc ảnh người thật chưa consent. Thiếu evidence quét thật thì giữ hardware acceptance NOT_RUN.
