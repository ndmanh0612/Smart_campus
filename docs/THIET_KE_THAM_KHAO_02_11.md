# Tài liệu thiết kế tham khảo ngày 02 tháng 11 năm 2026
CẢNH BÁO PHIÊN BẢN: Trích từ báo cáo cũ. Các số test, benchmark và đường dẫn bên dưới là lịch sử, không phải evidence của bản xây lại 05/11. Trạng thái mới xem NGHIEM_THU_TUAN_1.md và docs/evidence/.
Báo cáo tuần 1 hệ thống thẻ sinh viên AIoT
Thiết kế PostgreSQL và kiểm chứng prototype
Nhóm 2 người   •   20 giờ mỗi người mỗi tuần   •   Bản review ngày 02/11/2026
Báo cáo tập hợp kết quả phân tích, thiết kế, phân công và test plan tuần 1 của dự án xây mới theo PostgreSQL, có module điểm danh bằng khuôn mặt 1:1. Các kết quả đã chạy gồm 14 kiểm thử backend/SQL, 5 kiểm thử AI và 4 kiểm tra HTTP. Đây là evidence của prototype, chưa đủ để đánh dấu toàn bộ tuần 1 đã nghiệm thu.
Máy chưa cài Flutter/Android SDK, chưa thử board/camera thật và chưa thuê VPS. Nhóm cần hoàn thành các mục này, xác nhận lịch và review với giảng viên trước khi đóng mốc. Số tiền trong nghiệp vụ là tiền mô phỏng; chưa kết nối thanh toán thật.

| Phần | Nội dung cần đọc |
| --- | --- |
| 1 Hồ sơ tuần 1 | Đối chiếu năm tiêu chí, trạng thái và việc còn thiếu |
| 2 Khảo sát nguồn | Luồng TapCard và căn cứ thiết kế mới |
| 3 SRS và thiết kế | Nghiệp vụ, invariant, PostgreSQL, API và design pattern |
| 4 Kế hoạch nhóm | 40 giờ mỗi tuần, phụ thuộc và lịch tám tuần dự thảo |
| 5 AI và triển khai | Dữ liệu, metric, model, máy chủ, ngân sách và phục hồi |
| 6 Test plan | 28 ca gốc và các ca bổ sung cho Web Android và thiết bị |
| 7 Kiểm chứng | Kết quả thật, giới hạn và điều kiện đóng tuần 1 |
| 8 Sơ đồ | Danh mục tám sơ đồ và ba hình chính |


# 1 Hồ sơ thực hiện tuần 1 hệ thống thẻ sinh viên đa năng AIoT
Ngày lập 02/11/2026. Kiến trúc xây mới dùng PostgreSQL 17. Hồ sơ phục vụ nhóm hai người và giảng viên review, không tự thay thế biên bản nghiệm thu có xác nhận.
## Kết luận thiết kế và nguồn kiểm chứng
Chốt hướng triển khai kỹ thuật: Express/TypeScript modular monolith, PostgreSQL cho dữ liệu nghiệp vụ và ledger, Python/FastAPI cho Face 1:1, Flutter dùng chung Web/Android, ESP32 + MFRC522 + LCD cho RFID. Hai phương thức nhận diện cùng ánh xạ về student_id, cùng một ví và các service nghiệp vụ. Điểm danh không làm thay đổi số dư. AI không có quyền trừ tiền.
Nguồn ưu tiên là yêu cầu hiện tại của người dùng, kế hoạch 8 tuần v2, PDF Hệ thống thẻ sinh viên đa năng AIoT 21 trang và khảo sát source GitHub. PDF có lộ trình 12 tuần; hồ sơ này dùng nghiệp vụ từ PDF nhưng theo lịch 8 tuần của bản v2. Không nhập lại Face 1:N, OCR/OMR hay dự đoán chuyên cần vào nghiệm thu cốt lõi.
Repository tham chiếu được kiểm tra tại commit 6f600226e3f0f383897ee5d2d607733e5a80c84f. Đã đọc 29 file liên quan; manifest nội bộ giữ URL và SHA-256. Không chạy TapCard với MongoDB, không lấy dữ liệu MongoDB thật và không sao chép code ứng dụng upstream vào dự án mới.
## Đầu vào do nhóm xác nhận

| Hạng mục | Thông tin đã có |
| --- | --- |
| Nhân lực | Hai người: bạn và thành viên 2; cùng phụ trách backend, AI, Flutter, IoT; chia tải và review chéo |
| Quỹ thời gian | 20 giờ/người/tuần; 40 giờ/tuần cho nhóm; 320 giờ trong 8 tuần |
| Phần cứng | Người dùng xác nhận có ESP32, reader RFID, LCD, thẻ và điện thoại Android; chưa đồng nghĩa đã chạy test trên chúng |
| Ngân sách | 300.000–600.000 đồng/tháng; chưa mua VPS/tên miền |
| SDK | Người dùng xác nhận chưa cài Flutter/Android SDK trên máy này |
| Lịch | Dự thảo từ 02/11 đến 27/12/2026; ngày bắt đầu cần nhóm xác nhận, chưa phải lịch được giảng viên duyệt |


## Bộ sản phẩm đã chuẩn bị
1. Khảo sát TapCard ở mức source, entry point, dependencies, config và luồng RFID, kèm các điểm không kế thừa.
2. Đặc tả yêu cầu, vai trò, giới hạn, quy tắc định danh, xác minh, điểm danh, thanh toán, hoàn tiền và gửi xe.
3. Tám sơ đồ kiến trúc, Use Case, Class, Sequence điểm danh/thanh toán, Activity gửi xe và hai ERD PostgreSQL ở dạng source lẫn hình.
4. SQL thiết kế, API contract mục tiêu, cấu trúc repo và quyết định chọn pg/SQL thay Mongoose.
5. Prototype RFID-to-PostgreSQL có test tích hợp thực; bản thử AI runtime và chương trình camera/firmware để nhóm kiểm tra tiếp.
6. Phân công và lịch 8 tuần phù hợp 40 giờ/tuần, dự toán trong ngân sách, kế hoạch staging/production, test plan và mẫu evidence.
## Ma trận đối chiếu 5 tiêu chí tuần 1

| Tiêu chí trong kế hoạch | Sản phẩm và bằng chứng | Trạng thái nghiệm thu |
| --- | --- | --- |
| 1 Phạm vi, người phụ trách, lịch, điều kiện còn thiếu; Web và APK | SRS, backlog và lịch 8 tuần; thông tin nhân lực do nhóm xác nhận | Hồ sơ đã lập; chờ nhóm xác nhận lịch và phân công, giảng viên review |
| 2 Kiến trúc/ERD có định danh, ví, ledger, căn tin, gửi xe và chống trùng | Bộ UML/ERD, SQL baseline, các invariant, test SQL và attendance | Thiết kế và prototype kiểm chứng được; chưa phải sản phẩm đầy đủ |
| 3 Bản thử RFID/camera, hai build Flutter, version/model/license/thiết bị | Code spike, manifest model, test backend/AI; checklist phần cứng và Flutter | Chưa đủ: chưa cài SDK, chưa có build Web/APK hay test camera/RFID thật |
| 4 Chốt VPS theo thử tải AI, chi phí, domain, quyền và tách môi trường | Dự toán và topology; benchmark local ghi rõ phạm vi | Chưa đủ: chưa mua/trial VPS, domain và người vận hành chưa được nhóm xác nhận |
| 5 Dataset AI, mục tiêu, tải 20 client, P95, backup/restore và test plan | Protocol thu thập/split, mục tiêu pilot, kịch bản đo và phục hồi; kế thừa 28 test PDF | Test plan đã lập; threshold thực nghiệm và chất lượng PAD còn chờ dữ liệu, không ghi đã đạt |


Trạng thái kỹ thuật cập nhật chi tiết trong 06-bien-ban-kiem-chung.md và thư mục evidence. Tài liệu này không đánh dấu toàn bộ tuần 1 là Đạt. Mục còn thiếu phải có người phụ trách và bằng chứng thực trước khi ký nghiệm thu.
## Việc nhóm cần làm để đóng tuần 1

