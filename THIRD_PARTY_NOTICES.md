# Nguồn code kế thừa TapCard

Smart Campus dùng thêm font Roboto regular/bold được lấy từ material_fonts của Flutter SDK đang cài. License đi kèm được giữ nguyên tại `flutter/app/assets/fonts/LICENSE.txt`; fonts được bundle local để Web không phải tải font từ CDN.

Repository: https://github.com/ndmanh0612/tapcard-iotproject

Commit kiểm tra ngày 05/11/2026: 6f600226e3f0f383897ee5d2d607733e5a80c84f.

Hai file kế thừa từ nguồn trên, chỉ chuyển withOpacity sang withAlpha với alpha tương đương để tránh API deprecated trên Flutter mới:

- flutter/lib/core/widgets/modern_button.dart → flutter/template/lib/core/widgets/modern_button.dart
- flutter/lib/core/widgets/modern_textfield.dart → flutter/template/lib/core/widgets/modern_textfield.dart

ModernButton đã được gọi trong màn hình camera mới. ModernTextField được giữ làm component cho form tiếp theo, chưa tích hợp vào màn hình đăng nhập. Trạng thái analyze/build mới xem docs/evidence/flutter-build.json khi có; không suy ra từ việc có source. Manifest nguồn giữ URL và SHA-256 gốc: docs/evidence/tapcard-source.json.

express/package.json của upstream khai báo GPL-3.0-only và metadata tác giả/repository trỏ tới s-m-quadri/taptag. Cây file khảo sát không có LICENSE ở root. Đây là thông tin nguồn quan sát được, chưa xác nhận license áp dụng cho toàn repo hoặc quyền sở hữu của từng file Flutter. Giữ nguyên attribution và kiểm tra notice/quyền phân phối với người duy trì trước khi công bố bản phân phối. Không tự gán MIT cho code kế thừa.

Backend PostgreSQL, SQL, camera spike và phần truyền HTTPS/event của firmware là phần viết mới trong lần xây lại. Sơ đồ chân và luồng đọc MFRC522/LCD được đối chiếu với firmware TapCard; không tuyên bố toàn bộ dự án tự viết nếu dùng các component nêu trên.

Model YuNet/SFace có license và manifest riêng trong docs/licenses và models/manifest.json sau khi fetch. License weights không được suy ra từ license thư viện OpenCV.
