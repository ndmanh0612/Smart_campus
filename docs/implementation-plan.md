# Roadmap, checklist và nghiệm thu

05/11/2026 — người dùng **đã duyệt thiết kế và cho phép triển khai các giai đoạn tiếp theo**. Checklist dưới đây là kế hoạch gốc; kết quả thực thi sẽ được cập nhật bằng evidence mới, không suy ra từ việc đã viết source.

## 1. Điểm bắt đầu review

| Tài liệu | Nội dung cần xem |
| --- | --- |
| [legacy-analysis.md](legacy-analysis.md) | Source thực tế, phạm vi bằng chứng, lỗi upstream, phần giữ/bỏ/chuyển |
| [requirements.md](requirements.md) | Vai trò, use cases, REAL/DEMO/MOCK, acceptance, mặc định chưa chốt |
| [architecture.md](architecture.md) | Express/pg modular monolith, boundaries, security/config, folder target |
| [business-flows.md](business-flows.md) | State machines, holds/capture, gate reconciliation, cantin/attendance |
| [database-design.md](database-design.md) | ERD/dictionary, invariant, constraints/locks, migration mapping |
| [api-contracts.md](api-contracts.md) | User/device/service auth, endpoint contracts, schemas provider, realtime |
| [camera-integration-guide.md](camera-integration-guide.md) | Demo mặc định và điều kiện thay camera/AI thật |

Các tài liệu KIEN_TRUC/API/KE_THUA_TAPCARD và evidence cũ là tài liệu prototype/lịch sử. Không đọc chúng như bằng chứng thiết kế mới đã được implement. README có đường dẫn tới bộ thiết kế này; code hiện có giữ nguyên tại GĐ0–1.

## 2. Quyết định đề nghị duyệt

1. Giữ Express/TypeScript + PostgreSQL/pg + SQL migrations; chưa thêm NestJS/ORM/Redis. Transaction thủ công nhỏ, parameterized và test bằng DB thật.
2. Flutter Android cho SV, Flutter Web cho staff/admin với layout riêng; tận dụng widget có sẵn, không dùng camera spike làm giao diện nghiệp vụ giả.
3. Demo Face/Camera/Liveness/OCR ở backend; không cần model/FastAPI/GPU cho MVP. RFID luôn thật; một reader đổi bốn role tuần tự qua config server.
4. Cổng mô phỏng có passage confirmation riêng; phí gửi xe giữ point trước, capture khi xe ra. UNKNOWN không tự release/thu lại, phải reconcile.
5. PIN/app confirmation trên app sinh viên cho mọi chi trả >0 kể cả parking; credential device/UID không là quyền chi tiền.
6. Giữ prototype/schema cũ, thêm migration có backfill/đối chiếu. Không reset DB, DROP bảng, xóa volume hoặc copy secret từ upstream.

Thông số phí, hạn mức, attendance window, retention, board/LCD và deployment domain còn cần chốt tại giai đoạn liên quan. Các mặc định dev ở SRS cho phép tiếp tục thiết kế, không phải chính sách thật. Không cần hỏi thêm quyết định ngăn thiết kế ở thời điểm này.

## 3. Cổng chất lượng chung cho từng giai đoạn

Trước code: inspect entry/caller/config/test → trace input/output/data flow → nêu vấn đề, giải pháp, file, ảnh hưởng. Mỗi giai đoạn mở checklist cụ thể, implement thay đổi nhỏ, test đúng phạm vi, ghi evidence mới, review diff, cập nhật tài liệu và báo cáo phần còn thiếu. Không dùng “đã hoàn thành” nếu thiếu evidence của điều kiện bắt buộc.

Evidence mỗi lần chạy: case ID, source/version hash nếu có, ngày giờ, người chạy/môi trường, lệnh đã chạy, expected, actual, PASS/FAIL/NOT_RUN/BLOCKED, log đã lọc dữ liệu. Không commit .env/token/PIN/UID raw/face thật; HTTP fixtures không được gắn nhãn hardware test.

## 4. Checklist triển khai hiện hành

Chi tiết source, bằng chứng và giới hạn: [implementation-status.md](implementation-status.md). Checkbox code không thay thế hardware/browser acceptance.

### Giai đoạn 0–1 — Khảo sát và thiết kế

