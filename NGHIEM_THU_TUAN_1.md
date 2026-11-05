# Chốt công việc trọng tâm tuần 1

Ngày đối chiếu 05/11/2026. Nguồn chính: Ke_hoach_AIoT_8_tuan_Web_Android_Production_v2.docx, mục Tuần 1 và bảng năm tiêu chí. Đây là checklist hỗ trợ nhóm/giảng viên review; không tự đánh dấu Đạt hoặc ký thay người nghiệm thu.

Cập nhật trong phiên: người dùng đã cho cài SDK và chấp thuận Android SDK License; hiện không có thiết bị thật để thử. Người dùng chọn production thuê VPS4vCPU/8GB/80–100GB và staging tạm trên máy nhóm, chưa mua. Xem docs/PHUONG_AN_TRIEN_KHAI.md; lựa chọn này thay ứng viên cấu hình ban đầu bên dưới. Trạng thái build mới xem docs/evidence/flutter-build.json khi có.

## Ma trận nghiệm thu

| Tiêu chí nguồn | Sản phẩm hiện có | Trạng thái và điều kiện đóng |
| --- | --- | --- |
| 1 Phạm vi, owner, lịch 8 tuần, điều kiện thiếu, Web và APK | README, thiết kế tham khảo, kế hoạch bên dưới; nguồn kế thừa TapCard rõ từng file | Hồ sơ đã chuẩn bị; hai người cần chốt lịch và owner |
| 2 Kiến trúc/ERD chung student, wallet, ledger, canteen, parking và chống trùng | docs/KIEN_TRUC.md, SQL, 14 test PostgreSQL mới; User/Card/Face cùng student_id | Có thiết kế/prototype để review; cần nhóm xác nhận nghiệp vụ, không phải mọi module đã code |
| 3 Bản thử RFID/camera, hai build Flutter, version/model/license/thiết bị | SDK đã cài, analyze/widget test/Web release đạt; firmware, model/hash/license; xem trạng thái APK mới trong evidence | CHƯA ĐỦ: cần hoàn tất APK và camera/board thật, version Arduino và compatibility |
| 4 Cấu hình máy chủ theo thử AI, chi phí/domain/quyền/isolation | Blueprint deploy, mục tiêu VPS và biểu chốt quyết định | CHƯA ĐỦ: chưa thuê/trial, domain chưa chọn, chưa đo VPS; benchmark local không thay thế |
| 5 Mẫu AI, mục tiêu, tải20client/P95/backup, test plan | Protocol/metric và kịch bản dưới đây; 28 ca kế thừa ở thiết kế tham khảo | Đã lập đề xuất; cần nhóm/GV chốt target. Đo accuracy/PAD thực hiện tuần3; test tải đầy đủ tuần5 và restore trước pilot |

## Việc trọng tâm theo thứ tự phụ thuộc

1. **Cả hai review scope/thiết kế, 4 giờ mỗi người.** Đọc ma trận kế thừa; xác nhận giữ UI/Provider/phần cứng dùng được, thay DB/transaction và contract. Chốt tiền demo, Face1:1, Web/APK, không phát hành Play. Evidence: biên bản ghi phiên bản, quyết định và vấn đề còn mở.
2. **Bạn kiểm SQL/backend 5 giờ, thành viên 2 review 2 giờ.** Chạy test-postgres, đọc các test retry/concurrency/rollback/ledger guard. Evidence mới phải còn source và TAP, không chỉ ảnh báo cáo cũ. Prototype chưa có Auth người dùng/Payment, không demo như đã hoàn tất các phần này.
3. **thành viên 2 cài SDK/build/camera 6 giờ, bạn review 2 giờ.** Cài SDK đáp ứng constraint, doctor, analyze, build Web/APK. Test allow/deny camera, capture, app pause/resume và HTTPS/localhost, Android máy thật. Evidence: version/doctor/log build/APK hash/device OS/video. Nếu quá giờ, ghi blocker và hạn, không tạo log giả.
4. **thành viên 2 thử IoT 4 giờ, bạn đối chiếu DB 2 giờ.** Chốt model board/reader/LCD, điện áp/dây/core/library; compile; provision DB dev + CA/token; RFID→HTTPS→SQL→LCD. Thử lost ACK giữ event_id, thẻ khóa, ngoài lớp, phiên đóng. Evidence gồm compile log, hình dây, video và truy vấn DB đã ẩn dữ liệu.
5. **Bạn AI/runtime 3 giờ, thành viên 2 VPS/dự toán 2 giờ.** Kiểm model hash/license, đọc kết quả local mới; chọn trial/cấu hình theo workload thực, ghi quote và domain có thể mua. Chưa mua thì giữ “chưa chốt”.
6. **Bạn tổng hợp 4 giờ, thành viên 2 evidence/review 2 giờ.** Tổng 20 giờ mỗi người, gồm review nêu trên. Chốt lịch 8 tuần, target, owner vận hành và trạng thái từng tiêu chí với GV. Không lấy số giờ assistant làm thành timesheet của nhóm.

Ngày đầu 8 tuần chưa được nhóm xác nhận. Nếu giữ dự thảo 02/11–27/12 thì tuần1 kết thúc 08/11/2026; đây chỉ là mốc đề xuất. Ngày 05–08/11 không tự suy ra mỗi người còn 20 giờ rảnh: nhóm cần đối chiếu số giờ đã dùng. Nếu thiếu SDK/hardware/VPS trước hạn, nộp hồ sơ với mục chưa đạt và hạn bổ sung được GV đồng ý.

