# Chạy Smart Campus và kiểm thử từng phân hệ

Áp dụng cho code Smart Campus trong `backend/src`, Flutter hiện tại và firmware `firmware/smart_campus`. Prototype tuần 1 vẫn giữ ở schema PostgreSQL `public` và `backend/prototype-server.ts`. Schema mới `campus` được tạo bằng migration có checksum; **không tự chuyển dữ liệu cũ hoặc xóa database/volume**.

## 1. Chế độ của hệ thống

| Thành phần | Chế độ |
| --- | --- |
| ESP32 + MFRC522 + LCD | RFID THẬT, không có API quét RFID giả trên dashboard |
| Face/Camera/Liveness/OCR | DEMO, chỉ fixture synthetic và có permission |
| Barrier | SIMULATOR, mở cổng và xác nhận xe qua là hai bước |
| Top-up | MOCK, không có giao dịch tiền thật |
| Ví/kho/điểm danh/gửi xe | Dữ liệu và transaction thật trong DB dev/test |

Đây là MVP thử nghiệm. Bootstrap từ chối `APP_ENV=production`; không đổi nhãn DEMO thành REAL để sử dụng với người dùng thật.

## 2. Chạy native trên máy Windows hiện tại

Từ thư mục `source`:

```powershell
.\tools\verify-flutter.ps1 -Stage all
.\tools\start-campus.ps1
```