- [x] Đọc source, trace nghiệp vụ, chốt ma trận kế thừa và đủ 8 tài liệu.
- [x] Người dùng duyệt thiết kế trước triển khai.
- [x] Kiểm lại 46/46 hash source ghim; commit trùng default-branch HEAD tại thời điểm kiểm (`evidence/tapcard-reverified.json`).
- [x] Giữ attribution và prototype, không copy credential upstream.

### Giai đoạn 2 — Backend core

- [x] Baseline prototype 14/14, Campus final suite 40/40, TypeScript check.
- [x] Additive migrations, runtime grants, auth/refresh/RBAC, identity/card/consent/device lifecycle, audit/outbox.
- [x] Ledger/hold/posting/mock callback/refund, approval/PIN/limits, concurrency và regression snapshot wallet.
- [x] Native upgrade/readiness/login/RBAC/grants và backup/restore vào DB riêng đạt; không reset DB local.

### Giai đoạn 3 — Firmware RFID thật

- [x] Source mới riêng ở firmware/smart_campus; giữ pin map classic ESP32, TLS/NTP/config/ACK, NVS pending/retry/action polling.
- [x] Cài toolchain riêng, ghi version/checksum CLI/core/libraries.
- [x] Compile source cuối PASS, source hash khớp firmware-compile.json; không flash.
- [ ] Xác minh chip biến thể, điện áp/I2C address, COM và wiring thực tế.
- [ ] Provision, flash, quét MFRC522/LCD, mất mạng/TLS/reboot/retry và đổi role trên một reader thật.

GĐ3 chưa đóng: user xác nhận ESP32 Dev Board, Windows chưa thấy serial. Compile/HTTP tests không phải hardware run.

### Giai đoạn 4 — Parking

- [x] Vehicle/authorization/policy/pass, OCR DEMO/correction, occupancy, quote/PIN/hold, passage/capture, timeout/fencing/reversal.
- [x] API/DB tests cho wrong plate, thiếu point, duplicate, UNKNOWN/no-passage, full reversal/new cycle và monthly pass.
- [ ] End-to-end bằng RFID thật sau GĐ3.

### Giai đoạn 5 — Cantin

- [x] Catalog/inventory/reservation/POS/identity/approval/atomic checkout/refund.
- [x] API/DB tests cho cạnh tranh ví/kho, expiry, thiếu point, retry/payment dedupe, refund bounds và grants.
- [ ] Scan CANTEEN_POS và biên lai trên phần cứng thật.

### Giai đoạn 6 — Attendance

- [x] Academic data/assignment/schedule/room, lecturer OPEN/CLOSE/CANCEL, roster snapshot và corrections/audit/CSV.
- [x] Face/Camera/Liveness DEMO, provider ports, consent/profile erasure và fixture guards.
- [x] PostgreSQL/HTTP và WebSocket tests: open-before-attend, scope/duplicate/late/absent, role/cookie/CSRF và owner event delivery.

### Giai đoạn 7 — UI

- [x] Flutter student/staff/admin/lecturer screens và simulation dashboard nối API.
- [x] Analyze sạch, 4/4 widget tests, Web release build cuối đạt.
- [x] APK debug build cuối PASS.
- [ ] Visual/click E2E trên browser và chạy Android thật; browser tool hiện lỗi attach webview.

### Giai đoạn 8 — Local/đóng gói

- [x] Native startup/upgrade/auth/grants và isolated backup/restore đạt.
- [x] Runbook local/Compose/RFID, demo scenarios, camera adapters và security boundaries.
- [x] Compose build/health/ba luồng Face DEMO qua proxy/seed/restart/backup-restore đạt trên image đã dùng; offline YAML/digest pin check đạt. CLI config sau pin chưa chạy do approval review usage limit (xem báo cáo).
- [x] Đóng gói source/Web/APK, SHA-256 và quét archive member/credential dài PASS (evidence/campus-artifacts.json).
- [ ] Hardware-backed MVP acceptance; không đánh hoàn thành 10 tiêu chí khi chưa quét RFID thật.

## 5. Ma trận kiểm thử và expected results

Đây là test matrix mục tiêu, không phải danh sách mọi case đã PASS. Coverage thực thi xem 40 test có tên trong evidence/campus-tests.tap và báo cáo trạng thái. T01/T05 phần cứng, RFID-backed T07/T09/T20 và visual T31 chưa chạy; fault injection DB outage của T13 chưa chạy. Retry/callback concurrency hiện kiểm 10 request, chưa chạy cấu hình 20 request của matrix gốc. Không suy ra mọi tổ hợp trong một dòng đã được kiểm chỉ vì test cùng domain đạt.

