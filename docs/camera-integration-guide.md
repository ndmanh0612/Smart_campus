# Hướng dẫn thay camera/AI demo bằng thiết bị thật

> Thiết kế đã được người dùng duyệt ngày 05/11/2026. Đây là tài liệu thiết kế gốc; xem [trạng thái triển khai](implementation-status.md) và [runbook](SETUP_SMART_CAMPUS.md) cho code, lệnh chạy và bằng chứng hiện hành.

05/11/2026 — thiết kế đã được duyệt. Chưa chọn camera/SDK, chưa có đo accuracy/liveness/OCR thật. Hướng dẫn này mô tả ranh giới và điều kiện tích hợp, không đưa ra API của nhà cung cấp chưa xác minh.

## 1. MVP chạy được mà không camera

- `CAMERA_PROVIDER=DEMO`, `FACE_PROVIDER=DEMO`, `LIVENESS_PROVIDER=DEMO`, `OCR_PROVIDER=DEMO`.
- Backend DemoCameraProvider trả capture metadata/evidenceRef synthetic, không cần webcam/file ảnh thật. DemoFaceProvider chọn fixture synthetic có permission; DemoLivenessProvider mô phỏng PASS/FAIL/UNKNOWN, không là chống giả mạo thật.
- DemoOCRProvider nhận text/scenario từ dashboard có quyền, trả raw/normalized/confidence/source DEMO và lưu observation. Confidence là số fixture, không kết quả đo model.
- SimulatedGateProvider mô phỏng dispatch/open/fail/unknown/passage bằng commandId bền; Payment MOCK không phát sinh tiền thật. RFID vẫn REAL từ MFRC522.
- App/Compose demo không cần gọi FastAPI hiện có, tải YuNet/SFace, chạy GPU hoặc xin camera permission. Không xóa các tệp/model/spike cũ; để riêng khỏi startup mặc định.

Schema và port methods dùng thống nhất tại [api-contracts.md](api-contracts.md), quy tắc nghiệp vụ tại [business-flows.md](business-flows.md). Không tạo một bộ DTO khác cho camera thật rồi sửa mọi service.

## 2. Phân biệt các tác vụ AI

| Bước | Làm gì | Không chứng minh điều gì |
| --- | --- | --- |
| Capture | Lấy frame từ nguồn đã xác thực, timestamp/cameraId, kiểm chất lượng đầu vào | Không xác định sinh viên |
| Face detection | Vị trí/số mặt trong frame | Không trả danh tính chỉ từ bounding box |
| Quality/alignment | Kiểm blur, sáng, pose, size và căn chỉnh | Chất lượng tốt không đồng nghĩa người thật |
| Liveness/PAD | Đánh giá dấu hiệu trình diễn ảnh/video/mask theo giải pháp chọn | DEMO PASS không bảo đảm chống spoof; PAD thật cũng phải đo |
| Embedding + recognition | Trích vector, so khớp với hồ sơ đã consent để xác định identity | Không dùng mọi threshold/model cho mọi camera và mọi người |
| OCR plate | Detect vùng plate, đọc text, chuẩn hóa và confidence | Plate text không là yếu tố định danh người hoặc bằng chứng đúng tuyệt đối |
| Domain validation | Lớp OPEN, roster, quyền xe, phiên/approval/balance | Model match không thay các bước kiểm này |

Recognition tương lai cần chốt 1:1 (verify người khai danh tính) hay 1:N (identify trong tập được phép). Attendance/parking simulator hiện trả studentId; adapter thật chỉ được trả studentId sau recognition được đánh giá. Không gọi detection là recognition, không triển khai vector DB/reranker/LLM chỉ vì có embedding. Scope lớp/bãi có thể nhỏ, chọn index sau khi đo quy mô/latency.

## 3. Ranh giới adapter tương lai

1. Viết CameraCaptureProvider cho thiết bị đã chọn dựa trên SDK/protocol/documentation thực. Xác thực nguồn, network isolation, retry/timeout/clock drift; không mở endpoint ingest public nhận studentId tùy ý.
2. FastAPI nội bộ nhận captureRef + request/context scope qua service credential hoặc mTLS; không có ví/DB write credential. Nếu backend gửi object reference, service chỉ được fetch từ kho allowlist, không URL arbitrary.
3. Face/Liveness/OCR adapters map output model thực sang schema version 1. `source=REAL` chỉ gán từ adapter cấu hình tin cậy và endpoint ingest nội bộ; reject source mismatch, identity ngoài scope hoặc evidence thiếu.
4. Thực thi inference ngoài DB transaction, deadline/cancellation và rate/backpressure rõ ràng. Kết quả có request/event ID, camera/device ID, capture time/server receive time, model/preprocess/threshold version, evidenceRef và status. Timeout → ERROR/UNKNOWN, không fallback sang DEMO hoặc match mặc định.
5. Backend kiểm event freshness, replay, device/classroom/lot binding, consent/active account, liveness/quality/confidence rồi tạo identity assertion như scan/demo. Các service parking/attendance/canteen tiếp tục giữ nguyên policy và transaction boundaries.
6. Với gate thật, adapter phải hỗ trợ command idempotency/fencing hoặc bổ sung gateway/controller thực thi đảm bảo tương đương. Nếu hardware không dedupe, không giả định retry an toàn; lệnh UNKNOWN phải tra trạng thái/nhân viên, không gửi OPEN lại mù.
7. Passage confirmation cần sensor/controller feedback hoặc staff có quyền và evidence. ACK motor/relay không có nghĩa xe đã qua. Gate fail-safe và kiểm an toàn vật lý phải thiết kế theo hardware thật sau khi chọn.