| Việc | Người phụ trách đề xuất | Điều kiện xác nhận |
| --- | --- | --- |
| Cài Flutter/Android SDK, chạy doctor, build Web và APK | thành viên 2 thực hiện, bạn review | Log doctor/build, version, checksum APK và URL/file Web |
| Nạp bản thử cho board phù hợp, quét thẻ thật → backend → PostgreSQL → LCD | thành viên 2, bạn quan sát DB | Sơ đồ dây đã kiểm, video/serial và request/event ID; retry không trùng |
| Thử camera Web qua HTTPS hoặc localhost, Android máy thật | thành viên 2 thực hiện, bạn review | Cho phép/từ chối camera, ảnh chụp, app pause/resume; không ghi nhận tự động bằng Face khi PAD chưa có |
| Chọn domain, trial/mua VPS trong ngân sách; benchmark trên VPS | Bạn thực hiện, thành viên 2 review | Hóa đơn/cấu hình, số đo CPU/RAM/AI thực, xác nhận quyền quản trị; không gửi secret vào chat hoặc Git |
| Xác nhận lịch và thu thập pilot có đồng ý | Cả hai | Ngày bắt đầu, danh sách ẩn danh, consent, split manifest và người giữ khóa/dữ liệu |
| Review hồ sơ và xin giảng viên nhận xét | Cả hai | Bản chốt có trạng thái Đạt/Chưa đạt và hạn bổ sung cho từng tiêu chí |


## Cách đọc hồ sơ
Đọc 01 để hiểu khác biệt với TapCard; 02 để học nghiệp vụ và thiết kế; 03 để nhận việc theo giờ; 04 để chuẩn bị AI và máy chủ; 05 để chạy đúng test và lưu evidence; 06 để phân biệt kết quả thật với phần chưa kiểm chứng. SQL và OpenAPI là bản đầu có thể review, chưa đóng băng trước mọi phản hồi nghiệp vụ.
# 2 Khảo sát TapCard và quyết định xây mới
Nguồn: https://github.com/ndmanh0612/tapcard-iotproject tại commit 6f600226e3f0f383897ee5d2d607733e5a80c84f, khảo sát ngày 02/11/2026. Chỉ kết luận từ 29 file đã đọc và cây file trả về; không xác nhận hệ thống upstream chạy thành công.
## Cấu trúc và luồng hiện có

| Thành phần | Entry point và dependency đã thấy | Vai trò |
| --- | --- | --- |
| express/ | src/index.ts; Express ^4.21.2, Mongoose ^8.4.1, Socket.IO ^4.8.3, jsonwebtoken, bcrypt, TypeScript | Kết nối Atlas, mount auth/user/reader/tag/attendance, tạo HTTP server và Socket.IO |
| flutter/ | lib/main.dart; Dart constraint ^3.7.2, Provider, http, Socket.IO client và plugin Wi-Fi | Khởi tạo các provider; login, hồ sơ, gán thẻ và màn hình điểm danh |
| arduino/ | arduino.ino; MFRC522, LCD I2C, AESLib, HTTPClient | Đọc UID, mã hóa rồi gửi reader/tag tới attendance/swipe, phân tích phản hồi để hiện LCD |


Data flow đã đọc: MFRC522 → UID → firmware encrypt → HTTP POST /attendance/swipe → swipeTag → reader/tag lookup → tìm attendance có reader và isOpen → thêm student vào mảng students → io.emit → Flutter/LCD. Đây là mô tả source, chưa phải kết quả thử board.
DB gồm các Mongoose model user, reader, tag, attendance, track và access. Attendance dùng một document chứa danh sách students cho phiên. Không thấy bảng lớp/ghi danh, wallet/ledger, Face hoặc các nghiệp vụ thu phí trong các file khảo sát này. Muốn mở rộng theo PDF phải thiết kế mới các quan hệ và transaction; đổi riêng connection string không đủ.
## Những phát hiện ảnh hưởng trực tiếp tới thiết kế mới

| Phát hiện được chứng minh từ source | Hệ quả hoặc rủi ro | Quyết định trong bản mới |
| --- | --- | --- |
| db.config.ts gọi mongoose.connect(env.ATLAS) | Tầng truy cập dữ liệu phụ thuộc MongoDB | Viết SQL và migration PostgreSQL từ đầu; không cài Mongoose |
| attendance.router.ts gắn /swipe trực tiếp, không middleware xác thực người dùng; body tự khai reader | Không có device credential độc lập ở route này theo luồng đã đọc | Token riêng mỗi thiết bị, lookup identity từ token, không tin device_id trong body |
| swipeTag tra tag nhưng không kiểm tra tag.status/validFrom/validTo trước ghi attendance | Thẻ khóa/hết hạn có thể không bị chặn ở chính luồng này | Kiểm trạng thái và thời hạn trong Identity; test thẻ revoked bắt buộc |
| swipeTag tìm phiên theo reader,isOpen; không có lớp/roster trong luồng | Chưa chứng minh được sinh viên thuộc lớp của phiên | ClassSession + roster snapshot + composite FK attendance |
| Kiểm includes rồi push/save danh sách students | Chưa có invariant SQL cho mỗi session/student; cần kiểm thử race nếu kế thừa | UNIQUE(session_id,student_id), event dedupe và transaction |
| auth.controller.ts loginUser ghi password hash và rawPassword qua console.log | Có nguy cơ lộ mật khẩu trong log khi code chạy | Không log password, PIN, token, UID thô hay vector/ảnh Face |
| createEntity ghi secret key ra log; swipe dùng CBC với IV cố định | Không kế thừa cơ chế này làm lớp bảo vệ mạng | HTTPS xác minh chứng chỉ + credential riêng + idempotency/TTL; UID vẫn có giới hạn bảo mật |
| index.ts dùng CORS mở và io.emit broadcast | Cần kiểm quyền HTTP và Socket.IO theo phạm vi dữ liệu | Origin allowlist; room theo lớp/người dùng sau auth; snapshot qua API |
| Android app/build.gradle.kts release dùng signingConfig debug | Không đáp ứng APK phát hành có khóa ký do nhóm quản lý | Tạo signing riêng ở tuần 6; backup khóa ngoài Git |
| Main manifest cho phép cleartext; pubspec chưa có camera plugin | Không có bằng chứng camera Web/Android đạt yêu cầu từ repo hiện có | Bản Flutter mới có camera, permission và lifecycle test; không dùng plugin Wi-Fi nếu chưa cần |


Các rủi ro concurrency/chạy thực ở trên chưa được tái hiện trên app upstream. Những kết luận về cách viết code, middleware và log đã được đọc trực tiếp; không phóng đại thành kết luận đã xảy ra sự cố ở người dùng thật.
## Cấu hình và license
Upstream dùng env cho Atlas/JWT cùng cấu hình firmware và base URL trong Flutter. Không đưa giá trị cụ thể vào tài liệu này. Snapshot khảo sát không tải .env và đã che literal credential; nằm trong .work được ignore.
express/package.json khai báo metadata license: GPL-3.0-only và trỏ về dự án TapTag upstream khác trong repository metadata. Đây là ghi nhận metadata, không phải kết luận pháp lý cho toàn bộ nội dung repository. Bản mới không copy source ứng dụng/firmware từ repository; chỉ dùng làm căn cứ so sánh nghiệp vụ và luồng kỹ thuật. License model/code/thư viện của bản mới được ghi riêng.
## Môi trường quan sát ngày 02 11 2026
Máy kiểm tra: Intel Core i7-1255U, 10 core/12 logical processor, khoảng 7,69 GiB RAM nhận diện bởi OS. Có PostgreSQL 17.9 và runtime Node 24.22.1 được dùng để build/test. Node mặc định của npm hệ thống là 25.6.0 nên các lần kiểm chứng dùng đường dẫn Node 24 rõ ràng, không kết luận toàn máy đã đổi PATH.
Docker client có nhưng Linux engine chưa kết nối được tại thời điểm kiểm tra. Flutter/Android SDK chưa cài, do người dùng xác nhận. Không thấy cổng serial được CIM trả về ở lần đọc; điều này không phủ nhận nhóm sở hữu bộ RFID, nhưng chưa có bằng chứng board đang kết nối với phiên làm việc này.
# 3 Đặc tả yêu cầu và thiết kế bản đầu
Phạm vi mới dựa trên PDF trang 3–15 và lịch 8 tuần v2. Tiền trong hệ thống là giá trị thử nghiệm, không kết nối tài khoản ngân hàng hoặc tiền thật. Web và Android gọi chung API và nguồn PostgreSQL. PostgreSQL 17 là lựa chọn xây mới theo yêu cầu người dùng, không có migration dữ liệu từ MongoDB.
## Vai trò và nghiệp vụ