| ID | Mức/giai đoạn | Ca thử | Expected |
| --- | --- | --- | --- |
| T01 | Hardware GĐ3 | Quét MFRC522 thật, UID có byte 00/01, LCD | UID đúng padding, event/auth/DB tương ứng, LCD đúng ACK/action |
| T02 | Integration + hardware GĐ2/3 | Thẻ unknown/LOST/REVOKED/EXPIRED, SV khóa | Reject, không assertion/chi tiền/điểm danh |
| T03 | Contract/security GĐ2/3 | Token sai, deviceId spoof, role/version sai | 401/403/409, không side effect |
| T04 | Integration GĐ2 | 20 retry cùng event; cùng ID khác payload | Một event/kết quả, khác payload 409 |
| T05 | Hardware + integration GĐ3 | Wi-Fi mất, ACK mất, TLS CA sai, reboot pending | Không offline success; retry cùng ID; query recovery; CA sai fail-closed |
| T06 | Security GĐ2 | Challenge hết hạn/đã dùng/new event ID replay | Reject; duplicate đúng event vẫn lấy ACK không thực thi lại |
| T07 | E2E GĐ4 | RFID thật + OCR DEMO → entry + passage | Một ACTIVE session/occupancy, source tách rõ |
| T08 | Integration GĐ4 | Hai entry đồng thời cùng vehicle bởi hai SV | Một lượt thắng, lượt còn lại conflict; không hai occupancy |
| T09 | E2E GĐ4 | Exit đúng SV/plate/approval/point + passage | Một PARKING_PAYMENT, session COMPLETED, occupancy release |
| T10 | Integration GĐ4 | Exit sai SV/plate/không active session | Không mở tự động, audit exception có quyền |
| T11 | E2E GĐ4 | Thiếu point → mock top-up → retry | Shortfall đúng; callback cộng một lần; charge một lần |
| T12 | Integration GĐ4 | Timeout trước mở chắc chắn/UNKNOWN/sau mở chưa passage | Release chỉ khi chứng minh chưa ra; UNKNOWN giữ hold/occupancy; không capture từ OPENED |
| T13 | Fault injection GĐ4 | Passage trước DB outage, late ACK sau void/reversal, full reversal rồi exit lại | Reconcile cùng payment; event cũ không charge; chỉ resolution có quyền mở cycle mới sau full reversal và fence, tổng thu ròng đúng một lượt |
| T14 | Unit + DB GĐ4 | Phí grace/hour/day/cap/pass đổi policy | Snapshot deterministic, server time, không lấy giá client |
| T15 | Integration GĐ2 | 2 charge 80 point cạnh tranh ví có 100 | Một thành công, một thiếu point, balance/available>=0; tổng ledger cân bằng |
| T16 | Integration GĐ2 | 20 callback cùng top-up; amount mismatch; callback sau cancel | Cộng một lần; mismatch reject; late chuyển review, không tự cộng |
| T17 | Integration/security GĐ2/5 | Refund lặp/partial đồng thời/vượt original/sai quyền | Tổng refund<=charge, replay receipt, quyền sai reject, không UPDATE ledger |
| T18 | Integration GĐ5 | Checkout đồng thời 2 đơn cho sản phẩm cuối | Không oversell; reserved<=onHand, một đơn phù hợp thành công |
| T19 | Integration GĐ5 | Cart sửa giá/qty client, reservation expiry race checkout | Server price; atomic winner; không negative stock/COMPLETED lỗi |
| T20 | Integration/E2E GĐ5 | UID/Face DEMO không PIN, approval hết hạn/sai amount/order | Reject, không debit/stock change; PIN/app đúng mới charge |
| T21 | Security GĐ2/5 | PIN brute-force, daily limit, card lost sau scan trước authorization; lost sau gate dispatch | Lock/rate limit; authorization mới reject; hold đã dispatch reconcile theo passage, không auto-release |
| T22 | E2E GĐ6 | Chưa OPEN/CLOSED/CANCELLED, GV sai phân công | Attendance reject, không mở/đóng phiên người khác |
| T23 | Integration GĐ6 | Sai roster/device/phòng, duplicate, late threshold | Reject sai scope; một record; bằng lateAfter PRESENT, sau là LATE |
| T24 | Integration GĐ6 | Close cạnh tranh event, roster change, manual correction | Serialize theo session; roster snapshot; ABSENT/correction audit đúng |
| T25 | Provider contract GĐ4/6 | Face unknown/low confidence/liveness fail/multiple faces/timeout | Identity không được dùng, source DEMO, không fallback thành công |
| T26 | Security GĐ2/6 | STUDENT gọi simulator/room khác, production bật demo | 403/404; socket không lộ data; production bootstrap fail |
| T27 | Integration GĐ6 | Socket disconnect/reconnect/outbox publish lặp | REST snapshot đầy đủ; dedupe event, không duplicate business record |
| T28 | DB/grants GĐ2 | UPDATE/DELETE ledger, thêm entry vào posting cũ, unbalanced commit | App role bị chặn; rollback không cập nhật balance/outbox |
| T29 | E2E GĐ8 | Compose clean boot/migrate/seed/restart/health | Ready đúng schema; seed không double credit; không publish DB |
| T30 | Migration GĐ8 | Upgrade DB prototype + restore backup | Counts/UUID/balance giữ, dữ liệu mơ hồ yêu cầu mapping, không drop tùy tiện |
| T31 | E2E GĐ7/8 | Role UI, history/wallet real DB, lỗi và responsive | Scope đúng, loading/error thật, mode labels luôn rõ |
| T32 | Privacy GĐ2/8 | Revoke consent/delete profile/log/report export | Future recognition blocked; template xóa theo job; log không secret; CSV an toàn |

