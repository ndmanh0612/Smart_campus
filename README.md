# Smart Campus — MVP local

Thiết kế đã được duyệt và các phân hệ phần mềm đã được triển khai: định danh chung, RFID/device, ví point, gửi xe, POS/kho, điểm danh giảng viên mở phiên, Flutter Web/Android và dashboard mô phỏng.

**RFID: phần cứng thật; Face/Camera/Liveness/OCR: DEMO; Gate: SIMULATOR; Payment: MOCK.** Firmware chưa flash/quét MFRC522/LCD thật. Các bản build và kiểm thử phần mềm không thay thế nghiệm thu phần cứng hoặc triển khai production.

- [Hướng dẫn cài và chạy](docs/SETUP_SMART_CAMPUS.md): native Windows hoặc Docker Compose, tài khoản local, kịch bản các vai trò, backup.
- [Tệp triển khai](docs/implementation-files.md) và [124 route API](docs/api-routes.md).
- [Kết quả và phần chưa nghiệm thu](docs/implementation-status.md): đối chiếu evidence, giới hạn và đường dẫn code.
- [Nối dây, provision và flash ESP32](docs/RFID_SMART_CAMPUS.md).
- [Thiết kế và test matrix](docs/implementation-plan.md), [API](docs/api-contracts.md), [thay camera thật](docs/camera-integration-guide.md).

Từ thư mục `source`, trên máy hiện tại:

```powershell
.\tools\start-campus.ps1
```

Trên GitHub, nội dung thư mục `source` là root của repository, vì vậy chạy lệnh từ root sau khi clone. Cần Node 24, PostgreSQL 17 và Flutter/Android SDK phù hợp; các SDK/cache riêng của máy phát triển không nằm trong Git. Cài backend bằng `npm ci` trong `backend`, xem runbook cho cấu hình toolchain và build Flutter.