| Vai trò | Quyền trong phạm vi |
| --- | --- |
| Sinh viên | Hồ sơ, điểm danh, xem ví/lịch sử của mình, yêu cầu nạp demo và xác nhận khoản chi |
| Giảng viên | Mở/đóng phiên, xem/sửa có lý do và xuất điểm danh lớp được phân công |
| Nhân viên căn tin | Quản lý đơn tại terminal được cấp quyền, xem biên nhận; không tự chỉnh ví |
| Nhân viên gửi xe | Kiểm tra xe/vé, mở lượt, chốt phí và xác nhận ra xe; không bỏ qua thanh toán âm thầm |
| Admin | Tài khoản/quyền, thiết bị/thẻ, phê duyệt nạp, giá/phí và audit; không sửa ledger đã ghi sổ |
| ESP32/terminal | Credential riêng, phạm vi nghiệp vụ gắn phía server; không truy cập DB hoặc tự cho phép chi tiền |


Một người có thể có nhiều role qua user_roles. Quyền role là chưa đủ: mọi truy cập phải kiểm tra sở hữu hồ sơ/ví, phân công lớp hoặc terminal. Device credential không thay thế token đăng nhập của con người.
## FR và phạm vi ưu tiên

| ID | Yêu cầu và tiêu chí tối thiểu |
| --- | --- |
| FR01 | Auth, revoke phiên và quyền từng tài nguyên; không lộ hồ sơ/ví người khác |
| FR02 | Sinh viên chung student_id, cấp/khóa thẻ, consent/đăng ký/thu hồi Face và quản lý device |
| FR03 | Lớp, ghi danh, roster khi mở buổi, RFID hoặc Face 1:1; một record mỗi sinh viên/buổi; không đổi ví |
| FR04 | Một ví/sinh viên; nạp có phê duyệt, lịch sử và ledger cân bằng, không âm số dư sinh viên |
| FR05 | Căn tin: server tính giá từ menu, người trả xác nhận amount, một intent/một SALE/nguồn, refund toàn bộ một lần |
| FR06 | Gửi xe: đối chiếu người và xe/vé, một lượt chưa đóng/xe, phí có version và một khoản thu/lượt |
| FR07 | Web/Android, snapshot/receipt khi mất thông báo, audit và báo cáo theo quyền |


P0 gồm định danh, RFID/Face 1:1, điểm danh, ví và căn tin; gửi xe cơ bản có trong lịch 8 tuần và phải tích hợp trước bản release candidate. P2 gồm OCR/OMR, Face 1:N, dự đoán chuyên cần, OCR biển số và phát hành Google Play. Không mở rộng P2 khi core, ledger hoặc kiểm thử phục hồi còn thiếu.
## Bất biến cần giữ
1. Điểm danh không tạo khoản chi. RFID và Face là hai phương thức xác minh cùng một student_id và wallet_id.
2. Verification phải được backend phát hành, gắn purpose, student, terminal, nguồn nghiệp vụ và TTL; client không được tự gửi trạng thái VERIFIED.
3. Face dùng claimed student code hoặc tài khoản đã xác định để so 1:1; không tìm người gần nhất trên toàn trường. Quality, matching và PAD là các kiểm tra riêng. PAD chưa đạt thì không tự xác minh bằng Face cho thanh toán.
4. Một hóa đơn/lượt thu phí có một intent; một intent chỉ có một SALE. Đổi Idempotency-Key không được tạo thêm khoản ghi nợ cho cùng nguồn.
5. Tổng delta mỗi ledger transaction bằng 0; ví sinh viên không âm. Chỉ SIM_SOURCE có thể âm theo thiết kế tiền demo. Số dư là cache của ledger, không có balance thứ hai ở wallets.
6. Posted ledger không được sửa/xóa hoặc thêm entries sau khi đã commit. Hoàn toàn bộ bằng reversal mới tham chiếu SALE gốc, một lần.
7. AI trả evidence, không được cập nhật ví; Payment kiểm tra quyền, confirmation, binding và số dư trong transaction.
8. Thông báo không là nguồn dữ liệu. Commit thành công nhưng mất response phải tra lại intent/receipt, không tạo nguồn mới.
9. Khi lấy xe phải khớp xe/vé và lượt gửi, không chỉ khớp khuôn mặt. Đã trả tiền nhưng chưa ra xe giữ receipt để nhân viên xử lý; không thu lại.
## Use case bản đầu

| UC | Luồng chính | Ngoại lệ cần giữ |
| --- | --- | --- |
| UC01 Quản lý định danh | Admin tạo hồ sơ; cấp thẻ; enrollment Face có xác minh/consent; khóa/thu hồi có audit | UID active trùng, sai người, revoke khi inference đang chạy |
| UC02 Điểm danh | GV mở phiên và chốt roster; xác minh RFID/Face theo purpose; Attendance khóa phiên và insert unique | Ngoài lớp, phiên đóng, retry, hai phương thức đồng thời, mạng mất |
| UC03 Nạp demo | SV yêu cầu; admin duyệt; posting cân bằng từ SIM_SOURCE sang account SV | Approval lặp/đồng thời, sai quyền, cùng nguồn đổi key |
| UC04 Căn tin | NV tạo order cho SV được chỉ định; server chốt giá; tạo intent; xác minh và SV xác nhận; posting; receipt | Client sửa giá, thiếu hoặc sai confirmation, thiếu tiền, verification hết hạn, response mất |
| UC05 Refund | Người có quyền chọn SALE; đối chiếu nguồn; reversal toàn bộ có audit | Lặp refund, original không phải SALE, tiền hoàn/đối ứng sai |
| UC06 Gửi xe | Request vào/ra có TTL; xác minh; đối chiếu xe; mở lượt hoặc chốt phí/intent; PAID rồi xác nhận ra | Xe sai, lượt mở trùng, fee version thay đổi, đã trả nhưng chưa ra, thiếu tiền |


