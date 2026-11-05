# API đang thực thi

Sinh từ route declarations trong backend/src/app.ts của bản bàn giao; không liệt kê schema body tự suy đoán. Xem handler và domain service cho field bắt buộc, validation, state guards và response. Client nhận envelope data/requestId hoặc error.code/message/details/requestId. Các lệnh business thường trả 200; scan/Face accepted có thể trả 202; không coi chỉ HTTP 200 là thành công.

Các route user cần access token. null trong cột scope nghĩa mọi user đã đăng nhập; permission/resource scope còn được kiểm bên trong handler. Device/internal routes dùng auth riêng, không phải user role. Demo chỉ development/test và fixture có consent. UID không là quyền chi point; mọi thanh toán dương cần approval sinh viên.

| Method | Path | Role/scope ban đầu | Dòng app.ts |
| --- | --- | --- | --- |
| GET | /healthz | Theo handler/auth riêng | 46 |
| GET | /readyz | Theo handler/auth riêng | 47 |
| POST | /api/v1/auth/login | Theo handler/auth riêng | 68 |
| GET | /api/v1/auth/csrf | Theo handler/auth riêng | 69 |
| POST | /api/v1/auth/refresh | Theo handler/auth riêng | 70 |
| POST | /api/v1/internal/mock-payment-callbacks | Theo handler/auth riêng | 81 |
| GET | /api/v1/me | null | 134 |
| POST | /api/v1/auth/logout | null | 135 |
| PATCH | /api/v1/me | null | 136 |
| GET | /api/v1/me/notifications | null | 137 |
| POST | /api/v1/me/notifications/:id/read | null | 138 |
| GET | /api/v1/me/cards | ['STUDENT'] | 139 |
| POST | /api/v1/me/cards/:id/report-lost | ['STUDENT'] | 140 |
| POST | /api/v1/enrollment-contexts | ['ADMIN'] | 141 |
| POST | /api/v1/rfid-cards | ['ADMIN'] | 142 |
| POST | /api/v1/rfid-cards/:id/revoke | ['ADMIN'] | 157 |
| GET | /api/v1/me/vehicles | ['STUDENT'] | 158 |
| POST | /api/v1/me/vehicles | ['STUDENT'] | 159 |
| POST | /api/v1/vehicle-authorizations | ['ADMIN'] | 160 |
| GET | /api/v1/me/biometric-consents | ['STUDENT'] | 161 |
| GET | /api/v1/me/biometric-profiles | ['STUDENT'] | 162 |
| POST | /api/v1/me/biometric-consents | ['STUDENT'] | 163 |
| POST | /api/v1/me/biometric-consents/:id/revoke | ['STUDENT'] | 175 |
| POST | /api/v1/me/biometric-profiles/enrollment-requests | ['STUDENT'] | 176 |
| DELETE | /api/v1/me/biometric-profiles/:id | ['STUDENT'] | 177 |
| PUT | /api/v1/me/wallet-pin | ['STUDENT'] | 178 |
| GET | /api/v1/me/wallet | ['STUDENT'] | 192 |
| GET | /api/v1/me/wallet/ledger | ['STUDENT'] | 193 |
| GET | /api/v1/me/wallet/transactions | ['STUDENT'] | 194 |
| POST | /api/v1/me/topups | ['STUDENT'] | 195 |
| GET | /api/v1/me/topups | ['STUDENT'] | 196 |
| GET | /api/v1/me/topups/:id | ['STUDENT'] | 197 |
| GET | /api/v1/me/payment-requests | ['STUDENT'] | 198 |
| GET | /api/v1/me/payments/:id | ['STUDENT'] | 199 |
| POST | /api/v1/me/payments/:id/approvals | ['STUDENT'] | 200 |
| POST | /api/v1/refunds | ADMIN, CANTEEN_STAFF | 201 |
| GET | /api/v1/refunds | ADMIN, CANTEEN_STAFF | 202 |
| POST | /api/v1/admin/wallet-adjustments | ['ADMIN'] | 203 |
| GET | /api/v1/admin/wallet-reconciliation | ['ADMIN'] | 215 |
| GET | /api/v1/parking/lots | ADMIN, PARKING_STAFF | 216 |
| GET | /api/v1/parking/sessions | ADMIN, PARKING_STAFF | 217 |
| GET | /api/v1/parking/sessions/:id | ADMIN, PARKING_STAFF | 218 |
| GET | /api/v1/parking/gate-commands | ADMIN, PARKING_STAFF | 219 |
| POST | /api/v1/parking/entry-contexts | ADMIN, PARKING_STAFF | 220 |
| POST | /api/v1/parking/entries | ADMIN, PARKING_STAFF | 227 |
| POST | /api/v1/parking/sessions/:id/exit-contexts | ADMIN, PARKING_STAFF | 228 |
| POST | /api/v1/parking/sessions/:id/exit-quotes | ADMIN, PARKING_STAFF | 239 |
| POST | /api/v1/parking/sessions/:id/exit-authorizations | ADMIN, PARKING_STAFF | 240 |
| POST | /api/v1/parking/sessions/:id/exception-resolutions | ADMIN, PARKING_STAFF | 241 |
| POST | /api/v1/parking/gate-commands/:id/passage-confirmations | ADMIN, PARKING_STAFF | 242 |
| POST | /api/v1/parking/ocr-observations/:id/corrections | ADMIN, PARKING_STAFF | 243 |
| GET | /api/v1/me/parking-sessions | ['STUDENT'] | 244 |
| GET | /api/v1/canteen/products | null | 245 |
| GET | /api/v1/canteen/categories | null | 246 |
| POST | /api/v1/canteen/categories | ADMIN, CANTEEN_STAFF | 247 |
| POST | /api/v1/canteen/products | ADMIN, CANTEEN_STAFF | 248 |
| PATCH | /api/v1/canteen/products/:id | ADMIN, CANTEEN_STAFF | 249 |
| POST | /api/v1/canteen/inventory-adjustments | ADMIN, CANTEEN_STAFF | 250 |
| GET | /api/v1/canteen/inventory-movements | ADMIN, CANTEEN_STAFF | 261 |
| POST | /api/v1/canteen/orders | ADMIN, CANTEEN_STAFF | 262 |
| GET | /api/v1/canteen/orders | ADMIN, CANTEEN_STAFF | 263 |
| GET | /api/v1/canteen/orders/:id | ADMIN, CANTEEN_STAFF | 264 |
| POST | /api/v1/canteen/orders/:id/checkout-contexts | ADMIN, CANTEEN_STAFF | 265 |
| POST | /api/v1/canteen/orders/:id/identify | ADMIN, CANTEEN_STAFF | 273 |
| POST | /api/v1/canteen/orders/:id/payments | ADMIN, CANTEEN_STAFF | 274 |
| POST | /api/v1/canteen/orders/:id/cancel | ADMIN, CANTEEN_STAFF | 275 |
| GET | /api/v1/me/canteen-orders | ['STUDENT'] | 276 |
| POST | /api/v1/device-contexts/:id/cancel | ['ADMIN', 'PARKING_STAFF', 'CANTEEN_STAFF', 'LECTURER'] | 278 |
| GET | /api/v1/dashboard | null | 283 |
| GET | /api/v1/lecturer/class-sections | ADMIN, LECTURER | 310 |
| GET | /api/v1/attendance/sessions | ADMIN, LECTURER | 311 |
| POST | /api/v1/attendance/sessions | ADMIN, LECTURER | 312 |
| POST | /api/v1/attendance/sessions/:id/open | ADMIN, LECTURER | 313 |
| POST | /api/v1/attendance/sessions/:id/close | ADMIN, LECTURER | 314 |
| POST | /api/v1/attendance/sessions/:id/cancel | ADMIN, LECTURER | 315 |
| GET | /api/v1/attendance/sessions/:id | ADMIN, LECTURER | 316 |
| GET | /api/v1/attendance/sessions/:id/records | ADMIN, LECTURER | 317 |
| PATCH | /api/v1/attendance/records/:id | ADMIN, LECTURER | 318 |
| GET | /api/v1/me/attendance | ['STUDENT'] | 319 |
| POST | /api/v1/attendance/adjustment-requests | ['STUDENT'] | 320 |
| GET | /api/v1/attendance/adjustment-requests | ADMIN, LECTURER | 321 |
| POST | /api/v1/attendance/adjustment-requests/:id/decisions | ADMIN, LECTURER | 322 |
| GET | /api/v1/attendance/sessions/:id/report | ADMIN, LECTURER | 335 |
| GET | /api/v1/simulator/status | simRoles | 339 |
| GET | /api/v1/simulator/students | simRoles | 340 |
| GET | /api/v1/simulator/events | simRoles | 341 |
| POST | /api/v1/simulator/face-events | simRoles | 342 |
| POST | /api/v1/simulator/ocr-observations | ADMIN, PARKING_STAFF | 343 |
| POST | /api/v1/simulator/attendance-events | ADMIN, LECTURER | 344 |
| POST | /api/v1/simulator/gate-scenarios | ADMIN, PARKING_STAFF | 345 |
| POST | /api/v1/simulator/mock-topup-scenarios | ['ADMIN'] | 346 |
| GET | /api/v1/admin/reports | ['ADMIN'] | 349 |
| GET | /api/v1/admin/rfid-cards | ['ADMIN'] | 350 |
| GET | /api/v1/admin/settings | ['ADMIN'] | 351 |
| PUT | /api/v1/admin/settings/wallet-limits | ['ADMIN'] | 352 |
| PUT | /api/v1/admin/settings/point-conversion | ['ADMIN'] | 354 |
| PUT | /api/v1/admin/users/:id/roles | ['ADMIN'] | 355 |
| GET | /api/v1/admin/users | ['ADMIN'] | 364 |
| POST | /api/v1/admin/users | ['ADMIN'] | 365 |
| POST | /api/v1/admin/users/:id/status | ['ADMIN'] | 384 |
| GET | /api/v1/admin/roles | ['ADMIN'] | 399 |
| GET | /api/v1/admin/devices | ['ADMIN'] | 400 |
| POST | /api/v1/admin/devices/:id/status | ['ADMIN'] | 401 |
| PUT | /api/v1/admin/devices/:id/role | ['ADMIN'] | 403 |
| POST | /api/v1/admin/devices | ['ADMIN'] | 404 |
| POST | /api/v1/admin/devices/:id/rotate-credential | ['ADMIN'] | 405 |
| GET | /api/v1/admin/audit-logs | ['ADMIN'] | 406 |
| GET | /api/v1/admin/vehicles | ['ADMIN'] | 407 |
| GET | /api/v1/admin/parking-fee-policies | ['ADMIN'] | 408 |
| POST | /api/v1/admin/parking-fee-policies | ['ADMIN'] | 409 |
| POST | /api/v1/admin/parking-fee-policies/:id/activate | ['ADMIN'] | 419 |
| POST | /api/v1/admin/parking-passes | ['ADMIN'] | 420 |
| GET | /api/v1/admin/academic-terms | ['ADMIN'] | 421 |
| GET | /api/v1/admin/courses | ['ADMIN'] | 422 |
| GET | /api/v1/admin/classrooms | ADMIN, LECTURER | 423 |
| GET | /api/v1/admin/class-sections | ['ADMIN'] | 424 |
| GET | /api/v1/admin/schedules | ['ADMIN'] | 425 |
| POST | /api/v1/admin/academic-terms | ['ADMIN'] | 426 |
| POST | /api/v1/admin/courses | ['ADMIN'] | 427 |
| POST | /api/v1/admin/classrooms | ['ADMIN'] | 428 |
| POST | /api/v1/admin/class-sections | ['ADMIN'] | 429 |
| POST | /api/v1/admin/schedules | ['ADMIN'] | 430 |
| POST | /api/v1/admin/class-sections/:id/enrollments | ['ADMIN'] | 431 |
| POST | /api/v1/admin/class-sections/:id/teaching-assignments | ['ADMIN'] | 432 |
