# Phương án triển khai đã thống nhất về hướng thực hiện

Cập nhật05/11/2026: người dùng chọn **production thuê VPS, staging dùng tạm máy nhóm** để giữ ngân sách ban đầu300.000–600.000đ/tháng. Chưa mua VPS/tên miền. Đây là quyết định hướng triển khai, chưa phải máy chủ đã được cấp và benchmark đạt.

| Môi trường | Cấu hình mục tiêu | Vai trò và giới hạn |
| --- | --- | --- |
| Production thuê VPS | 4vCPU,8GB RAM,80–100GB SSD/NVMe,Ubuntu24.04LTS | Reverse proxy, API, PostgreSQL, AI service bằng Docker Compose; cần quote và benchmark đúng gói trước chốt |
| Staging máy nhóm | Mục tiêu2vCPU/4GB RAM,40–50GB lưu trữ theo khả năng máy | CI/integration, camera HTTPS, restore; không coi tài nguyên đã cấp. Máy hiện8GB RAM, không chạy build nặng/load/restore đồng thời |

Staging không còn là khoản thuê VPS thứ hai. Máy nhóm cần đủ dung lượng và Docker engine hoạt động; dung lượng trên bảng là mục tiêu chứ không tạo volume rỗng50GB trong phiên này. Tách DB/volume/secret/role với production, không dùng dữ liệu Face thật khi chưa có đồng ý/kiểm soát. Tắt staging khi không dùng, không cam kết uptime hay xem độ trễ staging là độ trễ production.

## Đối chiếu ngân sách

Nguồn chính thức tra05/11: https://vietnix.vn/vps-ssd/. Gói tham khảo4vCPU/8GB/**50GB** là410.000đ/tháng hoặc393.600đ/tháng theo chu kỳ3tháng, trả trước1.180.800đ. Gói này **chưa đạt80–100GB**; cần quote nâng disk hoặc chọn nhà cung cấp/gói khác. Không mặc định410.000 là giá đúng cấu hình người dùng yêu cầu. Thuế/chu kỳ theo checkout cần xác nhận.

Phân bổ đề xuất trong trần600.000: VPS tối đa450.000; backup ngoài VPS dự phòng50.000–80.000; phần còn lại cho domain phân bổ/tháng và phát sinh. Đây là trần kế hoạch, không bảo đảm tìm được mọi gói. Nếu quote4vCPU/8GB/80–100GB vượt trần, trình nhóm quyết định đổi gói/tăng ngân sách, không âm thầm giảm spec.

Domain .com tham khảo11,17USD/năm tại https://pricing.registrar.cloudflare.com/; chưa chọn tên/kiểm khả dụng, chưa tự quy đổi tỷ giá/thuế. Backup dự phòng chưa là báo giá. Production một host vẫn là điểm lỗi đơn, chưa có HA dù staging tách máy.

## HTTPS staging và cách vận hành

Web localhost có thể thử quyền camera trong secure context, nhưng không phải URL staging HTTPS công khai. Nếu Web/Android truy cập staging từ thiết bị/mạng khác, cần hostname/TLS và đường kết nối đã thử (công khai có kiểm soát hoặc tunnel được nhóm cho phép), cùng quyền truy cập/secret riêng. Chưa dựng tunnel/public URL hoặc dùng một certificate tự ký rồi khẳng định HTTPS máy thật đã đạt.

Production có Caddy bind80/443; PostgreSQL/AI chỉ private network. Staging máy nhóm dùng port/domain cấu hình riêng, không exposeDB/AI; CI job không đưa production secret vào máy nhóm. Backup mã hóa ngoài production; restore vào DB riêng, đo thời gian và đối soát. Staging nhỏ hơn có thể phục hồi chậm hơn production; phải ghi đúng môi trường khi báo RTO.

Compose hiện là blueprint mỗi lần chạy một môi trường, có AI container private. Chưa build image/deploy/monitoring/backup scheduler/resource limit/posting role đầy đủ. AI vẫn503 khi thiếu PAD; RFID không chờ readiness của Face. Trước mở pilot phải hoàn thiện các phần này và có người vận hành.

## Bằng chứng đóng tiêu chí4 tuần1

Quote có ngày/gói/cấu hình/chu kỳ/thuế/tổng tiền trả trước; owner thanh toán/MFA/quản trị; domain/hostname đã chốt; CPU/RAM/disk thực; model/hash/license và benchmark VPS đúng workload; kế hoạch port/privateDB/AI, staging/backup; quyết định ngân sách. Chưa có các mục này thì tiêu chí4 chưa đủ để ghi Đạt.