Nhận dạng danh tính không đồng nghĩa đồng ý chi tiền. Đối với UC04, MVP chốt sinh viên xác nhận trên Web/Android đã đăng nhập sau khi xem intent và số tiền do server trả. Endpoint confirm chỉ cho chính chủ ví gọi, kiểm expected_amount khớp amount đã khóa và verification đúng terminal của intent. Không nhận confirmation=true do POS tự khai như bằng chứng đồng ý. PIN tại POS để ngoài MVP nhằm giảm phần phải bảo vệ và kiểm thử; prototype xác nhận app được hiện thực ở tuần 4–5.
## Kiến trúc và design pattern
Backend một ứng dụng chia module Auth, Student/Card, Identity, Classroom/Attendance, Wallet/Payment/Ledger, Canteen, Parking, Audit/Realtime. FastAPI là dịch vụ inference nội bộ; không có credential PostgreSQL hoặc quyền ví. Firmware và Flutter chỉ gọi backend qua HTTPS. Media/embedding không được public; embedding được mã hóa với key_id, key nằm ngoài DB.
Service Layer giữ nghiệp vụ; controller xử lý HTTP. Strategy có lý do thật ở RFID và Face cùng trả VerificationResult. AIClient là Adapter để cô lập schema, timeout và lỗi. Truy vấn dùng pg/SQL và cùng transaction context; không thêm Prisma/TypeORM song song. State machine dùng enum/check và transition guard. Outbox được thiết kế cho sự kiện hậu commit; worker consumer phải dedupe, không xem Socket.IO là broker bền vững.
## PostgreSQL và các quyết định dữ liệu
SQL trong database/ được chạy kiểm tra trên PostgreSQL 17 thật, không thay bằng SQLite hoặc mock khi kiểm tra khóa/unique/rollback. UUID được application tạo; TIMESTAMPTZ lưu thời điểm tuyệt đối; hiển thị Asia/Ho_Chi_Minh. Tiền dùng BIGINT VND trong DB, JSON truyền chuỗi số nguyên thập phân để không mất chính xác khi qua JavaScript; amount từ server, không lấy số tiền client làm nguồn sự thật.
Các nhóm bảng: users/user_roles/students; student_cards/devices; classes/enrollments/teaching_assignments/class_sessions/roster; face_profiles/verification_sessions; wallets/ledger_accounts/transactions/entries; menu/orders/items; vehicles/rates/parking_sessions/requests; payment_intents/topup/idempotency/outbox/audit.
Quyết định quan trọng: payment_intents dùng hai FK có kiểu rõ ràng canteen_order_id hoặc parking_session_id, CHECK đúng một nguồn và unique riêng từng nguồn. API vẫn dùng source_type/source_id nhưng service ánh xạ sang FK. Cách này tránh một source_id đa hình không có FK thật. Intent có composite FK theo student_id để không dùng ví của sinh viên khác cho nguồn đó. parking_requests tạo context cho xác minh trước khi lượt gửi mới tồn tại. Các chi tiết này làm rõ hơn ERD rút gọn trong PDF, chưa phải đổi nghiệp vụ.
Attendance UNIQUE(session_id,student_id) và FK tới roster. Device events UNIQUE(device_id,event_id), request_hash và response đã lưu. Một thiết bị chỉ có một assignment chưa release. UID active dùng partial unique. Một xe chỉ có một parking session chưa closed. SALE(intent), TOPUP(request) và REVERSAL(original) đều unique theo nguồn.
Ledger có deferred constraint trigger kiểm tra ít nhất hai entries và tổng delta=0 lúc commit. Guard creation_xid chặn thêm entry vào header đã ghi ở transaction trước; BEFORE UPDATE/DELETE chặn sửa lịch sử. Việc kiểm tra account kind, binding, số tiền debit/credit, cache balance, reversal đúng SALE/amount và quyền posting vẫn thuộc Payment/Ledger Service cần làm và test tuần 4. SQL balanced không tự chứng minh mọi bút toán đã được phép.
## Transaction thanh toán mục tiêu
Xác minh Face và nhập confirmation diễn ra trước, ngoài DB lock dài. Khi confirm, reserve idempotency key/hash; lock intent; nếu đã PAID thì trả receipt cũ sau kiểm quyền. Kiểm nguồn, amount, expiry và confirmation; lock verification và kiểm student/terminal/purpose/source/TTL/unused; lock các account theo ID cố định; kiểm ví active và đủ tiền. Insert SALE unique; insert hai entry đối ứng; update balance cache; consume verification; cập nhật intent/order; lưu receipt, idempotent result và outbox trong cùng transaction rồi commit.
Lỗi phải rollback toàn bộ. Không gọi AI hoặc gửi thông báo trong transaction. Deadlock/serialization lỗi tạm thời có thể retry cả transaction giới hạn, giữ key; thiếu tiền/sai quyền không retry. Refund dùng đường posting kiểm soát với kiểm tra SALE gốc và số tiền đảo chính xác. Đây là thiết kế, không khẳng định Payment Service đã implement tuần 1.
## API contract và prototype
Contract OpenAPI trong docs/api là mục tiêu, có security, schema, money dạng string, enum trạng thái và lỗi có code/request_id. Auth/RBAC đầy đủ làm ở tuần 2; Face ở tuần 3; posting ở tuần 4. Đường /v1/device-events của prototype chỉ hỗ trợ ATTENDANCE, không dùng trực tiếp cho Face hoặc thanh toán. Prototype ghi evidence RFID trực tiếp, chưa đi qua verification session hoàn chỉnh; việc này được khoanh vùng trong báo cáo để không nhầm đã hoàn thành Identity Service.
Mọi endpoint chưa implement phải trả lỗi rõ, không giả lập PAID/VERIFIED. Face/PAD chưa cấu hình trả không sẵn sàng. Dữ liệu thật và secret nằm ngoài Git; không hạ TLS validation trên ESP32 để làm demo “chạy được”.
## Quy trình làm việc có hỗ trợ AI
Vibe coding trong nhóm được hiểu là dùng AI hỗ trợ đọc, soạn và sửa code; hai người vẫn chịu trách nhiệm về thiết kế, quyền truy cập và bằng chứng kiểm thử. Không đưa password, token, ảnh/embedding thật hoặc dữ liệu sinh viên vào prompt. Không nhận một đoạn code chỉ vì AI nói “chạy được”.
Mỗi đầu việc đi theo thứ tự: đọc file liên quan và cấu hình; mô tả luồng input/output và invariant; tách điều đã chứng minh khỏi giả thuyết; nêu phương án, file ảnh hưởng và rủi ro; sửa phần nhỏ; chạy kiểm tra phù hợp; giải thích kết quả và phần chưa kiểm. Thay đổi ví, xác minh hoặc quyền phải có người còn lại review trước khi nhập vào nhánh dùng chung. Không bắt buộc chờ tuần sau mới đọc việc tuần sau, nhưng triển khai phải theo phụ thuộc và điều kiện qua mốc của lịch.
Các kỹ năng cần luyện gắn với đầu ra thật: SQL transaction/khóa/constraint qua các test đồng thời; HTTP contract và authorization qua ca sai quyền; AI evaluation qua split và metric; Flutter qua permission/lifecycle; IoT qua TLS/ACK/retry; vận hành qua restore và đối soát. Không cài thêm framework hoặc skill chỉ để tăng số công cụ; giải thích được vai trò trước khi thêm dependency.
Mẫu giao việc cho AI: “Đọc các file liên quan đến [luồng]. Mục tiêu là [hành vi], giữ [invariant]. Chỉ sửa [phạm vi]; trước khi sửa nêu nguyên nhân và ảnh hưởng. Sau đó chạy [kiểm tra], báo actual/evidence và ghi rõ phần chưa chạy.” Mỗi lần chỉ xử lý một luồng đủ nhỏ để người review đọc hết thay đổi và tái hiện được kết quả.
Khi làm chung, giữ secret ngoài Git, không ghi đè thay đổi của người kia, dùng branch riêng theo đầu việc và commit mô tả hành vi. Tuần 1 chưa thiết lập remote/CI trong workspace này; lịch tuần 2 mới hoàn thiện nhánh chung, CI và staging. Checklist dùng AI không thay cho test, review hay nghiệm thu của giảng viên.
# 4 Phân công 2 người và lịch 8 tuần
Đầu vào do người dùng xác nhận: bạn và thành viên 2, mỗi người 20 giờ/tuần. Dưới đây là phân công đề xuất để review/chốt; giờ là dự toán, không phải timesheet đã thực hiện. Hai người cùng học và chịu trách nhiệm cả backend/AI/Flutter/IoT, luân phiên phần chính và review chéo. Không tính công cụ AI là thành viên thứ ba.
## Backlog tuần 1