| Tuần | Trọng tâm và phụ thuộc | Nhân lực |
| --- | --- | --- |
| 1 | Chốt thiết kế/khả thi và evidence | 20 giờ/người |
| 2 | Port auth/providers/SQL, RFID thật, staging HTTPS và CI | 20 giờ/người |
| 3 | Face1:1/consent/PAD/camera và parking cơ bản | 20 giờ/người |
| 4 | Wallet/ledger/posting, concurrency, backup/restore | 20 giờ/người |
| 5 | Canteen/parking payment, E2E, tải và release candidate | 20 giờ/người |
| 6 | Production Web/APK ký, alert/rollback/restore | 20 giờ/người |
| 7 | UAT5–10 người3–5ngày và sửa lỗi | 20 giờ/người |
| 8 | Hồi quy, báo cáo/demo/bàn giao | 20 giờ/người |

## AI và kế hoạch đo để chốt tiêu chí 5

Đề xuất pilot20–30 người tự nguyện; mỗi người3 ảnh enrollment,5 capture development và5 capture test khác buổi. Nếu được, tách người chọn ngưỡng và người test; không chia frame kề nhau sang hai tập. Ghi số mẫu thực, manifest ẩn danh, consent/retention/key owner; chưa thu dataset thật trong phiên này.

Đề xuất giảng viên chốt FMR≤1% (nhầm người khác), FNMR≤10% (từ chối đúng người), PAD APCER≤5% cho từng loại attack đã thử và BPCER≤10% cho người thật. Đây là target pilot tiền demo, chưa đo/duyệt, không là chuẩn thanh toán thật. PAD thử ảnh in/màn hình/video; chưa chọn model PAD, không giả PASS. Threshold chọn development, khóa trước held-out test; không dùng mặc định0.363 từ benchmark ngoài làm kết quả dự án.

Tải staging:20 client/10phút, warm-up riêng, các nhóm CRUD/RFID/Face có auth/data hợp lệ, ghi mỗi request duration/status/request_id, P50/P95 nearest-rank, throughput/error và CPU/RAM. Target kế hoạch: CRUD P95<500ms, RFID<2s, Face<3s phía server; báo riêng round-trip thiết bị. 20 retry đồng thời trong integration test không là kịch bản tải10phút. Không cộng component P95 thành P95 toàn luồng.

Backup target RPO≤24h/RTO≤4h trước pilot: backup DB/private artifacts mã hóa ngoài VPS, owner bạn, thành viên 2 kiểm chéo. Restore DB riêng, đo thời gian, đối soát sum(delta), cache balance, source/intent uniqueness và file/model hash. Tuần1 chốt mục tiêu/cách đo; chưa có phục hồi thực để báo đạt.

## Phiếu chốt máy chủ và chi phí

Ngân sách nhóm xác nhận300.000–600.000đ/tháng. Ứng viên cần thử là Linux x86_64 khoảng4vCPU/6GB/50GB SSD, CPU-only; chưa kết luận đủ tải. Dự toán phân bổ VPS≤450.000, backup ngoài máy≤80.000, còn≤70.000 cho domain phân bổ/tháng và phát sinh, tổng trần600.000. Các khoản này là **trần kế hoạch**, không là báo giá hiện tại hoặc bảo đảm mua được. Mốc300.000 có thể cần giảm cấu hình/phạm vi sau đo.

Trước khi ký tiêu chí4, điền: nhà cung cấp/gói/cấu hình thật; giá/thuế/chu kỳ và tổng tiền trả trước; URL quote/ngày; domain khả dụng/giá năm; owner tài khoản/MFA; hostname staging/prod; DB/volume/secret/role tách; số đo workload AI trên VPS. Không dùng giá cũ trong báo cáo02/11 thay quote mới. Không yêu cầu password/token trong biên bản.

## Test case tuần 1 cần lưu actual

| ID | Expected | Evidence hiện có hoặc còn thiếu |
| --- | --- | --- |
| W01 | TS check,14 integration test đạt trên PG17 | docs/evidence/postgres-integration.tap mới |
| W02 | Một attendance/session/student, retry cùng ACK, lỗi rollback toàn bộ | Test giả lập HTTP/DB, không phải board |
| W03 | Model đúng hash, blank reject, tensor finite; PAD thiếu không VERIFIED | AI tests/HTTP/benchmark mới khi chạy xong |
| W04 | Web release và APK debug build thành công | SDK/analyze/widget/Web đạt; APK xem docs/evidence/flutter-build.json |
| W05 | Camera allow/deny/capture/lifecycle cả2nền tảng | NOT RUN |
| W06 | Board quét thẻ thật/TLS/LCD, lostACK không trùng | NOT RUN |
| W07 | VPS cấu hình/giá/domain/isolation có bằng chứng | NOT RUN |
| W08 | Dataset protocol/target/P95/RPO/RTO được nhóm/GV chốt | Đề xuất, chờ xác nhận |

Mỗi ca ghi người chạy, thời gian, source/model version, môi trường, input ẩn danh, expected/actual, PASS/FAIL/NOT RUN và file evidence. 28 ca F/P/A/N trong bản tham khảo vẫn là kế hoạch các tuần sau, không đánh PASS do có prototype. Kết luận tuần để trống chờ GV; không ghi “đạt toàn bộ” khi W04–W07 chưa có bằng chứng.