Web/API ở [localhost:8081](http://localhost:8081). Mở `.work/campus-access.txt` tại máy để lấy tài khoản và PIN được sinh ngẫu nhiên. Không paste/commit tệp này. Khi đổi source Flutter, chạy `.\tools\verify-flutter.ps1 -Stage all` trước. Chi tiết prerequisite và lệnh Docker ở runbook.

API mới: `/api/v1`; entry point `backend/server.ts`; business modules ở `backend/src`; schema `campus` được thêm bằng migrations. Prototype cũ ở `backend/prototype-server.ts` và schema `public` được giữ nguyên. Không tự nhập dữ liệu cũ khi chưa chốt mapping.

Bản bàn giao tạo bởi `tools/package-campus.py`: `output/SmartCampus_Web.zip`, `output/SmartCampus_debug.apk`, `output/SmartCampus_Source.zip`. Xem SHA-256 và trạng thái ở `docs/evidence/campus-artifacts.json` sau khi đóng gói. APK debug mặc định nối Android emulator tại `http://10.0.2.2:8081`; thiết bị thật cần build với `--dart-define=API_BASE_URL=<URL_API>` và cấu hình TLS thích hợp.

Git chỉ chứa mã nguồn, assets và tài liệu. APK/ZIP, Web đã build, model weights, database, backup, `.work` và credential local được loại khỏi repository. Manifest/license của models và các file cấu hình mẫu vẫn được giữ. Các đường dẫn artefact trong hồ sơ lịch sử mô tả kết quả tạo tại máy phát triển, không phải file có sẵn sau khi clone.

## Hồ sơ prototype tuần 1 (lịch sử)

Nội dung bên dưới được giữ để truy vết công việc trước Smart Campus. Lệnh `/v1/device-events`, camera spike và kết quả tuần 1 thuộc prototype; không áp dụng cho backend mới. Trạng thái hiện hành luôn xem báo cáo và runbook phía trên.

Bản xây lại ngày 05/11/2026 để hoàn thiện tuần 1, **kế thừa chọn lọc TapCard**. Đọc [quyết định kế thừa](docs/KE_THUA_TAPCARD.md), [checklist nghiệm thu](NGHIEM_THU_TUAN_1.md), [kiến trúc](docs/KIEN_TRUC.md) và [nguồn code dùng lại](THIRD_PARTY_NOTICES.md).

Chuẩn bị báo cáo: file Word local `output/Bao_cao_Tuan_1_Trinh_Thay_05_11.docx` (không đưa vào Git), [kịch bản 8–10 phút](docs/KICH_BAN_BAO_CAO.md). Chạy `.\tools\demo-week1.ps1` từ source để demo backend trên DB riêng; xem docs/evidence/demo-backend.json. Đây là đầu vào thiết bị giả lập, không thay quét RFID thật. Người dùng đã cho phép cài SDK và chấp thuận Android SDK License ngày05/11; thiết bị thật hiện chưa sẵn để thử.

Đầu vào: kế hoạch 8 tuần v2, PDF thẻ sinh viên và repo TapCard do người dùng cung cấp. Thứ tự ưu tiên: yêu cầu người dùng và lịch 8 tuần; PDF cung cấp nghiệp vụ. Scope gồm Web/APK Android, định danh chung, RFID/Face 1:1, điểm danh, ví tiền mô phỏng, căn tin và gửi xe. Face 1:N/OCR/OMR/Google Play ngoài MVP.

## Cấu trúc và entry point

| Thư mục | Vai trò |
| --- | --- |
| backend/server.ts, app.ts | Node 24 native TypeScript, Express; pool PostgreSQL và prototype device-events |
| database/001.sql | Schema mới; transaction/unique/FK/ledger guard, không dùng Mongoose |
| ai-service/app.py, runtime.py | FastAPI nội bộ, OpenCV model smoke; chưa cấp Face VERIFIED |
| flutter/template/lib/main.dart | Spike camera, dùng ModernButton kế thừa, chưa là app nghiệp vụ |
| firmware/rfid_spike | Luồng RFID/LCD đối chiếu TapCard, truyền HTTPS/ACK/event mới |
| deploy | Blueprint staging; chưa có VPS hoặc Docker build |
| docs/evidence | Kết quả chạy bản mới; không dùng số cũ làm evidence |
| docs/THIET_KE_THAM_KHAO_02_11.md | Thiết kế/SRS/lịch/test plan trích báo cáo cũ, có đánh dấu lịch sử |

## Chạy lại kiểm thử backend

Yêu cầu Node 24, PostgreSQL 17. Trong backend chạy npm ci bằng npm đi cùng Node 24. Sau đó từ source:

```powershell
.\tools\test-postgres.ps1 -Node 'C:\duong-dan-node24\node.exe'
```

Script khởi tạo cluster test riêng source/.work/postgres-rebuild, chỉ nghe 127.0.0.1:54329, DB smartcard_rebuild_test, chạy kiểm tra TypeScript và test, rồi tắt cluster của mình. Test reset dữ liệu DB test. Không trỏ vào DB thật. Trust auth chỉ dùng local cluster này. Lần đầu có thể mất một phút khi initdb.

Để chạy dev, dùng DB dev riêng, áp dụng 001.sql một lần; copy backend/.env.example thành .env, điền DATABASE_URL và CARD_HMAC_SECRET ngẫu nhiên >=32 ký tự rồi npm start. Backend mặc định loopback; chuẩn bị student, thẻ HMAC, device token hash, class/session/roster bằng công cụ dev, tham khảo cấu trúc trong test nhưng **không gọi fixture reset trên DB dev/thật**. Chưa có API quản trị để cấp các dữ liệu này trong tuần 1. Không dùng prototype cho người dùng thật khi Auth/RBAC và vận hành chưa hoàn thiện.

POST /v1/device-events nhận JSON event_id UUID v4, card_uid chuỗi 8/14/20 hex và purpose ATTENDANCE, Authorization Bearer token thiết bị. Token được hash SHA256 trong devices, UID HMAC server; không đưa HMAC secret lên ESP32. Endpoint từ chối field lạ, kể cả device_id. GET healthz là liveness, readyz kiểm migration. Endpoint khác chưa implement trả 404.

## Chạy lại AI

Tạo Python 3.12 venv ở .venv, cài ai-service/requirements.lock.txt. Chạy tools/fetch-models.py để tải weights public đã ghim commit và kiểm SHA256; manifest/license được lưu riêng. Từ ai-service chạy python -m unittest -v test_runtime; từ source chạy python tools/check-ai.py và python tools/benchmark-ai.py bằng interpreter venv.

HTTP test tự tạo token và tắt server loopback mình tạo. Kết quả mong đợi: health 200, thiếu token 401, readyz/verify có token 503 vì PAD chưa cấu hình. Benchmark dùng ảnh trống/tensor synthetic; không kết luận accuracy hoặc Face <3s trên VPS. AI không có DATABASE_URL.

## Flutter và phần cứng

Đã cài SDK riêng tại .work/toolchains: Flutter3.47.9, Dart3.13.7, AndroidAPI36/build-tools36.0.0 và adb37.0.1. Không thêm PATH toàn máy. Analyze không có issue, widget test và Web release đã đạt; trạng thái APK mới xem docs/evidence/flutter-build.json. Camera0.12.2 yêu cầu AndroidSDK24+; app minSdk24. Build chưa thay test camera máy thật.

Từ source chạy `.\tools\verify-flutter.ps1 -Stage all` để analyze/test/build lại trên app đã scaffold. Có thể dùng -Stage web hoặc -Stage apk khi chỉ cần build lại một phía sau khi kiểm các phần còn lại. Script dùng SDK/cache riêng và khôi phục biến môi trường khi xong; máy này cần jdk.net.unixdomain.tmpdir trỏ tới .work/jtmp để JavaSelector/Gradle chạy được. Probe và log ở docs/evidence/java-selector-*.txt. Không tắt firewall. tools/build-flutter.ps1 chỉ dành lần scaffold đầu, không ghi đè flutter/app có sẵn.

Doctor cảnh báo PATH do cố ý dùng SDK riêng; Windows desktop thiếu C++ không phải mục tiêu Web/Android; license Android không dùng đã bị từ chối, chỉ android-sdk-license được người dùng chấp thuận. Không ghi doctor “tất cả xanh”. Web dùng localhost hoặc HTTPS; APK debug tuần1 không là APK production. Không có ESP32/điện thoại sẵn trong phiên này để thử.

RFID: xác nhận đúng classic ESP32 trước khi dùng SS5/RST4/SPI18-19-23; LCD SDA21/SCL22/0x27 cần I2C scan và kiểm điện áp/pullup. MFRC522 thường dùng 3,3V, không mặc định LCD5V an toàn với GPIO. Cài/chốt version core và MFRC522, LiquidCrystal_I2C, ArduinoJson7 bằng compile thực. Copy secrets.example.h thành secrets.h, cấp Wi-Fi/token/root CA/URL HTTPS riêng. Firmware dùng setCACert, NTP; không bỏ kiểm TLS. Chưa compile/flash/thử board thật.

Thử 1 thẻ hợp lệ, thẻ khóa/hết hạn, ngoài roster, phiên đóng và mất ACK. Đối chiếu event/record trong DB, không chỉ nhìn LCD. Retry tối đa 3 lần giữ cùng payload/event_id trong RAM; hết lần hoặc lỗi cần người vận hành kiểm tra. Chưa có queue bền vững qua mất điện. UID có thể sao chép, không quảng cáo là bằng chứng chống giả mạo.

## Triển khai và quy trình nhóm

Người dùng chọn production thuê VPS4vCPU/8GB/80–100GB và staging tạm trên máy nhóm; chưa mua. Đọc docs/PHUONG_AN_TRIEN_KHAI.md để đối chiếu trần600.000đ/tháng và điều kiệnHTTPS staging. Compose là blueprint DB/backend/AI/proxy, chưa build image/deploy và máy hiện chưa có DockerCLI được kiểm chứng. Hai môi trường dùng DB/volume/secret/role khác nhau; không publishDB/AI. Tạo role app tối thiểu quyền sau bootstrap owner; chưa có Payment posting, worker, backup scheduler, giám sát, resource limits hoặc release signing. InitSQL chỉ chạy trên volume mới; nâng cấp cần migration có backup, không xóa volume.

Mỗi task: đọc source → hiểu input/output/invariant → xác định nguyên nhân → nêu file/rủi ro → sửa nhỏ → chạy test → review chéo và ghi evidence. Hai người 20 giờ/người/tuần; AI hỗ trợ code nhưng không thay người review. Không đưa secret/Face data vào prompt hoặc Git. Chưa tạo Git remote/commit hoặc triển khai dịch vụ bên ngoài trong phiên này.