| ID | Công việc | Chủ trì | Review | Giờ |
| --- | --- | --- | --- | --- |
| W1-A01 | SRS, phạm vi, quy tắc và acceptance | Bạn | thành viên 2 | 4 |
| W1-A02 | PostgreSQL, ERD, invariant ledger và nguồn thanh toán | Bạn | thành viên 2 | 5 |
| W1-A03 | Backend spike, SQL test, idempotency và rollback | Bạn | thành viên 2 | 4 |
| W1-A04 | Protocol AI, model/license và tiêu chí đánh giá | Bạn | thành viên 2 | 3 |
| W1-A05 | Tổng hợp hồ sơ, evidence và rủi ro | Bạn | thành viên 2 | 2 |
| W1-A06 | Review camera/firmware/triển khai của thành viên 2 | Bạn | thành viên 2 | 2 |
| W1-B01 | Khảo sát source TapCard và sơ đồ luồng hiện tại | thành viên 2 | Bạn | 3 |
| W1-B02 | Cài SDK, camera và build Web/APK | thành viên 2 | Bạn | 6 |
| W1-B03 | Sơ đồ dây, RFID board thật và LCD/HTTP retry | thành viên 2 | Bạn | 4 |
| W1-B04 | VPS/domain/backup, ngân sách và tách môi trường | thành viên 2 | Bạn | 3 |
| W1-B05 | Test plan, kịch bản build và evidence | thành viên 2 | Bạn | 2 |
| W1-B06 | Review DB/AI/API và buổi chốt với nhóm | thành viên 2 | Bạn | 2 |


Tổng bạn 20 giờ, thành viên 2 20 giờ. Các sản phẩm do assistant chuẩn bị giúp giảm thao tác soạn và viết prototype, nhưng hai người vẫn cần đọc, chạy lại, làm phần thiết bị và ký review. Không tự đánh dấu các giờ dự toán là đã hoàn thành vì có file.
## Lịch tuần 1 theo thứ tự phụ thuộc
Ngày 1: đọc nguồn, chốt yêu cầu và setup; ngày 2: API/ERD và hardware/camera spike; ngày 3–4: PostgreSQL/RFID backend, model load/benchmark và build; ngày 5: tích hợp thiết bị và review; ngày 6: xử lý lỗi, đo và viết evidence; ngày 7: chốt hồ sơ/giảng viên, hoặc bổ sung phần chưa đạt. Không đợi vẽ xong mọi UML mới thử camera; khả năng camera/SDK/model phải được kiểm tra sớm.
## Lịch 8 tuần dự thảo
Ngày bắt đầu tạm dùng 02/11/2026, cần nhóm xác nhận. Mỗi ô phân công có tổng 20 giờ. Cột đầu ra không có nghĩa đã đạt.

| Tuần và thời gian | Bạn, 20 giờ | thành viên 2, 20 giờ | Điều kiện qua mốc |
| --- | --- | --- | --- |
| 1: 02–08/11 | SRS 4; DB 5; backend 4; AI plan 3; hồ sơ 2; review 2 | Khảo sát 3; SDK/camera/build 6; IoT 4; VPS 3; test plan 2; review 2 | Thiết kế review, test prototype, hai build và thử thật; còn thiếu phải có hạn |
| 2: 09–15/11 | Auth/DB 8; RFID/session 5; test 3; review/tích hợp 4 | Flutter 8; IoT 6; staging/CI 4; review 2 | RFID thật → DB → Web/Android trên staging HTTPS, đúng quyền |
| 3: 16–22/11 | Enrollment/AI 10; Identity 6; review/test 4 | Camera 7; gửi xe cơ bản 6; UI 5; review 2 | Face 1:1 + PAD có số đo; vào/ra xe chưa bỏ qua thanh toán |
| 4: 23–29/11 | Wallet/ledger 10; concurrency/security 6; review 4 | UI ví 6; test tích hợp 6; backup/restore 6; review 2 | Posting đúng, không âm/ghi lặp, restore staging đối soát khớp |
| 5: 30/11–06/12 | Payment tích hợp 8; security 6; sửa lỗi 4; review 2 | Căn tin/parking UI 8; E2E 7; tải 3; review 2 | Ba nghiệp vụ, test tài chính/quyền, release candidate |
| 6: 07–13/12 | DB/deploy/backup 8; monitoring 6; test/review 6 | HTTPS/Web/APK ký 8; smoke 6; runbook/review 6 | Production, alert/restore/rollback thực; đủ điều kiện mở pilot |
| 7: 14–20/12 | Triage backend/AI 8; đối soát 6; sửa/review 6 | UAT 8; UI/IoT fix 6; evidence/review 6 | 5–10 người tự nguyện, 3–5 ngày; xử lý lỗi và lưu evidence |
| 8: 21–27/12 | Báo cáo 8; hồi quy 6; bàn giao 4; review 2 | Slide/video 8; demo 6; vận hành 4; review 2 | Giữ dịch vụ, code/tài liệu/số đo thống nhất, bàn giao có người nhận |


Tổng dự toán 160 giờ/người và 320 giờ cả nhóm. Nếu việc cài SDK, hardware hoặc dữ liệu làm tuần 1 vượt tải, không bù bằng cách bỏ test tài chính; cắt P2, thu hẹp UI và báo rõ lịch điều chỉnh với giảng viên.
## Trách nhiệm vận hành đề xuất
Bạn là đầu mối DB/backup và sự cố backend/AI; thành viên 2 là đầu mối build/phát hành Web/Android và thiết bị; hai người đều đọc được runbook, có quyền dự phòng phù hợp. Tài khoản mua VPS/domain thuộc nhóm/người dùng, bật MFA và không chia secret qua Git/chat. Phân công này cần hai người xác nhận trước khi coi là đã có người vận hành chính thức.
## Những điểm còn phải xác nhận
Ngày bắt đầu chính thức; tên miền có thể đăng ký; gói/chu kỳ thanh toán VPS và chi phí trả trước; người đứng tên/chi trả; máy Android/API level, board ESP32/reader/LCD thực tế; danh sách người pilot và consent; ngưỡng đạt của pilot được giảng viên đồng ý. Không yêu cầu nhóm gửi password, token hay khóa ký vào tài liệu.
# 5 AI và phương án triển khai trong ngân sách
## Chốt phần AI của MVP
Face 1:1 so capture với template của student_id đã khai báo hoặc tài khoản đã đăng nhập. YuNet/SFace là baseline kỹ thuật; PAD là module độc lập chưa có model được đánh giá trong workspace. Không gán VERIFIED nếu chỉ cosine cao nhưng PAD chưa đạt. Khi không sẵn sàng, dùng RFID/đối soát theo policy; không giả lập PAD_PASS hoặc score ngẫu nhiên.
Model manifest giữ upstream commit, file, SHA-256 theo Git LFS và license của từng thư mục model. License thư viện OpenCV không mặc định thay cho license mọi weights; đọc notice cụ thể trong licenses/. Baseline dùng OpenCV headless 4.12.0.88 và NumPy 2.2.6 để giữ API đã thử; không tự nâng OpenCV 5 chỉ vì có bản mới.
Chưa chọn PAD thay thế bằng một model tên nghe phù hợp. Việc chọn PAD cần input modality, license code/weights/data, CPU latency, tấn công thử và khả năng tái lập. Nếu tuần 3 chưa chứng minh được, hạn chế Face theo kế hoạch, không dùng cho thanh toán tự động. Student vẫn phải xác nhận khoản chi trong app đã đăng nhập, kể cả Face đạt.
## Protocol dữ liệu pilot
Mục tiêu thu 20–30 người tự nguyện như PDF; nếu chỉ thu được ít hơn thì báo cỡ mẫu thật, không bổ sung số giả. Mỗi người có ảnh enrollment tách riêng, một buổi development và một buổi held-out test khác thời điểm. Ưu tiên tách người giữa development/test nếu số người đủ; nếu chưa đủ, nêu hạn chế generalization. Không chia frame liền kề cùng video sang hai tập.
Đề xuất mỗi người có 3 ảnh enrollment, 5 capture development và 5 capture test với sáng trước mặt, hơi nghiêng, kính khi phù hợp và hơi thiếu sáng. Đây là quota dự kiến, chưa phải dataset đã thu. Mẫu chất lượng thấp và lỗi thu nhận phải được đếm, không chỉ giữ ảnh đẹp. Cặp genuine cùng người và impostor khác người được lập bằng manifest có seed cố định; không đưa student name/ảnh vào Git.
PAD cần mẫu người thật và ảnh in/màn hình/video phát lại được người tham gia đồng ý. Ghi loại tấn công, thiết bị, điều kiện chụp và giới hạn. Không tuyên bố chống tất cả deepfake từ một bộ mẫu nhỏ. Lưu dữ liệu mã hóa, phân quyền hai người theo nhiệm vụ; ngày xóa và cách xử lý backup phải được thống nhất với người tham gia trước khi thu.
## Mục tiêu đánh giá đề xuất để giảng viên chốt