Thay adapter không có nghĩa không sửa gì khác: có thể cần provisioning, deployment/resource limits, secrets, evidence storage, metrics và UI quyền camera/consent. Mục tiêu là giữ **quy tắc domain và contract ổn định**, mọi thay đổi schema phải version/migrate.

## 4. Dữ liệu, consent và lưu trữ

- Trước thu dữ liệu: mục đích từng domain, người được truy cập, consent version, thời hạn lưu, quy trình revoke/xóa/backup; trường phê duyệt chính sách. Không dùng fixture DEMO làm consent cho người thật.
- Đăng ký biometric phải xác minh đúng chủ thể và chất lượng enrollment; mã hóa template/object với key version ngoài DB, least privilege, audit truy cập. Không log embedding/ảnh hoặc gửi lên hệ thống ngoài phạm vi đã đồng ý.
- Mặc định không giữ ảnh mặt gốc nếu chỉ cần template; evidence thật chỉ giữ tối thiểu có lý do/retention rõ. Private object store, URL ngắn hạn, quyền theo sinh viên/lớp/bãi; template không public bucket.
- Revoke chặn inference/identity assertion mới ngay; xóa template/object qua job có retry và erasedAt/evidence. Backup retention/restore phải tái áp dụng deletion tombstones để không làm dữ liệu đã xóa sống lại.
- Không xóa ledger/attendance lịch sử bằng cascade từ biometric profile. Lịch sử chỉ giữ phương thức/source/model version và bằng chứng tối thiểu được phép, không cần giữ vector mặt mãi.

## 5. Evaluation trước khi thay DEMO

| Phần | Dataset/test | Metric và quyết định |
| --- | --- | --- |
| Face detection/quality | Điều kiện sáng/tối/ngược sáng, kính/khẩu trang, pose, nhiều mặt/không mặt | Tỷ lệ capture hợp lệ, false/missed detections, latency; reject nhiều mặt hoặc chọn ROI theo quy tắc rõ |
| Face recognition | Người đồng ý; tập enrollment tách ngày/buổi capture khỏi validation/test; cả impostor/unknown | FAR/FRR cho verify; FPIR/FNIR/top-1 + unknown rejection cho identify; chọn threshold trên validation, giữ test để báo cuối |
| Liveness/PAD | Print, phone replay, video và kiểu tấn công phù hợp camera; thiết bị/môi trường test khác train | APCER/BPCER và phân tích failure; chỉ chọn metric/tuyên bố theo protocol đo, không nói “100% chống giả mạo” |
| OCR | Plate thực có phép, nhiều góc/sáng/mờ/che; test tách xe/ngày/camera khỏi train | Exact match plate sau normalization, CER, unreadable/review rate, false auto-accept và latency; raw OCR/correction phải giữ riêng |
| Hệ thống | Mạng yếu, CPU-only, nhiều frame, provider down, out-of-order/replay | p50/p95/p99 end-to-end, timeout/drop/queue lag, cost/event, phần trăm cần staff review; không lấy inference latency thay toàn flow |

Không leakage: không để cùng frame/near-duplicate/người/xe hoặc buổi chụp phân phối sai giữa train/validation/test theo mục tiêu đánh giá. Báo rõ tập evaluation và hạn chế theo nhóm/điều kiện; threshold/confidence demo không chuyển sang model thật. Version dataset/model/weights/preprocess/normalizer/threshold; pin checksum/license, đo trên máy đích trước cam kết không cần GPU.

## 6. Trình tự triển khai có kiểm soát

1. Chọn phần cứng và protocol/SDK đã kiểm documentation/version/license, power/network/mounting, mô hình dữ liệu và ngân sách đo được. Không bắt buộc ESP32-CAM/IP camera khi chưa chọn.
2. Adapter contract tests: đúng schema/source, unknown/null identity, low confidence, PAD fail, timeout, stale event, wrong device, multiple faces, duplicate event, unreadable/correction OCR. Dùng fixtures cho test, ghi rõ không là test thiết bị thật.
3. Thử capture/model thật trên môi trường đánh giá riêng có consent. Shadow mode chỉ so sánh dự đoán, chưa mở cổng/thu point/điểm danh tự động.
4. Chạy evaluation, hiệu chuẩn threshold, review failure cases; manual review ở low confidence. Xác minh p95, tài nguyên/cost và failure recovery.
5. Pilot giới hạn, rollback về manual verified workflow nếu model lỗi; không fallback DEMO trong production. Đăng ký source REAL/chứng thực service và bật adapter sau review.
6. Trước production: thay đủ providers thật, tắt simulator/mock, xác nhận config guard pass, harden TLS/credential/retention/monitoring, kiểm lại E2E domain/hardware. Production với provider DEMO/SIMULATOR/MOCK vẫn bị từ chối start.

## 7. Tiêu chí ra khỏi demo

- [ ] Camera/SDK/model/license đã chọn và kiểm thật; schema contract và source không thể bị client giả.
- [ ] Có consent/retention/xóa dữ liệu và quyền truy cập; không dùng dữ liệu thật chưa được phép.
- [ ] Dataset/evaluation/threshold được version; accuracy/PAD/OCR báo đúng metric và giới hạn, không suy từ smoke test.
- [ ] Network/inference timeout/replay/load/unknown và staff fallback đã thử; fail-closed.
- [ ] Gate vật lý có xác nhận passage/idempotency/fencing; wallet/stock/attendance invariants vẫn pass.
- [ ] Deployment/backup/monitoring/rollback và vận hành được duyệt.

Chưa đủ thông tin để chọn camera/SDK hoặc công bố độ chính xác hiện tại. Không có bước nào trong tài liệu này được tính là đã test hardware/model thật.
