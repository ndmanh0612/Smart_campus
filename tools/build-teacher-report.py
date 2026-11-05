from pathlib import Path
import json
from docx import Document
from docx.shared import Inches,Pt,RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_CELL_VERTICAL_ALIGNMENT
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
E=ROOT/'docs/evidence'
D=Document()
def text(value,bold=False):
 p=D.add_paragraph();p.add_run(value).bold=bold;return p
def heading(value):D.add_heading(value,level=2)
def page(title):
 D.add_page_break();D.add_heading(title,level=1)
def table(rows,widths):
 t=D.add_table(rows=0,cols=len(widths));t.autofit=False
 for c,w in zip(t.columns,widths):c.width=Inches(w)
 pr=t._tbl.tblPr;b=OxmlElement('w:tblBorders')
 for edge in ['top','bottom','left','right','insideH','insideV']:
  el=OxmlElement('w:'+edge);el.set(qn('w:val'),'single');el.set(qn('w:sz'),'4');el.set(qn('w:color'),'D9DFE5');b.append(el)
 pr.append(b)
 for i,values in enumerate(rows):
  row=t.add_row();rp=row._tr.get_or_add_trPr();rp.append(OxmlElement('w:cantSplit'))
  if i==0:rp.append(OxmlElement('w:tblHeader'))
  for cell,w,value in zip(row.cells,widths,values):
   cell.width=Inches(w);cell.vertical_alignment=WD_CELL_VERTICAL_ALIGNMENT.CENTER
   cp=cell._tc.get_or_add_tcPr();m=OxmlElement('w:tcMar')
   for side in ['top','bottom','left','right']:
    el=OxmlElement('w:'+side);el.set(qn('w:w'),'85');el.set(qn('w:type'),'dxa');m.append(el)
   cp.append(m);p=cell.paragraphs[0];p.paragraph_format.space_after=Pt(2);p.paragraph_format.line_spacing=1.04
   r=p.add_run(value);r.font.size=Pt(9.5)
   if i==0:
    r.bold=True;r.font.color.rgb=RGBColor(255,255,255);shade=OxmlElement('w:shd');shade.set(qn('w:fill'),'294864');cp.append(shade)
 D.add_paragraph().paragraph_format.space_after=Pt(0)
def figure(name,caption):
 path=ROOT/'docs/diagrams'/name
 with Image.open(path) as im:width=min(6.5,7.65*im.width/im.height)
 p=D.add_paragraph();p.alignment=WD_ALIGN_PARAGRAPH.CENTER;p.add_run().add_picture(str(path),width=Inches(width))
 p=text(caption);p.alignment=WD_ALIGN_PARAGRAPH.CENTER
 for r in p.runs:r.font.size=Pt(9)