| Hạng mục | Mục tiêu pilot ban đầu | Trạng thái |
| --- | --- | --- |
| Matching 1:1 | FMR ≤1%, FNMR ≤10%; ghi mẫu số và khoảng tin cậy | Mục tiêu kỹ thuật đề xuất, chưa đo và chưa được giảng viên duyệt |
| PAD | APCER ≤5% từng loại đã thử, BPCER ≤10%; không gộp attack types che kết quả xấu | Đề xuất; chưa có model/dataset nên không coi đã đạt |
| Runtime | P95 Face phía server <3 giây, gồm quality/PAD/embedding/matching | Mục tiêu từ kế hoạch; benchmark synthetic không chứng minh full pipeline |
| Thu nhận | Báo tỷ lệ no-face, nhiều mặt, capture/enrollment thất bại, chất lượng không đạt | Đếm riêng, không biến lỗi thu nhận thành “matching đúng” |


Các mục tiêu lỗi trên chỉ dành pilot tiền thử nghiệm, không là chuẩn đủ cho thanh toán thật. Khóa similarity threshold từ development theo trade-off rồi test một lần trên held-out test; hiện để threshold chưa hiệu chỉnh, không lấy 0.363 của benchmark bên ngoài làm ngưỡng dự án. Nếu FMR mục tiêu chưa đạt, không tự nới ngưỡng chỉ để demo nhận ra người.
FMR là tỷ lệ chấp nhận nhầm người khác; FNMR là tỷ lệ từ chối nhầm đúng người. APCER đếm mẫu tấn công bị chấp nhận như người thật; BPCER đếm người thật bị PAD từ chối. PAD là kiểm tra tấn công trình diện như đưa ảnh/màn hình trước camera, khác với so khớp danh tính. P95 là mức thời gian mà ít nhất 95% mẫu đo không vượt quá. Luôn công bố mẫu số và điều kiện đo cùng các tỷ lệ này.
## Đo hiệu năng và cấu hình máy chủ
Máy local quan sát là i7-1255U/12 logical processor, khoảng 7,69 GiB RAM. Ghi OS, Python/OpenCV/NumPy, model hash, input dimensions, số thread, số lượt warm-up và số lượt đo. Đo riêng cold load, detector, alignment, embedding, matching, PAD, API overhead và toàn luồng. P95 dùng nearest-rank trên thời gian từng request; warm-up không tính vào mẫu, nhưng vẫn báo cold start riêng.
Runtime smoke với ảnh trống/tensor synthetic chỉ chứng minh model load/chạy, shape và thời gian tính toán sơ bộ. Không phải dataset người thật, không có FMR/FNMR/PAD và không dùng để ký cấu hình VPS đủ tải. Face có input thật và PAD cần benchmark lại trên VPS đã mua/trial trước khi chốt mục 4 tuần 1.
Kịch bản staging cần 20 client trong 10 phút sau warm-up, tối thiểu ba nhóm: CRUD có auth, RFID hợp lệ/retry và Face có dữ liệu được phép. Ghi throughput, error rate, P50/P95, CPU/RAM/queue; tách thời gian chờ và xử lý. Số đo server không thay thế round-trip từ Web/Android/ESP32. Kiểm tra invariant ledger sau các ca load có thanh toán ở tuần 5; tuần 1 chưa có Payment API để chạy ca đó.
## Phương án VPS 300 000 600 000 đồng mỗi tháng
Khuyến nghị ứng viên để thử: VPS Linux x86_64, 4 vCPU, khoảng 6 GB RAM và 50 GB SSD; Ubuntu LTS, CPU-only YuNet/SFace, PostgreSQL 17, backend và reverse proxy. Đây là cấu hình cần kiểm chứng, chưa phải cấu hình đã đo đạt. Nếu benchmark Face/PAD cần nhiều tài nguyên hơn, ưu tiên tách lịch benchmark, giảm concurrency hoặc giảm phạm vi Face thay vì ghi đã đạt trên máy yếu.

| Khoản | Mức tham chiếu / dự toán | Lưu ý |
| --- | --- | --- |
| VPS tham khảo Vietnix SSD Linux 3 | Trang chính thức niêm yết 370.000 đ/tháng, 4 CPU/6 GB/50 GB; gói 3 tháng hiển thị 355.200 đ/tháng, tổng 1.065.600 đ | Cần xác nhận lại gói/chu kỳ/VAT với checkout; không coi giá quy đổi tháng là tiền trả trước một tháng |
| Backup ngoài VPS | Dự phòng kế hoạch 50.000–80.000 đ/tháng | Chưa là báo giá dịch vụ; chọn kho độc lập sau khi biết dung lượng/khóa |
| Domain .com | Cloudflare công bố 11,17 USD/năm cho đăng ký/gia hạn tại ngày tra | Không chọn domain thật khi chưa kiểm khả dụng; không tự quy đổi USD bằng tỷ giá giả |
| Dự phòng thuế/biến động | Phần còn lại trong trần 600.000 đ/tháng | Tổng cuối tùy hóa đơn, tỷ giá và lựa chọn backup; cần nhóm xác nhận |


Nguồn giá: Vietnix VPS và Cloudflare domain prices, tra 02/11/2026. Không dùng giá khuyến mại nhiều năm để ngụy trang chi phí đồ án 8 tuần. Chưa mua VPS/domain bằng tài khoản người dùng và chưa xác nhận SLA/khả năng hỗ trợ của nhà cung cấp.
## Tách dev staging và production
Dev chạy trên máy phát triển. Trong ngân sách, một VPS có thể chứa hai Compose project staging và production với DB instance, volume, network, account và secret tách biệt; cùng máy vật lý vẫn có chung điểm lỗi và tranh chấp tài nguyên. Trước tuần 6 staging chạy chính; khi production mở pilot thì giảm/tắt workload staging nặng, không chạy load test trên production. Nếu không đáp ứng tài nguyên/độ tin cậy phải tách host hoặc điều chỉnh phạm vi đã được duyệt.
Reverse proxy công khai 80/443; SSH hạn chế theo địa chỉ/quyền. PostgreSQL và AI không publish port ra Internet. App Web cùng origin với API để giảm CORS/CSRF complexity; Android và ESP32 dùng HTTPS cùng API. Staging domain dạng staging.<domain>, production app.<domain>; đây là mẫu, chưa có hostname đã đăng ký. Không deploy config placeholder rồi ghi URL production đã hoạt động.
Chọn Node 24 LTS cho project và Docker image, không dùng Node 25 mặc định trên máy để kết luận đã chốt runtime. Secret mỗi môi trường và mỗi device riêng; AI chỉ có service token/khả năng đọc capture cần thiết, không có DATABASE_URL. Model/private storage volume theo version; lưu manifest cùng backup metadata.
## Backup RPO và RTO
Giữ mục tiêu kế hoạch RPO ≤24 giờ, RTO ≤4 giờ trước pilot. Dự kiến backup DB hằng ngày và backup private file/model manifest tương ứng; mã hóa, chuyển ngoài VPS, có retention và cảnh báo lỗi. RPO là mức dữ liệu có thể mất, RTO là thời gian phục hồi; chưa diễn tập thì chưa ghi đã đáp ứng.
Thử restore sang DB/volume tách biệt: khôi phục schema/data, kiểm account balance với sum(delta), tổng mỗi transaction, một SALE/intent, record/nguồn, file references, model hash và secret tương thích. Ghi thời gian từ bắt đầu xử lý đến service khỏe lại; khóa ghi trong cửa sổ backup hoặc dùng phương án snapshot/version phù hợp để DB và file không lệch. Không chạy restore đè lên production có người dùng.
# 6 Test plan ban đầu và quy tắc evidence
Nguồn ca F/P/A/N là PDF trang 16–17. Giữ 28 ID gốc để đối chiếu, bổ sung build/camera/thiết bị/restore theo lịch Web + Android. Test của prototype trong evidence không thay thế toàn bộ 28 ca hệ thống.
## Các lớp kiểm tra
Unit cho validation, tính tiền và transition; integration trên PostgreSQL thật cho unique/lock/rollback; contract cho Node/FastAPI/Flutter/firmware; end-to-end Web/Android; hardware test với board thật; AI đánh giá bằng dữ liệu consent và split độc lập. Mock hoặc payload giả chỉ chứng minh phần được mô phỏng, không chứng minh phần cứng hay chất lượng nhận dạng.
Mỗi lần chạy phải ghi ID, timestamp, source/model version, môi trường, input đã ẩn danh, expected, actual, trạng thái, request/event/intent/transaction ID và đường dẫn evidence. Chỉ PASS khi có actual đáp ứng expected; NOT RUN khi chưa chạy; BLOCKED kèm dependency. Không ghi PASS do đọc code hoặc chỉ nhìn một toast UI.
## 28 ca gốc cần chạy xuyên các tuần

