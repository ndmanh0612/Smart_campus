# Kiến trúc mục tiêu và phạm vi prototype

Thiết kế kế thừa Express/TypeScript, Flutter và ESP32 của TapCard. PostgreSQL thay toàn bộ Mongoose; AI nội bộ là phần bổ sung. Hai widget Flutter được dùng lại trực tiếp, các provider chưa được chuyển API. Blueprint này chưa phải hệ thống đã triển khai.

```mermaid
flowchart TB
 ESP[ESP32 MFRC522 LCD] -->|HTTPS token event_id| API
 APP[Flutter Web và Android<br/>UI kế thừa chọn lọc và camera mới] -->|HTTPS| API[Proxy và Backend Express TypeScript]
 API --> ID[Identity RFID hoặc Face 1:1]
 API --> ATT[Class và Attendance]
 API --> PAY[Wallet Payment Ledger]
 API --> SERVICES[Canteen Parking Audit Outbox]
 ID -->|timeout service token| AI[FastAPI quality detection alignment PAD embedding matching]
 ID --> DB[(PostgreSQL 17)]
 ATT --> DB
 PAY --> DB
 SERVICES --> DB
 AI --> MODEL[Model version và SHA256]
```

Backend chia module trong một ứng dụng để transaction nghiệp vụ dùng chung DB. AI trả evidence, không ghi ví. Template Face mã hóa trong DB, key giữ ngoài DB; capture chỉ giữ theo consent/retention. Prototype hiện chỉ có RFID attendance; Face chưa có PAD và luôn từ chối cấp VERIFIED.

```mermaid
erDiagram
 STUDENTS ||--o{ STUDENT_CARDS : owns
 STUDENTS ||--o{ FACE_PROFILES : enrolls
 STUDENTS ||--o| WALLETS : owns
 CLASS_SESSIONS ||--o{ SESSION_ROSTER : contains
 STUDENTS ||--o{ SESSION_ROSTER : included
 SESSION_ROSTER ||--o| ATTENDANCE_RECORDS : records
 WALLETS ||--|| LEDGER_ACCOUNTS : references
 STUDENTS ||--o{ CANTEEN_ORDERS : orders
 STUDENTS ||--o{ VEHICLES : owns
 VEHICLES ||--o{ PARKING_SESSIONS : visits
 CANTEEN_ORDERS o|--o| PAYMENT_INTENTS : source
 PARKING_SESSIONS o|--o| PAYMENT_INTENTS : source
 PAYMENT_INTENTS o|--o| LEDGER_TRANSACTIONS : sale
 LEDGER_TRANSACTIONS ||--|{ LEDGER_ENTRIES : balances
 LEDGER_ACCOUNTS ||--o{ LEDGER_ENTRIES : posts
```

ERD rút gọn; ledger account có thể không thuộc wallet (tài khoản căn tin/nguồn tiền mô phỏng). SQL database/001.sql là căn cứ FK/check thực tế, gồm typed FK nguồn thanh toán và unique theo nguồn. Check/trigger chưa thay thế authorization, posting amount/account kind, cache balance và reversal service cần làm tuần 4.

```mermaid
sequenceDiagram
 participant E as ESP32
 participant B as Backend
 participant D as PostgreSQL
 E->>B: event_id card_uid purpose + Bearer
 B->>D: BEGIN lock device, lookup prior event
 alt retry cùng payload
 D-->>B: response đã commit
 B-->>E: cùng ACK
 else event mới
 B->>D: kiểm phiên OPEN, card active/expiry, roster
 alt hợp lệ
 B->>D: INSERT attendance UNIQUE(session,student), lưu ACK, COMMIT
 B-->>E: RECORDED hoặc ALREADY_RECORDED
 else không hợp lệ
 B->>D: lưu kết quả từ chối, COMMIT
 B-->>E: mã từ chối
 end
 end
```

Use Case và sơ đồ ví bản trước nằm ở diagrams/tham-khao-image*.png, trích nguyên từ báo cáo 02/11. Bản thiết kế chi tiết, vai trò, 28 ca gốc và lịch 8 tuần nằm trong THIET_KE_THAM_KHAO_02_11.md; mọi kết quả test lịch sử ở đó phải đối chiếu evidence mới.
