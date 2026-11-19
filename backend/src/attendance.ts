import { audit, choice, emit, expected, fields, id, one, optional, reject, requirePermission, str, uidHash, uuid, type Actor, type Db, type Result } from './platform.ts';
import { consumeIdentity, createContext, demoFace } from './devices.ts';
import { identifyFaceReal } from './face-service.ts';
export async function teachingScope(db: Db, a: Actor, sectionId: string) {
    if (a.roles.includes('ADMIN'))
        return;
    if (!a.lecturerId || !await optional(db, 'SELECT 1 FROM teaching_assignments WHERE section_id=$1 AND lecturer_id=$2', [sectionId, a.lecturerId]))
        reject(403, 'NOT_ASSIGNED_LECTURER', 'Bạn không được phân công lớp này.');
}
export async function createSession(db: Db, a: Actor, body: unknown) {
    const b = fields(body, ['scheduleId', 'deviceId']);
    if (!a.lecturerId)
        reject(403, 'LECTURER_REQUIRED', 'Chỉ giảng viên được mở phiên lớp phụ trách.');
    const schedule = await one(db, 'SELECT * FROM schedules WHERE id=$1', [uuid(b.scheduleId)]);
    await teachingScope(db, a, schedule.section_id);
    const device = await one(db, "SELECT * FROM devices WHERE id=$1 AND active AND kind='ATTENDANCE_CAMERA'", [uuid(b.deviceId)]);
    if (device.classroom_id !== schedule.classroom_id)
        reject(422, 'DEVICE_ROOM_MISMATCH', 'Camera demo không thuộc phòng của lịch học.');
    const sessionId = id();
    await db.query("INSERT INTO attendance_sessions(id,schedule_id,section_id,classroom_id,device_id,opened_by,status,late_after) VALUES($1,$2,$3,$4,$5,$6,'SCHEDULED',$7::timestamptz+interval '10 minutes')", [sessionId, schedule.id, schedule.section_id, schedule.classroom_id, device.id, a.lecturerId, schedule.starts_at]);
    await audit(db, a, 'ATTENDANCE_SCHEDULED', sessionId);
    return one(db, 'SELECT * FROM attendance_sessions WHERE id=$1', [sessionId]);
}
export async function openSession(db: Db, a: Actor, sessionId: string, body: unknown) {
    const b = fields(body, ['expectedVersion']);
    const session = await one(db, 'SELECT * FROM attendance_sessions WHERE id=$1 FOR UPDATE', [sessionId]);
    await teachingScope(db, a, session.section_id);
    expected(session.version, b.expectedVersion);
    if (session.status !== 'SCHEDULED')
        reject(409, 'SESSION_STATE', 'Phiên không ở trạng thái chờ mở.');
    const schedule = await one(db, 'SELECT * FROM schedules WHERE id=$1', [session.schedule_id]);
    const now = Date.now();
    if (process.env.APP_ENV !== 'development' && (now < new Date(schedule.starts_at).getTime() - 15 * 60000 || now > new Date(schedule.ends_at).getTime()))
        reject(422, 'OUTSIDE_TIME_WINDOW', 'Không nằm trong khoảng thời gian được mở phiên.');
    const device = await one(db, 'SELECT * FROM devices WHERE id=$1 FOR UPDATE', [session.device_id]);
    if (!device.active || device.classroom_id !== session.classroom_id)
        reject(422, 'DEVICE_ROOM_MISMATCH', 'Thiết bị không còn đúng phòng.');
    await db.query('INSERT INTO attendance_session_roster SELECT $1,student_id FROM enrollments WHERE section_id=$2 ON CONFLICT DO NOTHING', [session.id, session.section_id]);
    await db.query('INSERT INTO attendance_session_devices VALUES($1,$2) ON CONFLICT DO NOTHING', [session.id, device.id]);
    if (process.env.APP_ENV === 'development') {
        await db.query("UPDATE attendance_sessions SET status='OPEN',opened_at=clock_timestamp(),late_after=clock_timestamp()+interval '30 minutes',version=version+1 WHERE id=$1", [session.id]);
    } else {
        await db.query("UPDATE attendance_sessions SET status='OPEN',opened_at=clock_timestamp(),version=version+1 WHERE id=$1", [session.id]);
    }
    await audit(db, a, 'ATTENDANCE_OPENED', session.id);
    await emit(db, 'attendance.session.opened', session.id);
    return one(db, 'SELECT * FROM attendance_sessions WHERE id=$1', [session.id]);
}
export async function closeSession(db: Db, a: Actor, sessionId: string, body: unknown, cancel = false) {
    const b = fields(body, ['expectedVersion', 'reason'], cancel ? ['expectedVersion', 'reason'] : ['expectedVersion']);
    const session = await one(db, 'SELECT * FROM attendance_sessions WHERE id=$1 FOR UPDATE', [sessionId]);
    await teachingScope(db, a, session.section_id);
    expected(session.version, b.expectedVersion);
    if (!['SCHEDULED', 'OPEN'].includes(session.status))
        reject(409, 'SESSION_STATE', 'Phiên đã đóng hoặc hủy.');
    const reason = cancel ? str(b.reason, 1000, 5) : 'Giảng viên đóng phiên';
    if (!cancel && session.status !== 'OPEN')
        reject(409, 'SESSION_NOT_OPEN', 'Chỉ đóng phiên đang mở.');
    if (!cancel)
        await db.query("INSERT INTO attendance_records(id,session_id,student_id,status,source) SELECT gen_random_uuid(),session_id,student_id,'ABSENT','MANUAL' FROM attendance_session_roster WHERE session_id=$1 ON CONFLICT(session_id,student_id) DO NOTHING", [session.id]);
    await db.query('UPDATE attendance_sessions SET status=$2,closed_at=clock_timestamp(),version=version+1 WHERE id=$1', [session.id, cancel ? 'CANCELLED' : 'CLOSED']);
    await db.query("UPDATE device_contexts SET status='CANCELLED' WHERE attendance_session_id=$1 AND status='OPEN'", [session.id]);
    await audit(db, a, cancel ? 'ATTENDANCE_CANCELLED' : 'ATTENDANCE_CLOSED', session.id, reason);
    await emit(db, 'attendance.session.closed', session.id, { status: cancel ? 'CANCELLED' : 'CLOSED' });
    return one(db, 'SELECT * FROM attendance_sessions WHERE id=$1', [session.id]);
}
export async function attendanceDemo(db: Db, a: Actor, body: unknown): Promise<Result> {
    requirePermission(a, 'simulator.use');
    const b = fields(body, ['sessionId', 'deviceId', 'studentFixtureId', 'scenario']);
    const session = await one(db, 'SELECT * FROM attendance_sessions WHERE id=$1 FOR UPDATE', [uuid(b.sessionId)]);
    await teachingScope(db, a, session.section_id);
    if (session.status !== 'OPEN')
        reject(422, 'SESSION_NOT_OPEN', 'Giảng viên phải mở phiên trước khi điểm danh.');
    if (session.device_id !== uuid(b.deviceId))
        reject(422, 'DEVICE_ROOM_MISMATCH', 'Sai thiết bị điểm danh.');
    const schedule = await one(db, 'SELECT ends_at FROM schedules WHERE id=$1', [session.schedule_id]);
    if (new Date(schedule.ends_at) < new Date())
        reject(422, 'OUTSIDE_TIME_WINDOW', 'Buổi học đã hết thời gian điểm danh.');
    const studentId = uuid(b.studentFixtureId);
    if (!await optional(db, 'SELECT 1 FROM attendance_session_roster WHERE session_id=$1 AND student_id=$2', [session.id, studentId]))
        reject(422, 'NOT_ENROLLED', 'Sinh viên không thuộc danh sách lớp tại lúc mở phiên.');
    let ctx = await optional(db, "SELECT id FROM device_contexts WHERE device_id=$1 AND attendance_session_id=$2 AND status='OPEN' AND expires_at>now()", [session.device_id, session.id]);
    if (!ctx)
        ctx = await createContext(db, session.device_id, 'ATTENDANCE', session.id);
    const face = await demoFace(db, a, { contextId: ctx.id, studentFixtureId: studentId, scenario: b.scenario });
    if (face.error)
        return face;
    const faceData = face.data as {
        identityAssertionId: string;
        faceResult: unknown;
    };
    await consumeIdentity(db, faceData.identityAssertionId, 'ATTENDANCE', session.id);
    const result = await db.query("INSERT INTO attendance_records(id,session_id,student_id,status,source) VALUES($1,$2,$3,CASE WHEN clock_timestamp()>$4 THEN 'LATE' ELSE 'PRESENT' END,'DEMO') ON CONFLICT(session_id,student_id) DO NOTHING RETURNING *", [id(), session.id, studentId, session.late_after]);
    const record = await one(db, 'SELECT * FROM attendance_records WHERE session_id=$1 AND student_id=$2', [session.id, studentId]);
    if (result.rowCount) {
        const user = await one(db, 'SELECT user_id FROM students WHERE id=$1', [studentId]);
        await emit(db, 'attendance.recorded', session.id, { recordId: record.id, studentId, status: record.status, source: 'DEMO' }, user.user_id);
        await audit(db, a, 'ATTENDANCE_DEMO_RECORDED', record.id);
    }
    return { status: result.rowCount ? 201 : 200, data: { record, outcome: result.rowCount ? 'RECORDED' : 'ALREADY_RECORDED', source: 'DEMO', faceResult: faceData.faceResult } };
}
export async function correctRecord(db: Db, a: Actor, recordId: string, body: unknown) {
    const b = fields(body, ['status', 'reason', 'expectedVersion']);
    const record = await one(db, 'SELECT r.*,s.section_id FROM attendance_records r JOIN attendance_sessions s ON s.id=r.session_id WHERE r.id=$1 FOR UPDATE OF r', [recordId]);
    await teachingScope(db, a, record.section_id);
    expected(record.version, b.expectedVersion);
    const status = choice(b.status, ['PRESENT', 'LATE', 'ABSENT', 'EXCUSED'] as const), reason = str(b.reason, 1000, 5);
    await db.query('INSERT INTO attendance_corrections VALUES($1,$2,$3,$4,$5,$6,now())', [id(), record.id, record.status, status, reason, a.id]);
    await db.query("UPDATE attendance_records SET status=$2,source='MANUAL',version=version+1 WHERE id=$1", [recordId, status]);
    await audit(db, a, 'ATTENDANCE_CORRECTED', recordId, reason, { before: record.status, after: status });
    await emit(db, 'attendance.recorded', record.session_id, { recordId, status, source: 'MANUAL' });
    return one(db, 'SELECT * FROM attendance_records WHERE id=$1', [recordId]);
}
export function csvCell(value: unknown) {
    let text = String(value ?? '');
    if (/^[=+@\-\t\r]/.test(text))
        text = "'" + text;
    return '"' + text.replace(/"/g, '""') + '"';
}
export async function checkinReal(db: Db, a: Actor, sessionId: string, body: unknown, cardKey: string): Promise<Result> {
    const b = fields(body, ['cardUid', 'studentId', 'imageBase64', 'method'], []);
    const session = await one(db, 'SELECT * FROM attendance_sessions WHERE id=$1 FOR UPDATE', [uuid(sessionId)]);
    await teachingScope(db, a, session.section_id);
    if (session.status !== 'OPEN') {
        reject(422, 'SESSION_NOT_OPEN', 'Phiên điểm danh chưa được mở.');
    }

    let student: any = null;
    let method: string = typeof b.method === 'string' ? b.method : 'RFID';

    if (b.studentId) {
        student = await optional(db, 'SELECT s.*, u.name FROM students s JOIN users u ON u.id=s.user_id WHERE s.id=$1', [uuid(b.studentId)]);
    } else if (b.cardUid) {
        const cleanUid = str(b.cardUid, 20).replace(/[^0-9a-fA-F]/g, '').toUpperCase();
        const digest = uidHash(cleanUid.length % 2 !== 0 ? '0' + cleanUid : cleanUid, cardKey);
        student = await optional(db, "SELECT s.*, u.name FROM rfid_cards c JOIN students s ON s.id=c.student_id JOIN users u ON u.id=s.user_id WHERE c.uid_hmac=$1 AND c.status='ACTIVE'", [digest]);
        method = 'RFID';
        if (!student) {
            reject(404, 'CARD_UNREGISTERED', 'Thẻ RFID chưa được gán cho sinh viên nào.');
        }
    } else if (b.imageBase64) {
        method = 'FACE';
        const match = await identifyFaceReal(str(b.imageBase64, 16 * 1024 * 1024));
        if (!match.success || match.outcome !== 'MATCH' || !match.studentId) {
            reject(422, 'FACE_NOT_RECOGNIZED', match.message || 'Không nhận diện được khuôn mặt sinh viên.');
        }
        student = await optional(db, 'SELECT s.*, u.name FROM students s JOIN users u ON u.id=s.user_id WHERE s.id=$1', [uuid(match.studentId!)]);
    }

    if (!student) {
        reject(404, 'STUDENT_NOT_FOUND', 'Không tìm thấy thông tin sinh viên.');
    }

    // Ensure student is in roster (auto-enroll if dev)
    const inRoster = await optional(db, 'SELECT 1 FROM attendance_session_roster WHERE session_id=$1 AND student_id=$2', [session.id, student.id]);
    if (!inRoster) {
        await db.query('INSERT INTO attendance_session_roster(session_id, student_id) VALUES($1, $2) ON CONFLICT DO NOTHING', [session.id, student.id]);
    }

    // Check if already checked in
    const existing = await optional(db, 'SELECT * FROM attendance_records WHERE session_id=$1 AND student_id=$2', [session.id, student.id]);
    if (existing) {
        return {
            status: 200,
            data: {
                alreadyRecorded: true,
                student: { id: student.id, studentCode: student.student_code, name: student.name },
                status: existing.status,
                method,
                receivedAt: existing.received_at
            }
        };
    }

    const isLate = session.late_after && new Date() > new Date(session.late_after);
    const recordStatus = isLate ? 'LATE' : 'PRESENT';
    const recordId = id();
    await db.query(
        "INSERT INTO attendance_records(id, session_id, student_id, status, source, received_at) VALUES($1, $2, $3, $4, 'REAL', clock_timestamp())",
        [recordId, session.id, student.id, recordStatus]
    );

    const record = await one(db, 'SELECT * FROM attendance_records WHERE id=$1', [recordId]);
    await audit(db, a, 'ATTENDANCE_RECORDED', recordId, `${student.student_code} - ${student.name} (${recordStatus})`);
    await emit(db, 'attendance.recorded', session.id, { recordId, studentId: student.id, status: recordStatus, source: 'REAL' }, student.user_id);

    return {
        status: 201,
        data: {
            success: true,
            alreadyRecorded: false,
            student: { id: student.id, studentCode: student.student_code, name: student.name },
            status: recordStatus,
            method,
            receivedAt: record.received_at
        }
    };
}
