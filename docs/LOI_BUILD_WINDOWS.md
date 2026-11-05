# Lỗi Java loopback khi build APK trên máy này

## Hiện tượng và bằng chứng

Lần build APK đầu với Flutter3.47.9,Java Microsoft21.0.1,Gradle9.3.1 trên Windows thất bại trước khi có APK. gradle-stacktrace.txt ghi `Unable to establish loopback connection`, bên dưới là `UnixDomainSockets.connect0` với `Invalid argument: connect` khi Java mở NIO Selector cho giao tiếp Gradle.

Đây là lỗi môi trường build đã tái hiện độc lập bằng tools/SelectorProbe.java, không phải bằng chứng camera Dart hoặc SQL sai. Chưa đủ thông tin quy lỗi cho firewall hay mọi máy Windows.

## Cách xác định nguyên nhân

Probe chỉ mở Selector, không có app Android. Java mặc định lỗi; đổi java.io.tmpdir sang thư mục dự án vẫn lỗi; ép preferIPv4Stack cũng lỗi. Chỉ định `jdk.net.unixdomain.tmpdir` vào source/.work/jtmp thì probe PASS. Các log java-selector-default.txt, java-selector-short-temp.txt, java-selector-ipv4.txt và java-selector-unix-temp.txt nằm trong docs/evidence.

Source JDK đã cài (lib/src.zip, PipeImpl.java/UnixDomainSockets.java) cho thấy Selector sử dụng kênh Unix-domain ở nhánh này. Kết quả đủ để chọn cấu hình temp Unix-domain riêng làm cách khắc phục trên máy đang kiểm; chưa chứng minh nguyên nhân sâu bên trong đường dẫn/môi trường Windows áp dụng cho mọi trường hợp.

## Cách chạy lại

Từ source chạy `./tools/verify-flutter.ps1 -Stage apk`. Script dùng SDK/cache dự án và JAVA_TOOL_OPTIONS trỏ jdk.net.unixdomain.tmpdir vào .work/jtmp, khôi phục biến môi trường khi xong. Không ghi cấu hình toàn máy, không tắt firewall, không sửa source Gradle/JDK hoặc bypass TLS. Giữ log lần lỗi đầu và log lần chạy mới; chỉ ghi APK PASS khi file APK thực có, lệnh exit0 và checksum được lưu.

Tham khảo thuộc tính được hỗ trợ: https://docs.oracle.com/en/java/javase/24/docs/api/java.base/java/net/doc-files/net-properties.html. Bằng chứng quyết định trên máy này là probe và source JDK21 cục bộ, không suy ra chỉ từ bài viết ngoài.