def main():
 s=D.sections[0];s.page_width=Inches(8.5);s.page_height=Inches(11);s.top_margin=s.bottom_margin=Inches(.7);s.left_margin=s.right_margin=Inches(1)
 normal=D.styles['Normal'];normal.font.name='Arial';normal.font.size=Pt(11);normal.paragraph_format.line_spacing=1.08;normal.paragraph_format.space_after=Pt(7)
 for name,size in [('Title',25),('Heading 1',17),('Heading 2',12)]:
  style=D.styles[name];style.font.name='Arial';style.font.size=Pt(size);style.font.color.rgb=RGBColor(0,0,0)
  props=style.element.find(qn('w:pPr'))
  if props is not None:
   for el in list(props.findall(qn('w:pBdr'))):props.remove(el)
 s.header.paragraphs[0].add_run('SMARTCARD AIoT   |   HỒ SƠ BÁO CÁO TUẦN 1').font.size=Pt(8)
 p=s.footer.paragraphs[0];p.alignment=WD_ALIGN_PARAGRAPH.RIGHT;p.add_run('Bản review 05/11/2026   •   Trang ').font.size=Pt(8)
 f=OxmlElement('w:fldSimple');f.set(qn('w:instr'),'PAGE');p._p.append(f)
 D.core_properties.title='Báo cáo tiến độ tuần 1 hệ thống thẻ sinh viên AIoT'
 D.core_properties.author='Nhóm SmartCard AIoT'
 flutter_path=E/'flutter-build.json';flutter=json.loads(flutter_path.read_text(encoding='utf-8-sig')) if flutter_path.exists() else {'status':'NOT_COMPLETE','reason':'SDK đang cài, chưa có đủ hai build được kiểm chứng'}
 built=flutter.get('status')=='PASS'
 D.add_paragraph('Báo cáo tiến độ tuần 1 hệ thống thẻ sinh viên AIoT',style='Title')
 text('Kế thừa TapCard và thiết kế PostgreSQL',True)
 text('Nhóm 2 người: thành viên 1 (bổ sung họ tên và MSSV) và Đức Mạnh. Quỹ thời gian 20 giờ/người/tuần. Ngày báo cáo chính thức và ngày bắt đầu 8 tuần chờ nhóm xác nhận.')
 text('Nhóm đã có thiết kế bản đầu, nguồn kế thừa rõ ràng và prototype backend/AI có bằng chứng kiểm thử. Chưa đủ điều kiện nghiệm thu trọn tuần 1 vì hiện chưa có thiết bị thật để thử và chưa chốt máy chủ qua đo đạc. Giảng viên đánh giá từng tiêu chí theo minh chứng, không ký thay trong hồ sơ này.')
 table([['Tiêu chí kế hoạch tuần 1','Minh chứng hiện có','Phần còn thiếu'],
 ['1 Phạm vi và kế hoạch','Scope Web/APK, phân công và lịch 8 tuần','Nhóm/GV xác nhận lịch và owner'],
 ['2 Kiến trúc và ERD','Định danh chung, attendance, wallet/ledger/canteen/parking; SQL và test chống trùng','Review thiết kế; phần lớn service còn thuộc tuần sau'],
 ['3 Spike RFID camera và hai build','Code RFID/camera, model/hash/license; '+('Web/APK build PASS' if built else 'build chưa hoàn tất'),'Board/camera thật; version Arduino và compatibility'],
 ['4 Máy chủ và chi phí','Phương án cấu hình, giá tham khảo và tách môi trường','VPS/domain/quyền và benchmark máy thuê'],
 ['5 Mẫu AI và tiêu chí đo','Protocol/target, P95/20client, RPO/RTO và test plan','Nhóm/GV chốt target và người phụ trách']],[1.53,2.55,2.42])
 text('Nguồn: kế hoạch 8 tuần Web Android Production v2, mục Tuần 1; PDF hệ thống thẻ sinh viên; source TapCard tại commit 6f600226e3f0f383897ee5d2d607733e5a80c84f. Kết quả dưới đây thuộc bản xây lại 05/11; không dùng số đo báo cáo cũ làm evidence mới.')
 page('1 Phạm vi và nguồn kế thừa')
 text('MVP: định danh sinh viên chung; RFID hoặc Face 1:1; điểm danh; ví tiền mô phỏng; căn tin; gửi xe cơ bản; Flutter Web và APK Android dùng cùng API. Face 1:N, OCR/OMR, dự đoán chuyên cần và Google Play để ngoài MVP.')
 table([['Thành phần TapCard','Cách kế thừa và trạng thái'],['ModernButton và ModernTextField','Đã copy hai widget, giữ attribution; ModernButton đã gọi trong camera spike. Build không đồng nghĩa camera máy thật đã đạt.'],['Màn hình và Provider Flutter','Giữ bố cục/quy trình có ích; chưa port hoàn chỉnh. Chuyển DTO _id/result/secret và auth/API đồng bộ.'],['Firmware MFRC522/LCD','Giữ luồng phần cứng và chân tham khảo; viết truyền HTTPS có CA/token, UID padding và event retry ổn định. Chưa compile/flash.'],['Express và TypeScript','Giữ stack và nghiệp vụ; PostgreSQL thay Mongoose. Prototype mới chỉ có RFID attendance.'],['Face và ví dịch vụ','Bổ sung theo đề tài. Chưa thấy Face/wallet/ledger/canteen/parking trong 46 file khảo sát.']],[1.75,4.75])
 heading('Quyết định kỹ thuật')
 text('Backend là một ứng dụng chia module để nghiệp vụ dùng chung transaction. Strategy cho RFID/Face, Service Layer cho nghiệp vụ, Adapter cho AI; chưa cần thêm ORM song song pg/SQL. AI chỉ trả evidence, không truy cập ví. Client không tự khai VERIFIED hoặc giá thanh toán.')
 text('Không mang log password/secret/UID thô, AES IV cố định, cấu hình mạng hoặc khóa ký debug của upstream vào bản vận hành. Quyền role phải kèm quyền trên hồ sơ, lớp và ví. Dữ liệu Face có consent và retention, template mã hóa, key ngoài DB.')
 text('Nguồn và sửa đổi được ghi trong docs/KE_THUA_TAPCARD.md, docs/evidence/tapcard-source.json và THIRD_PARTY_NOTICES.md. Metadata GPL-3.0-only trong package backend upstream chưa đủ để xác nhận license áp dụng cho mọi file; chưa tự gán license mới cho component kế thừa.')
 page('2 Kiến trúc toàn hệ thống')
 figure('tham-khao-image1.png','Thiết kế mục tiêu từ hồ sơ trước, giữ hướng PostgreSQL; phạm vi code đã chạy được đối chiếu ở phần kiểm chứng.')
 page('3 Dữ liệu và quy tắc nhất quán')
 figure('tham-khao-image2.png','ERD khái niệm. Tên cột/constraint chi tiết theo database/001.sql của bản xây lại; hình không thay SQL.')
 page('4 Kết quả kiểm chứng và demo')
 benchmark=json.loads((E/'ai-benchmark.json').read_text())
 table([['Kiểm tra','Kết quả và giới hạn'],['TypeScript và PostgreSQL','14 integration test PASS, 0 fail trên cluster test riêng. Có revoked/expired, roster, closed session, 20 concurrent scan/retry, rollback và ledger guard.'],['Demo backend','6 bước PASS; đầu vào HTTP giả lập thiết bị. Một attendance, ACK retry cũ, thẻ khóa/phiên đóng bị chặn, không có giao dịch ví.'],['AI unit và HTTP','5 test và 4 check PASS. Health200, thiếu token401, ready/verify503 khi PAD chưa cấu hình; không có Face authorization thành công.'],['Model runtime local',f"100 lần đo sau 5 warm-up. P95 detector ảnh trống {benchmark['detector_blank_ms']['p95']:.2f} ms; embedding tensor {benchmark['embedding_synthetic_ms']['p95']:.2f} ms. Không phải accuracy/PAD hay tải VPS."],['Flutter Web và Android','Hai build PASS; xem flutter-build.json.' if built else flutter['reason']]], [1.65,4.85])
 heading('Demo có thể chạy lại')
 text('Từ source chạy tools/demo-week1.ps1 với Node24/PostgreSQL17. Script dùng DB smartcard_week1_demo riêng ở loopback54330, không TRUNCATE dữ liệu cũ, tạo dữ liệu giả riêng mỗi lượt và tự tắt server sau demo. Xem docs/evidence/demo-backend.json và kịch bản docs/KICH_BAN_BAO_CAO.md.')
 text('Quy tắc: attendance UNIQUE(session,student), event PK(device,event), payload hash và ACK lưu cùng commit; điểm danh không tạo khoản chi. Ledger có cân bằng/deferred trigger và seal chống thêm entry sau commit. Posting/authorization/balance cache/reversal đầy đủ chưa implement, không kết luận ví đã an toàn để dùng tiền thật.')
 text('Evidence: postgres-integration.tap; demo-backend.json; ai-unit.txt; ai-http.json; ai-benchmark.json; models/manifest.json. Mọi số đo cần kèm môi trường, phiên bản và scope; 20 request đồng thời không là 20 client trong 10 phút.')
 page('5 AI và phương án máy chủ')
 text('YuNet/SFace đã kiểm SHA256, license từng model lưu riêng; PAD chưa chọn và matching threshold chưa hiệu chỉnh. Không lấy ngưỡng benchmark ngoài làm ngưỡng dự án. Model smoke dùng ảnh trống/tensor, không có ảnh người thật hay số accuracy trong báo cáo này.')
 table([['Hạng mục','Mục tiêu đề xuất cần GV xác nhận'],['Dữ liệu AI','20–30 người tự nguyện; enrollment riêng, development và test khác buổi; không rò frame liền kề. Consent, manifest ẩn danh, key owner và ngày xóa trước khi thu.'],['Matching và PAD','FMR≤1%, FNMR≤10%; APCER≤5% mỗi attack đã thử, BPCER≤10%. Đây là target pilot tiền demo, chưa đo/duyệt.'],['Hiệu năng','20 client/10 phút trên staging; P95 nearest-rank, throughput/error, CPU/RAM/queue. CRUD<500ms, RFID<2s, Face<3s phía server; round-trip báo riêng.'],['Phục hồi','RPO≤24h, RTO≤4h trước pilot. Backup mã hóa ngoài VPS; restore DB riêng, đo thời gian và đối soát ledger/files/model.']],[1.5,5])
 heading('Dự toán trong ngân sách 300000 đến 600000 đồng mỗi tháng')
 text('Phương án người dùng chọn: production thuê VPS 4 vCPU, 8 GB RAM, 80–100 GB SSD/NVMe, Ubuntu 24.04 LTS; staging tạm chạy máy nhóm, mục tiêu 2 vCPU/4 GB và 40–50 GB theo tài nguyên thực. Chưa mua VPS hoặc tên miền; cấu hình cần benchmark, chưa chứng minh đủ tải.')
 text('Nguồn tra 05/11: https://vietnix.vn/vps-ssd/ niêm yết 4 vCPU/8 GB nhưng chỉ 50 GB ở mức tham khảo 410.000đ/tháng, chưa đủ disk yêu cầu. Cần quote đúng 80–100 GB trong trần ngân sách. Cloudflare .com tham khảo 11,17 USD/năm tại https://pricing.registrar.cloudflare.com/; tên miền/thuế/tỷ giá chưa chốt. Backup 50.000–80.000đ/tháng là dự phòng kế hoạch, không báo giá.')
 text('Staging và production tách DB/volume/secret/role. Máy nhóm 8 GB RAM nên tránh build nặng, load và restore đồng thời; chưa có URL staging HTTPS công khai. PostgreSQL/AI private. Chủ trì DB/backup đề xuất: thành viên 1; build/thiết bị: Đức Mạnh; review chéo, chờ nhóm xác nhận. Chi tiết: docs/PHUONG_AN_TRIEN_KHAI.md.')
 page('6 Công việc còn thiếu và đề nghị nghiệm thu')
 table([['Việc','Chủ trì đề xuất','Bằng chứng để đóng'],['SDK và hai build','Đức Mạnh, thành viên1 review','Doctor/version/analyze/test; Web artifacts và APK hash. SDK đã được phép cài; xem trạng thái mới trong evidence.'],['RFID và camera thật','Đức Mạnh, thành viên1 đối chiếu DB','Hiện chưa có thiết bị để thử. Cần board/reader/LCD/Android, dây đúng điện áp, compile log, video và request/DB IDs.'],['VPS và domain','Cả hai','Gói/quote/thuế/chu kỳ, owner/MFA, hostname, quyền và benchmark VPS. Chưa có thông tin mới xác nhận đã thuê.'],['Lịch và mục tiêu','Cả hai và giảng viên','Ngày bắt đầu, ngày báo cáo, target AI/P95/RPO/RTO, owner và hạn bổ sung.']],[1.65,1.6,3.25])
 text('Lịch 8 tuần: W1 thiết kế/khả thi → W2 auth/RFID/staging → W3 Face/parking cơ bản → W4 wallet/ledger/restore → W5 tích hợp/tải → W6 production → W7 UAT → W8 bàn giao. Mỗi người20giờ/tuần; không tự coi toàn bộ quỹ giờ còn trống hoặc các giờ dự toán đã làm xong.')
 text('Đề nghị giảng viên review tiêu chí1,2,5 dựa trên hồ sơ; tiêu chí3,4 ghi phần thiếu và hạn bổ sung. Không xin ghi Đạt trọn tuần khi thiếu hai build, thiết bị thật hoặc máy chủ được chốt theo bằng chứng. Build thành công chỉ đóng phần build, không thay thử camera/board.')
 heading('Nội dung cần nhóm và giảng viên xác nhận')
 text('Ngày kiểm tra: ............................................................')
 text('Tiêu chí cần bổ sung và hạn: ...........................................')
 text('................................................................................')
 text('Kết luận của giảng viên: ................................................')
 text('Người review và phiên bản hồ sơ: .....................................')
 out=ROOT/'output';out.mkdir(exist_ok=True);target=out/'Bao_cao_Tuan_1_Trinh_Thay_05_11.docx';D.save(target);print(target)
if __name__=='__main__':main()