Script đầu dùng Flutter/Android SDK đã có trong `.work/toolchains`; analyze, widget tests, Web release và APK debug. Script sau tạo cluster PostgreSQL local riêng ở `.work/campus-local`, chỉ nghe `127.0.0.1:54332`, dùng SCRAM và secret ngẫu nhiên. Nó migrate/seed rồi chạy API + worker trên [localhost:8081](http://localhost:8081).

- Xem tài khoản tại `.work/campus-access.txt`, **không chia sẻ/commit tệp này**. Các tài khoản fixture `admin`, `student`, `student2`, `lecturer`, `parking`, `canteen` có đuôi `@campus.test`.
- Mật khẩu và PIN được sinh ngẫu nhiên, không nằm trong README. Lần chạy sau giữ nguyên secret và dữ liệu, không tự cộng thêm point.
- Ctrl+C dừng API và cluster do script tự mở. Nếu tiến trình bị đóng đột ngột, kiểm tra port/process và log trước khi khởi động lại; không xóa data directory để sửa lỗi.
- `-PgBin` và `-Node` cho phép chỉ định toolchain khác. Cần PostgreSQL 17 và Node 24. `npm ci` trong backend khi dependency chưa được cài; Flutter SDK phải thỏa `pubspec.yaml`.

API mới có base `/api/v1`; health ở `/healthz`, readiness ở `/readyz`. Không gọi `/v1/device-events` của prototype để kiểm thử backend mới.

## 3. Chạy Docker Compose

Cần Docker engine đang chạy và Web đã build. Với máy khác có Flutter phù hợp:

```powershell
cd flutter/app
flutter pub get
flutter build web --release --no-web-resources-cdn
cd ../..
node tools/init-compose.mjs
docker compose --env-file deploy/.env -f deploy/compose.yaml config --quiet
docker compose --env-file deploy/.env -f deploy/compose.yaml up --build -d
docker compose --env-file deploy/.env -f deploy/compose.yaml ps
```

`init-compose.mjs` chỉ tạo mới `deploy/.env` và `.work/compose-access.txt`; từ chối ghi đè secret đang có. Nếu đã tạo thì bỏ qua lệnh này. Không đưa `.env` vào Git hoặc báo cáo.

- Web: [localhost:8080](http://localhost:8080). HTTPS local qua cổng 8443 dùng CA nội bộ Caddy; không tự cài CA vào hệ điều hành.
- `bootstrap` chạy migration + runtime grants + synthetic seed rồi thoát; API chỉ khởi động sau bootstrap thành công. Runtime DB role không được sửa ledger hoặc cache balance trực tiếp.
- Database và FastAPI không publish port. FastAPI chỉ có ở profile `future-camera`, không cần model để chạy MVP.
- Các image MVP được pin bằng digest trong Compose/Dockerfile, trùng image cache đã kiểm. Khi đổi pin, đọc release notes và chạy lại checks; profile AI tương lai chưa được nghiệm thu.

- Image backend dùng Web đã build tại `flutter/app/build/web`. Docker build sẽ báo thiếu nếu bỏ qua bước build Web.
- Dừng bằng `docker compose --env-file deploy/.env -f deploy/compose.yaml down`. Không thêm `-v` khi muốn giữ dữ liệu.
- File `.work/campus-access.txt` thuộc native local, `.work/compose-access.txt` thuộc Compose: hai DB/credential độc lập, không trộn tài khoản/PIN giữa hai môi trường.

## 4. Demo phần mềm khi chưa cắm ESP32

Dashboard liệt kê **một reader RFID thật** và các terminal Face DEMO không có credential RFID. Terminal DEMO không phải đầu đọc vật lý, không được dùng làm bằng chứng RFID thật.

1. Đăng nhập `student@campus.test`, vào Ví & thanh toán, yêu cầu nạp point MOCK. Worker nội bộ xác nhận top-up; xem ledger và số dư tăng đúng một lần.
2. Mở tài khoản staff/admin bằng app khác, trình duyệt khác hoặc cửa sổ riêng tư. Tránh dùng hai tài khoản trong hai tab chung refresh cookie của cùng trình duyệt.
3. Bãi xe: chuẩn bị lượt vào, chọn **Bảng Face DEMO: PARKING_ENTRY**, chọn sinh viên mẫu, nhập OCR `59-A1 123.45`, tạo lượt vào. Worker mô phỏng mở; nhân viên xác nhận xe qua mới ACTIVE.
4. Lấy xe: chọn terminal Face DEMO PARKING_EXIT, đúng lượt, sinh viên và biển số. Tính phí từ server. Sinh viên xem yêu cầu trên ví và nhập PIN; staff yêu cầu mở cổng. Point đang giữ chưa là khoản thu. Xác nhận xe ra mới ghi PARKING_PAYMENT và COMPLETED.
5. Cantin: chọn món, tạo đơn, chọn terminal DEMO CANTEEN_POS, nhận diện fixture và gửi yêu cầu. Sinh viên xác nhận PIN; POS hoàn tất mới đồng thời trừ point, giảm kho và hoàn tất đơn.
6. Giảng viên: chọn lịch lớp, tạo và mở phiên đúng camera/phòng. Chọn Face DEMO; thử success/unknown/low confidence/liveness fail. Đóng phiên để chốt ABSENT cho người chưa có bản ghi; điều chỉnh phải có lý do. Web xuất CSV.
7. Dashboard mô phỏng cho phép tạo OCR lỗi/cổng timeout và xem event/linked state. UID chỉ hiện đã che; không có SQL console hoặc bí mật thiết bị trên dashboard.

Sinh viên fixture và biển số là dữ liệu synthetic. Nhận diện không đánh giá ảnh/model thật, confidence là dữ liệu kịch bản. Tài khoản sinh viên mới không tự được xem là fixture hoặc được nhận diện bằng DEMO.

## 5. Các tình huống lỗi quan trọng

- **Thiếu point:** API trả required/available/shortfall; không giữ point hoặc tạo lệnh mở cổng. Nạp MOCK rồi xác nhận lại theo quote còn hiệu lực.
- **Biển số sai/độ tin cậy thấp:** không mở tự động. Staff lưu OCR correction kèm lý do; evidence OCR gốc giữ nguyên.
- **Gate UNKNOWN:** giữ occupancy và hold; không tự thu hay hoàn chỉ vì timeout. Nhân viên xác minh xe qua hoặc chắc chắn chưa qua, lưu lý do/bằng chứng và fence lệnh cũ.
- **Ghi nhầm passage sau khi đã thu:** dùng Đối soát thu phí chỉ sau khi chứng minh xe chưa ra. Reversal toàn bộ, giữ lại occupancy và tăng settlement cycle có audit; quote/approval/lệnh cũ không được dùng lại.
- **Đơn hết hạn:** worker release reservation; checkout cạnh tranh cùng order lock, không vừa bán vừa giải phóng hàng.
- **Mất ACK:** retry cùng eventId/payload hoặc Idempotency-Key. Không tạo key mới để đoán rằng lần đầu thất bại. Tra trạng thái/biên lai trước.
- **PIN sai:** counter lưu trong DB, khóa 15 phút sau 5 lần sai. Không gửi PIN qua reader hoặc đưa vào log.
- **Xóa/revoke Face:** template demo được đánh ERASED; nhận diện/approval mới bị chặn khi profile/consent không còn hiệu lực. Không xóa ledger hoặc attendance lịch sử bằng cascade.

## 6. Kiểm thử và bằng chứng

```powershell
.\tools\test-postgres.ps1
.\tools\test-campus.ps1
.\tools\verify-flutter.ps1 -Stage all
.\tools\compile-firmware.ps1
```

- `test-postgres.ps1`: prototype trên DB riêng port 54329, tên `smartcard_rebuild_test`.
- `test-campus.ps1`: DB riêng port 54331, tên `smartcampus_test`; test **DROP schema campus/TRUNCATE chỉ trong DB test đã kiểm tên/host**. Không thay URL bằng DB dev/thật.
- Campus suite kiểm role DB hạn chế, migration giữ public data, auth/session rotation/RBAC, top-up idempotency, RFID challenge/retry, ví/kho concurrency, parking/gate/reversal, cantin/refund, attendance/consent và Socket.IO owner scope.
- Logs ở `docs/evidence`. HTTP scan contract tests không là quét MFRC522 thật; compile không là flash; build APK không là kiểm máy Android thật.
- Các mục tiêu latency/accuracy trong SRS chưa được coi là đo đạt từ unit/integration tests.

## 7. Backup, migration và dữ liệu cũ

Migration chạy dưới advisory lock, kiểm checksum và chỉ apply bản chưa chạy. Không sửa SQL đã được apply; thêm migration mới. Runtime không giữ owner credential. Dữ liệu prototype `public` không được tự suy đoán term/course/plate/consent rồi nhập sang schema mới.

Trước import dữ liệu cũ: backup, restore vào DB riêng, thống kê duplicate card/vehicle/ledger, chốt mapping và kiểm counts/balance. Các ID/nguồn mơ hồ phải xác minh; không mặc định vehicle_code là biển số hoặc face_profile cũ đã có consent hợp lệ.

Native local đang chạy có thể kiểm backup/restore bằng `tools/verify-local-backup.ps1`: script tạo DB restore tên ngẫu nhiên mới, đối chiếu counts/balance/migrations rồi chỉ xóa DB kiểm tra của nó; dump giữ riêng trong `.work`. Không restore ghi đè DB nguồn.

Khi Compose đang chạy, `tools/verify-compose-backup.ps1` backup rồi restore vào DB kiểm tra tên ngẫu nhiên, so số dư/ledger/orders/parking, xóa đúng DB kiểm tra và giữ dump riêng trong `.work`.

Backup Compose có thể dùng `pg_dump -Fc` bên trong container DB rồi copy file ra `.work`; restore thử vào database tên riêng, không ghi đè DB đang dùng. Trước sử dụng dữ liệu thật cần chính sách backup/retention/xóa dữ liệu và diễn tập restore riêng.

## 8. Giới hạn hiện tại

- Môi trường chỉ development/test, không tiền thật hoặc camera/biometric thật.
- Danh sách UI/API được giới hạn 100 bản ghi gần nhất (event RFID/Face 50); chưa tối ưu báo cáo toàn trường hoặc benchmark tải production.
- Camera/gateway/barrier thật cần adapter, đánh giá và vận hành như [camera integration guide](camera-integration-guide.md).
- Chỉ đánh hoàn thành hardware acceptance sau khi compile/flash/quét/đối chiếu LCD và DB trên thiết bị. Xem [hướng dẫn RFID](RFID_SMART_CAMPUS.md).