## 6. Đối chiếu 10 tiêu chí MVP

| Tiêu chí | Evidence bắt buộc | Giai đoạn |
| --- | --- | --- |
| 1 Danh tính thống nhất | studentId FK và E2E ba domain | 2/4/5/6 |
| 2 RFID thật + LCD | Compile/flash/scan evidence và ID event/DB | 3 |
| 3 Entry thật + OCR demo | T07 hardware-backed | 4 |
| 4 Exit đúng chủ/biển, thu một lần | T09–T15 + receipt/ledger | 4 |
| 5 Cantin RFID + confirmation + kho | T18–T21 và scan thật | 5 |
| 6 Top-up mock + ledger | T16 + UI lịch sử, nhãn không tiền thật | 2/7 |
| 7 GV mở phiên rồi Face DEMO, không trùng | T22–T25, room realtime | 6 |
| 8 Demo lỗi/ngoại lệ | Kịch bản T02–T06/T10–T13/T17–T26 trên dashboard | 7/8 |
| 9 UI dữ liệu backend | T31 và đối chiếu GET/DB có quyền | 7 |
| 10 Local tái lập + adapter | T29/T30 và camera guide/provider contract | 8 |

## 7. Rủi ro và hành động trước bước tiếp theo

| Rủi ro | Cách giảm | Cần ai/chốt khi nào |
| --- | --- | --- |
| Upstream source/license | Đã verify 46 hash và HEAD qua HTTP; chưa chạy upstream, vẫn phải giữ notice và chốt quyền phân phối | Trước công bố |
| DB prototype có thể chứa dữ liệu cần giữ | Inventory/backup/restore trước migration, chỉ reset DB test riêng | Chủ dữ liệu trước GĐ2 |
| UID clone | PIN/app confirmation + limits + revoke; không tuyên bố UID an toàn tài chính | Thiết kế core bắt buộc |
| LCD/I2C/board chưa kiểm điện | Kiểm schematic/module/pullup, nguồn/level shifting trước nối | Người có phần cứng GĐ3 |
| Gate UNKNOWN giữ point lâu | Staff reconcile queue/alert, command fencing, evidence; không auto-refund mù | Người vận hành GĐ4 |
| Một reader demo nhiều domain | Lập kịch bản tuần tự, config ACK, không đổi role khi busy | GĐ3–7 |
| License nguồn chưa rõ phạm vi | Giữ notice, xác minh quyền phân phối với chủ nguồn | Trước công bố |
| Mở rộng phạm vi vượt MVP | Xong từng cổng kiểm thử; camera/payment thật là giai đoạn riêng | Người dùng duyệt thay đổi scope |

**Trạng thái hiện tại:** đã được phép triển khai. Test phần mềm, build, Docker và phần cứng phải ghi evidence riêng; không tự nhận đã kiểm phần cứng từ kiểm thử HTTP hoặc Markdown.
