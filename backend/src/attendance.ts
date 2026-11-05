import { audit, choice, emit, expected, fields, id, one, optional, reject, requirePermission, str, uuid, type Actor, type Db, type Result } from './platform.ts';
import { consumeIdentity, createContext, demoFace } from './devices.ts';
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
    if (now < new Date(schedule.starts_at).getTime() - 15 * 60000 || now > new Date(schedule.ends_at).getTime())
        reject(422, 'OUTSIDE_TIME_WINDOW', 'Không nằm trong khoảng thời gian được mở phiên.');
    const device = await one(db, 'SELECT * FROM devices WHERE id=$1 FOR UPDATE', [session.device_id]);
    if (!device.active || device.classroom_id !== session.classroom_id)
        reject(422, 'DEVICE_ROOM_MISMATCH', 'Thiết bị không còn đúng phòng.');
    await db.query('INSERT INTO attendance_session_roster SELECT $1,student_id FROM enrollments WHERE section_id=$2', [session.id, session.section_id]);
    await db.query('INSERT INTO attendance_session_devices VALUES($1,$2)', [session.id, device.id]);
    await db.query("UPDATE attendance_sessions SET status='OPEN',opened_at=clock_timestamp(),version=version+1 WHERE id=$1", [session.id]);
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