| ID | Nội dung và kiểm tra bắt buộc | Mốc thực hiện | Trạng thái hệ thống |
| --- | --- | --- | --- |
| F01 | SV không đọc được ví/hồ sơ người khác | Tuần 2/4 | NOT RUN |
| F02 | UID ACTIVE không cấp cho hai SV | Tuần 2; SQL đã có kiểm chứng prototype | NOT RUN end-to-end |
| F03 | RFID đúng phiên/lớp, một attendance, ví không đổi | Tuần 2; prototype dùng event giả đã kiểm | NOT RUN phần cứng |
| F04 | RFID rồi Face cùng buổi không tạo hai record | Tuần 3 | NOT RUN |
| F05 | Ngoài roster hoặc phiên đóng bị từ chối | Tuần 2; prototype đã có test API/DB | NOT RUN end-to-end |
| F06 | Thẻ khóa bị từ chối | Tuần 2; prototype đã có test API/DB | NOT RUN end-to-end |
| F07 | Face revoked hoặc verification hết hạn không dùng lại | Tuần 3 | NOT RUN |
| F08 | Approval nạp 100.000 lặp chỉ có một TOPUP | Tuần 4 | NOT RUN |
| F09 | Ví 100.000 trả đơn 25.000 còn 75.000, entries cân bằng | Tuần 4/5 | NOT RUN |
| F10 | Face đạt nhưng SV chưa confirm app không chi tiền | Tuần 5 | NOT RUN |
| F11 | Ví 20.000 không trả được đơn 25.000 | Tuần 4 | NOT RUN |
| F12 | Client đổi amount/nguồn không thay được giá server | Tuần 5 | NOT RUN |
| F13 | Refund toàn bộ đúng SALE và đúng amount một lần | Tuần 4/5 | NOT RUN |
| F14 | Xe chỉ có một lượt chưa đóng | Tuần 3 | NOT RUN |
| F15 | Đúng SV nhưng sai xe/vé không được lấy xe | Tuần 3/5 | NOT RUN |
| F16 | Thu phí/đóng lượt/retry chỉ có một hiệu lực | Tuần 5 | NOT RUN |
| P01 | 20 confirm cùng intent với key/RFID/Face khác nhau: một SALE | Tuần 4/5 | NOT RUN |
| P02 | Ví 30.000, hai đơn 25.000 đồng thời: một thành công, còn 5.000 | Tuần 4 | NOT RUN |
| P03 | Cùng key khác payload bị 409; đổi key cùng nguồn không ghi nợ lại | Tuần 4 | NOT RUN |
| P04 | Lỗi giữa posting: rollback balance/ledger/intent/verify | Tuần 4 | NOT RUN |
| P05 | Commit rồi mất response/restart: tra đúng receipt cũ | Tuần 5 | NOT RUN |
| P06 | Replay verify sang intent/student/terminal khác bị chặn | Tuần 3/4 | NOT RUN |
| P07 | Nạp/refund retry và concurrency không double-post | Tuần 4 | NOT RUN |
| A01 | FMR/FNMR, số mẫu và điều kiện, threshold khóa | Tuần 3 | NOT RUN |
| A02 | APCER/BPCER cho ảnh in, màn hình, video và người thật | Tuần 3 | NOT RUN |
| A03 | AI timeout/multiple faces/version sai: không VERIFIED/chi tiền | Tuần 3 | NOT RUN |
| N01 | 20 client/10 phút, P50/P95/error/throughput, đối soát sau load | Tuần 5 | NOT RUN |
| N02 | Mất Wi-Fi, outbox replay, restore, đối soát | Tuần 4–6 | NOT RUN |


## Ca bổ sung bắt buộc cho tiêu chí tuần 1 và hai nền tảng

| ID | Kiểm tra | Bằng chứng cần lưu | Trạng thái ban đầu |
| --- | --- | --- | --- |
| W01 | Build Flutter Web release | Doctor, version, build log, index/assets, checksum | BLOCKED SDK chưa cài |
| W02 | Build Android APK thử nghiệm | Log, APK checksum; không gọi debug-signed là release production | BLOCKED SDK chưa cài |
| W03 | Camera Web: allow/deny, secure context, capture, pause/resume | Browser/OS, permission và ảnh/video giả lập hoặc ảnh có consent | NOT RUN |
| W04 | Camera Android trên điện thoại thật: allow/deny/lifecycle | Android version/device, log và evidence | NOT RUN |
| W05 | Board thật: đọc UID, HTTPS, LCD, lost ACK retry giữ event_id | Sơ đồ dây đã kiểm, serial/video, API/DB | NOT RUN |
| W06 | Model load/hash/runtime | Manifest và benchmark JSON; phân biệt synthetic với ảnh người thật | Xem biên bản kiểm chứng |
| W07 | Staging HTTPS và isolation cấu hình | DNS/TLS, port check, DB/secret/volume riêng | NOT RUN |
| W08 | Backup/restore và RPO/RTO | Backup ID, restore log, đối soát, stopwatch | NOT RUN |


## Điều kiện hoàn tất tuần 1
Nộp hồ sơ review và test plan chưa đủ để ký Đạt toàn tuần. Phải có hai build và thử RFID/camera thật, version/license đã kiểm, phương án máy chủ được đo/xác nhận và phân công/ngưỡng mục tiêu được nhóm/giảng viên đồng ý. Nếu thiếu, ghi Chưa đạt ở tiêu chí tương ứng và có hạn bổ sung; không bịa evidence để đóng mốc.
# 7 Biên bản kiểm chứng kỹ thuật và phần còn thiếu
Ngày 02/11/2026. Đây là ghi nhận những lệnh đã thực thi trong workspace, không là chữ ký nghiệm thu của giảng viên. Không ghi toàn bộ tuần 1 là Đạt.
## Kết quả đã chạy

