# Kịch bản báo cáo tuần 1 trong 8 đến 10 phút

Đây là nội dung trình bày theo evidence, không phải biên bản giảng viên đã xác nhận. Ngày bắt đầu 8 tuần và hạn báo cáo chính thức chờ nhóm chốt.

1. **Phạm vi, 1 phút.** “Nhóm em làm hệ thống thẻ sinh viên đa năng với Web và APK Android, dùng chung định danh cho RFID và Face 1:1. Các nghiệp vụ gồm điểm danh, ví tiền mô phỏng, căn tin và gửi xe. Tuần 1 tập trung thiết kế và chứng minh khả năng thực hiện.”
2. **Kế thừa, 1 phút.** Mở docs/KE_THUA_TAPCARD.md. Nêu commit và 46 file khảo sát. Hai widget được dùng lại, ModernButton đã gọi trong camera. UI/Provider còn lại chỉ là ứng viên chuyển đổi; Mongoose và giao dịch phải đổi sang PostgreSQL. Nêu nguồn trong THIRD_PARTY_NOTICES.md, không nói toàn bộ là tự viết hoặc đã port xong app cũ.
3. **Thiết kế, 2 phút.** Mở docs/KIEN_TRUC.md và database/001.sql. Chỉ student_id chung, attendance UNIQUE(session,student), event PK(device,event), payment source FK/unique và ledger cân bằng/bất biến. Giải thích AI không có quyền sửa ví; nhận diện không là sự đồng ý chi tiền.
4. **Demo backend, 2 phút.** Từ source chạy `.\tools\demo-week1.ps1` với Node24 và PostgreSQL17. Script tạo cluster/DB demo riêng loopback54330, không TRUNCATE dữ liệu cũ và tự tắt khi xong. Mở docs/evidence/demo-backend.json: 6 bước PASS, một attendance dù gửi lại/20 lượt giả lập, thẻ khóa/phiên đóng bị chặn, ledger không có giao dịch. Nói rõ đây là HTTP giả lập thiết bị, chưa là quét ESP32 vật lý.
5. **AI và build, 1 phút.** Mở model manifest, AI test/HTTP và benchmark. Chỉ runtime synthetic; không có accuracy/PAD/Face VERIFIED. Build Web/APK chỉ trình bày khi có log exit0 và file artifact/hash. Có build chưa chứng minh camera máy thật. Kiểm trạng thái mới trong báo cáo và evidence, không dùng số cũ làm kết quả mới.
6. **Kế hoạch và phần thiếu, 1–2 phút.** Nêu nhóm2người,20giờ/người/tuần; chọn ngưỡng/target, mẫu dữ liệu có đồng ý, P95 và RPO/RTO. Trình dự toán/ứng viên máy chủ, chưa gọi là đã chốt khi chưa thuê/đo. Nêu thiếu thiết bị thật và xin thầy xác nhận hạn bổ sung, giữ ô nghiệm thu tương ứng chưa đạt.

Trước buổi báo cáo: chạy demo một lần; mở sẵn checklist, thiết kế, manifest và log; kiểm không lộ .env/token/UID thật/ảnh Face; giữ video demo giả lập dự phòng nếu nhóm tự quay được. Không dựng video giả quét thẻ hoặc ghi màn hình build thành công nếu build chưa chạy.

## Câu hỏi có thể gặp

| Câu hỏi | Câu trả lời có căn cứ |
| --- | --- |
| Vì sao không đổi mỗi connection string? | Controller dùng Mongoose và DTO dùng ObjectId/_id; PostgreSQL cần quan hệ/FK, SQL transaction và schema mới. |
| Vì sao 20 lần chỉ một điểm danh? | UNIQUE(session_id,student_id) và transaction; event retry còn được lưu status/body để trả ACK cũ. Test PostgreSQL thật đã chạy. |
| Có phải đã chống sao chép thẻ? | Chưa. UID RFID có giới hạn, HTTPS/token bảo vệ kênh và device, không biến UID thành thẻ chống sao chép. |
| Có phải Face đạt rồi? | Chưa. Model load/tensor chạy được, nhưng threshold/PAD và dữ liệu người thật chưa kiểm chứng; verify hiện từ chối an toàn. |
| Tại sao ledger cân bằng vẫn chưa đủ? | Còn kiểm quyền, nguồn/amount/account kind, khóa/cập nhật balance, consent chi tiền và reversal đúng; đó là service/test tuần4–5. |
| Hai build có phải hai app nghiệp vụ hoàn chỉnh? | Không. Đây là spike kiểm khả năng camera và build; màn hình/provider nghiệp vụ tiếp tục port tuần2. |
| Chốt VPS chưa? | Chỉ trả lời “đã” khi có cấu hình/quote/owner/domain và benchmark VPS. Nếu thiếu, trình phương án cùng hạn chốt. |
