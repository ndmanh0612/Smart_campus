# Bản đồ tệp Smart Campus

Danh sách tệp thêm/cập nhật hoặc bảo toàn để chuyển entry point trong phần triển khai Smart Campus. Đây là bản đồ bàn giao, không phải Git diff: workspace không có .git. Module responsibilities và kết quả kiểm ở [implementation-status.md](implementation-status.md). Prototype backend/app.ts, database/001.sql và firmware/rfid_spike được giữ nguyên; camera main cũ được giữ thành legacy/camera_spike.dart. Hai Modern widgets kế thừa chỉ format/tái sử dụng, giữ attribution.

## Backend / API / nghiệp vụ

- [backend/src/app.ts](../backend/src/app.ts)
- [backend/src/attendance.ts](../backend/src/attendance.ts)
- [backend/src/auth.ts](../backend/src/auth.ts)
- [backend/src/canteen.ts](../backend/src/canteen.ts)
- [backend/src/database.ts](../backend/src/database.ts)
- [backend/src/devices.ts](../backend/src/devices.ts)
- [backend/src/parking.ts](../backend/src/parking.ts)
- [backend/src/platform.ts](../backend/src/platform.ts)
- [backend/src/providers.ts](../backend/src/providers.ts)
- [backend/src/wallet.ts](../backend/src/wallet.ts)
- [backend/src/worker.ts](../backend/src/worker.ts)
- [backend/server.ts](../backend/server.ts)
- [backend/prototype-server.ts](../backend/prototype-server.ts)
- [backend/bootstrap.ts](../backend/bootstrap.ts)
- [backend/migrate.ts](../backend/migrate.ts)
- [backend/seed.ts](../backend/seed.ts)
- [backend/local.ts](../backend/local.ts)
- [backend/test/campus.test.ts](../backend/test/campus.test.ts)
- [backend/package.json](../backend/package.json)
- [backend/package-lock.json](../backend/package-lock.json)
- [backend/tsconfig.json](../backend/tsconfig.json)
- [backend/.env.example](../backend/.env.example)

## Database

- [database/migrations/002-campus.sql](../database/migrations/002-campus.sql)
- [database/migrations/003-operational-indexes.sql](../database/migrations/003-operational-indexes.sql)

## Flutter

- [flutter/app/lib/main.dart](../flutter/app/lib/main.dart)
- [flutter/app/lib/core/campus_api.dart](../flutter/app/lib/core/campus_api.dart)
- [flutter/app/lib/core/http_client.dart](../flutter/app/lib/core/http_client.dart)
- [flutter/app/lib/core/http_client_native.dart](../flutter/app/lib/core/http_client_native.dart)
- [flutter/app/lib/core/http_client_web.dart](../flutter/app/lib/core/http_client_web.dart)
- [flutter/app/lib/core/report_export.dart](../flutter/app/lib/core/report_export.dart)
- [flutter/app/lib/core/report_export_native.dart](../flutter/app/lib/core/report_export_native.dart)
- [flutter/app/lib/core/report_export_web.dart](../flutter/app/lib/core/report_export_web.dart)
- [flutter/app/lib/core/widgets/modern_button.dart](../flutter/app/lib/core/widgets/modern_button.dart)
- [flutter/app/lib/core/widgets/modern_textfield.dart](../flutter/app/lib/core/widgets/modern_textfield.dart)
- [flutter/app/lib/features/admin.dart](../flutter/app/lib/features/admin.dart)
- [flutter/app/lib/features/admin_tools.dart](../flutter/app/lib/features/admin_tools.dart)
- [flutter/app/lib/features/attendance.dart](../flutter/app/lib/features/attendance.dart)
- [flutter/app/lib/features/canteen.dart](../flutter/app/lib/features/canteen.dart)
- [flutter/app/lib/features/parking.dart](../flutter/app/lib/features/parking.dart)
- [flutter/app/lib/features/shared.dart](../flutter/app/lib/features/shared.dart)
- [flutter/app/lib/features/simulation.dart](../flutter/app/lib/features/simulation.dart)
- [flutter/app/lib/features/student.dart](../flutter/app/lib/features/student.dart)
- [flutter/app/lib/legacy/camera_spike.dart](../flutter/app/lib/legacy/camera_spike.dart)
- [flutter/app/test/campus_ui_test.dart](../flutter/app/test/campus_ui_test.dart)
- [flutter/app/test/widget_test.dart](../flutter/app/test/widget_test.dart)
- [flutter/app/pubspec.yaml](../flutter/app/pubspec.yaml)
- [flutter/app/pubspec.lock](../flutter/app/pubspec.lock)
- [flutter/app/android/gradle.properties](../flutter/app/android/gradle.properties)
- [flutter/app/android/app/src/main/AndroidManifest.xml](../flutter/app/android/app/src/main/AndroidManifest.xml)
- [flutter/app/android/app/src/debug/AndroidManifest.xml](../flutter/app/android/app/src/debug/AndroidManifest.xml)
- [flutter/app/web/index.html](../flutter/app/web/index.html)
- [flutter/app/web/manifest.json](../flutter/app/web/manifest.json)
- [flutter/app/assets/fonts/roboto-regular.ttf](../flutter/app/assets/fonts/roboto-regular.ttf)
- [flutter/app/assets/fonts/roboto-bold.ttf](../flutter/app/assets/fonts/roboto-bold.ttf)
- [flutter/app/assets/fonts/LICENSE.txt](../flutter/app/assets/fonts/LICENSE.txt)

## Firmware

- [firmware/smart_campus/smart_campus.ino](../firmware/smart_campus/smart_campus.ino)
- [firmware/smart_campus/secrets.example.h](../firmware/smart_campus/secrets.example.h)

## Vận hành / đóng gói

- [backend/Dockerfile](../backend/Dockerfile)
- [deploy/compose.yaml](../deploy/compose.yaml)
- [deploy/Caddyfile](../deploy/Caddyfile)
- [.dockerignore](../.dockerignore)
- [.gitignore](../.gitignore)
- [tools/test-campus.ps1](../tools/test-campus.ps1)
- [tools/start-campus.ps1](../tools/start-campus.ps1)
- [tools/verify-flutter.ps1](../tools/verify-flutter.ps1)
- [tools/install-arduino.py](../tools/install-arduino.py)
- [tools/compile-firmware.ps1](../tools/compile-firmware.ps1)
- [tools/init-compose.mjs](../tools/init-compose.mjs)
- [tools/format-campus.mjs](../tools/format-campus.mjs)
- [tools/smoke-compose.mjs](../tools/smoke-compose.mjs)
- [tools/verify-local-backup.ps1](../tools/verify-local-backup.ps1)
- [tools/verify-compose-backup.ps1](../tools/verify-compose-backup.ps1)
- [tools/package-campus.py](../tools/package-campus.py)

## Tài liệu

- [README.md](../README.md)
- [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md)
- [docs/legacy-analysis.md](legacy-analysis.md)
- [docs/requirements.md](requirements.md)
- [docs/architecture.md](architecture.md)
- [docs/business-flows.md](business-flows.md)
- [docs/database-design.md](database-design.md)
- [docs/api-contracts.md](api-contracts.md)
- [docs/api-routes.md](api-routes.md)
- [docs/implementation-plan.md](implementation-plan.md)
- [docs/camera-integration-guide.md](camera-integration-guide.md)
- [docs/SETUP_SMART_CAMPUS.md](SETUP_SMART_CAMPUS.md)
- [docs/RFID_SMART_CAMPUS.md](RFID_SMART_CAMPUS.md)
- [docs/implementation-status.md](implementation-status.md)