| Hạng mục | Kết quả thực tế | Evidence và phạm vi |
| --- | --- | --- |
| Khảo sát upstream | Đọc 29 file, commit 6f600226e3f0f383897ee5d2d607733e5a80c84f | Manifest URL/hash nội bộ; không chạy app MongoDB upstream |
| TypeScript | Compile thành công bằng Node 24.22.1 và TypeScript 5.9.3 | Build trước bộ test; npm lockfile có phiên bản thực |
| PostgreSQL | PostgreSQL 17.9, cluster riêng trên 127.0.0.1:54329; đã tắt sau test | Không dùng hoặc sửa DB thật của người dùng |
| Integration RFID/SQL | 14 test PASS, 0 fail, gồm 20 scan song song, 20 retry cùng event, role device, revoked/outside/closed, rollback và ledger guard | evidence/postgres-integration.tap; payload giả, không có quét từ ESP32 vật lý |
| Runtime AI | 5 unit test PASS | evidence/ai-unit.txt; model checksum, blank reject, tensor finite và không authorize khi PAD thiếu |
| FastAPI HTTP | 4 check PASS: health 200, thiếu token 401, readiness/verify 503 khi PAD chưa cấu hình | evidence/ai-http-smoke.json; không phải Face/PAD thành công |
| Benchmark synthetic | 100 lượt sau 5 warm-up, OpenCV một thread | evidence/ai-runtime-benchmark.json; không có dữ liệu người thật |
| OpenAPI | OpenAPI 3.0.3, 22 operation, validator PASS | evidence/openapi-validation.json; validation schema không xác nhận implementation đầy đủ |
| Compose | config --quiet PASS | evidence/compose-config.json; chưa build image hoặc chạy stack Docker/VPS |
| UML/ERD | Source PlantUML và PNG/SVG được render | docs/diagrams; xem manifest/visual QA, không phải sơ đồ as-built |


## Số đo AI local thực tế

| Chỉ số | Kết quả |
| --- | --- |
| Máy và runtime | i7-1255U, 12 logical processor, khoảng 7,69 GiB RAM; Windows 11; Python 3.12.14 |
| OpenCV / NumPy | 4.12.0 / 2.2.6 |
| Cold model load | 511,248 ms |
| Detector ảnh trống 640×480 | P50 194,246 ms; P95 272,918 ms |
| Embedding tensor synthetic 112×112 | P50 210,744 ms; P95 289,465 ms |
| Process RSS sau benchmark | 98.250.752 byte, khoảng 93,70 MiB; không phải toàn bộ RAM VPS hay peak toàn hệ thống |
| Shape embedding quan sát | 1×128 |
| Accuracy, FMR/FNMR, APCER/BPCER | Chưa có số liệu; không suy ra từ benchmark tensor |


P95 của từng bước không được cộng tùy ý thành P95 toàn pipeline. Chưa đo alignment trên mặt thật, PAD, hàng đợi, API full Face hay 20 client trong 10 phút. Không dùng bảng này để kết luận đạt Face dưới 3 giây trên VPS hoặc đã xác minh đúng sinh viên.
## Phiên bản và license đã kiểm

| Thành phần | Phiên bản/định danh và trạng thái |
| --- | --- |
| PostgreSQL | 17.9 đã chạy test local; staging image tag/digest chưa khóa sau build |
| Node / Express / pg / TypeScript | Node 24.22.1 dùng kiểm chứng; Express 5.3.0; pg 8.23.1; TypeScript 5.9.3 trong package lock |
| Python / OpenCV / FastAPI / Uvicorn | Python 3.12.14; opencv-python-headless 4.12.0.88; FastAPI 0.162.0; Uvicorn 0.54.0; requirements.lock.txt ghi transitive deps |
| YuNet | face_detection_yunet_2023mar.onnx, SHA-256 8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4; LICENSE thư mục model là MIT |
| SFace | face_recognition_sface_2021dec.onnx, SHA-256 0ba9fbfa01b5270c96627c4ef784da859931e02f04419c829e83484087c34e79; LICENSE thư mục model là Apache 2.0 |
| Model upstream | OpenCV Zoo commit 48b10fa505aeb51fbd127fc60a5c660040e823b7; hash download khớp Git LFS pointer |
| Flutter/camera | Template camera 0.12.2 theo pubspec chính thức, yêu cầu Dart ^3.12/Flutter >=3.44; chưa có SDK, lockfile hoặc build đã chạy |
| Arduino / board / libs | Chưa chốt bằng compile/thiết bị thật; không tự ghi version đã đạt |
| PAD / similarity threshold | PAD chưa chọn; threshold chưa hiệu chỉnh; Face không cấp VERIFIED |


Npm hệ thống lúc cài dependency gọi Node 25.6.0 và phát engine warning. Các bước build/test sau đó dùng đường dẫn Node 24.22.1 rõ ràng, phù hợp engines của project. Không thay Node/PATH toàn máy và không bỏ qua sự khác biệt này trong evidence.
## Phần chưa chạy và điều kiện đóng

| Việc còn thiếu | Phụ thuộc | Chủ trì đề xuất |
| --- | --- | --- |
| Hai build Flutter, camera Web/Android | Cài SDK và Android tools, chấp thuận license sau khi đọc, kết nối điện thoại thật | thành viên 2, bạn review |
| Compile/flash RFID và thử end-to-end thật | Board đúng model, dây/điện áp, credential riêng, backend HTTPS và UID thẻ được đăng ký | thành viên 2, bạn quan sát DB |
| Matching/PAD accuracy và threshold | Người tham gia có đồng ý, data split theo buổi, PAD model/license và test attacks | Bạn, thành viên 2 review |
| Cấu hình VPS chốt theo tải | Mua/trial gói trong ngân sách, domain, deploy, benchmark thực trên máy thuê | Cả hai |
| RPO/RTO và backup ngoài máy chủ | Có stack staging, kho backup, khóa và diễn tập restore | Bạn, thành viên 2 đối chiếu |
| Xác nhận lịch, owner và gate tuần 1 | Hai người và giảng viên review hồ sơ | Cả hai |


## Kết luận dùng để trình bày với giảng viên
Nhóm đã có bộ thiết kế PostgreSQL, API, UML/ERD, phân công và test plan bản đầu, cùng prototype và evidence chạy được cho một phần backend/DB và AI runtime. Nhóm chưa có đủ bằng chứng của tiêu chí 3 và 4 để ghi đạt toàn tuần: camera/Flutter/hardware thật và máy chủ thuê vẫn cần thực hiện. Chất lượng Face/PAD chưa được chứng minh. Hạn bổ sung đề xuất là cuối tuần 1 theo lịch đã thống nhất; nếu bắt đầu 02/11 thì chốt ngày 08/11/2026, cần nhóm xác nhận lịch thực tế.
# 8 Danh mục sơ đồ và hình thiết kế
Bộ source có đủ tám sơ đồ dạng PlantUML có thể sửa và SVG có thể phóng to. Ba hình sau được đặt trong báo cáo để đọc nhanh. Các sơ đồ mô tả kiến trúc mục tiêu; biên bản ở phần 7 ghi phạm vi prototype đã kiểm chứng.

| File trong docs/diagrams | Nội dung |
| --- | --- |
| 01-architecture.svg / .puml | Kiến trúc toàn hệ thống và module Face |
| 02-erd-identity.svg / .puml | ERD định danh và điểm danh |
| 03-erd-ledger.svg / .puml | ERD ví và giao dịch |
| 04-use-case.svg / .puml | Use Case nghiệp vụ và vai trò |
| 05-sequence-attendance.svg / .puml | Sequence điểm danh |
| 06-sequence-payment.svg / .puml | Sequence thanh toán |
| 07-activity-parking.svg / .puml | Activity gửi xe |
| 08-class.svg / .puml | Class và trách nhiệm service |


SQL đầy đủ nằm trong database/001_design_baseline.sql và 002_seal_posted_ledger.sql. API mục tiêu nằm trong docs/api/target-api.openapi.json. ERD là hình rút gọn; FK, unique, check và trigger trong SQL là căn cứ kiểm tra chi tiết.
## Kiến trúc toàn hệ thống và module Face

Hình 01   Kiến trúc toàn hệ thống và module Face   Bản thiết kế mục tiêu
## ERD ví và giao dịch

Hình 03   ERD ví và giao dịch   Bản thiết kế mục tiêu
## Use Case nghiệp vụ và vai trò

Hình 04   Use Case nghiệp vụ và vai trò   Bản thiết kế mục tiêu