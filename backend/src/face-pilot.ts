import { execFile } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import type { Express, Response } from 'express';
import type { Pool } from 'pg';
import { choice, fields, handler, id, one, reject, requireRole, send, uuid, type Actor } from './platform.ts';

export function mountFacePilot(app: Express, pool: Pool, camera: string) {
    const root = resolve(import.meta.dirname, '../..');
    const script = resolve(root, 'ai-service/face_pilot.py');
    let busy = false;
    let frame: { jpeg: Buffer; receivedAt: number } | undefined;
    let stream: AbortController | undefined;
    let idle: ReturnType<typeof setTimeout> | undefined;
    const viewers = new Set<Response>();
    const jpegStart = Buffer.from([0xff, 0xd8]);
    const jpegEnd = Buffer.from([0xff, 0xd9]);
    const maxJpegBytes = 2 * 1024 * 1024;

    function requestLiveFrame() {
        if (idle)
            clearTimeout(idle);
        if (!stream) {
            const controller = new AbortController();
            stream = controller;
            const url = new URL(camera);
            url.port = String(Number(url.port || 80) + 1);
            url.pathname = '/stream';
            url.search = '';
            let watchdog = setTimeout(() => controller.abort(), 3500);
            void (async () => {
                const upstream = await fetch(url, { signal: controller.signal });
                if (!upstream.ok || !upstream.body)
                    throw Error('Camera stream unavailable');
                const reader = upstream.body.getReader();
                let buffer = Buffer.alloc(0);
                try {
                    for (;;) {
                        const chunk = await reader.read();
                        if (chunk.done)
                            break;
                        clearTimeout(watchdog);
                        watchdog = setTimeout(() => controller.abort(), 3500);
                        buffer = Buffer.concat([buffer, chunk.value]);
                        let start = buffer.indexOf(jpegStart);
                        while (start >= 0) {
                            const end = buffer.indexOf(jpegEnd, start + jpegStart.length);
                            if (end < 0)
                                break;
                            if (end + 2 - start > maxJpegBytes)
                                throw Error('Camera frame too large');
                            frame = { jpeg: Buffer.from(buffer.subarray(start, end + 2)), receivedAt: Date.now() };
                            if (viewers.size) {
                                const packet = Buffer.allocUnsafe(4 + frame.jpeg.length);
                                packet.writeUInt32BE(frame.jpeg.length);
                                frame.jpeg.copy(packet, 4);
                                for (const viewer of viewers) {
                                    if (!viewer.writableNeedDrain)
                                        viewer.write(packet);
                                }
                            }
                            buffer = buffer.subarray(end + 2);
                            start = buffer.indexOf(jpegStart);
                        }
                        if (buffer.length > maxJpegBytes)
                            throw Error('Camera frame too large');
                        buffer = start >= 0 ? buffer.subarray(start) : buffer.subarray(-1);
                    }
                }
                finally {
                    await reader.cancel().catch(() => {});
                }
            })().catch(() => {}).finally(() => {
                clearTimeout(watchdog);
                stream = undefined;
                frame = undefined;
                for (const viewer of viewers)
                    viewer.end();
            });
        }
        if (!viewers.size)
            idle = setTimeout(() => stream?.abort(), 5000);
        return frame && Date.now() - frame.receivedAt <= 1500 ? frame : undefined;
    }

    const profileExists = (studentId: string) => existsSync(resolve(root, '.work/face-profiles', studentId + '-v1.npy'));
    const readMeta = (studentId: string) => {
        try {
            const p = resolve(root, '.work/face-profiles', studentId + '-meta.json');
            if (existsSync(p))
                return JSON.parse(readFileSync(p, 'utf8'));
        }
        catch {}
        return null;
    };

    function attachVideoFeed(res: Response) {
        if (!camera)
            reject(503, 'FACE_PILOT_DISABLED', 'Thử nghiệm camera chưa được bật.');
        if (viewers.size >= 4)
            reject(429, 'FACE_VIDEO_BUSY', 'Camera đã có đủ phiên xem.');
        viewers.add(res);
        res.on('close', () => {
            viewers.delete(res);
            if (!viewers.size && stream) {
                clearTimeout(idle);
                idle = setTimeout(() => stream?.abort(), 5000);
            }
        });
        res.type('application/octet-stream').flushHeaders();
        requestLiveFrame();
    }

    async function executeFaceAction(studentId: string, action: 'enroll' | 'verify' | 'erase', consent: boolean) {
        const studentRes = await pool.query('SELECT s.id, s.student_code, u.name FROM campus.students s JOIN campus.users u ON u.id=s.user_id WHERE s.id=$1', [studentId]);
        const student = studentRes.rows[0];
        if (!student)
            reject(404, 'STUDENT_NOT_FOUND', 'Không tìm thấy hồ sơ sinh viên.');
        if (action === 'enroll' && !consent)
            reject(422, 'FACE_CONSENT_REQUIRED', 'Cần xác nhận đồng ý trước khi chụp mẫu.');
        if (action === 'enroll' && profileExists(studentId))
            reject(409, 'FACE_ALREADY_ENROLLED', 'Sinh viên đã có mẫu. Hãy xóa mẫu cũ trước khi đăng ký lại.');
        if (action === 'verify' && !profileExists(studentId))
            reject(422, 'FACE_NOT_ENROLLED', 'Cần đăng ký mẫu khuôn mặt trước.');
        if (busy)
            reject(409, 'FACE_PILOT_BUSY', 'Camera đang xử lý yêu cầu khác. Vui lòng thử lại.');
        const current = action !== 'erase' ? requestLiveFrame() : undefined;
        if (action !== 'erase' && !current)
            reject(503, 'FACE_FRAME_WAITING', 'Đang chờ ảnh trực tiếp từ camera.');
        busy = true;
        try {
            const args = [
                script,
                action,
                '--student-id', studentId,
                '--student-code', student.student_code,
                '--name', student.name,
            ];
            if (action !== 'erase')
                args.splice(2, 0, '-');
            if (action === 'enroll')
                args.push('--consent');
            const stdout = await new Promise<string>((res, rej) => {
                const child = execFile('python', args, { cwd: root, timeout: 12000, maxBuffer: 8192, windowsHide: true }, (error, out, stderr) => {
                    if (error)
                        rej(Object.assign(error, { stderr }));
                    else
                        res(out);
                });
                child.stdin?.on('error', () => {});
                child.stdin?.end(current?.jpeg);
            });
            const result = JSON.parse(stdout);
            if (action === 'enroll') {
                const consentRes = await pool.query(
                    "INSERT INTO campus.biometric_consents(id,student_id,purpose,policy_version,source) VALUES($1,$2,'PARKING','camera-s3-v1','REAL') ON CONFLICT DO NOTHING RETURNING id",
                    [id(), studentId]
                );
                const consentId = consentRes.rows[0]?.id ?? (await pool.query("SELECT id FROM campus.biometric_consents WHERE student_id=$1 AND purpose='PARKING' AND revoked_at IS NULL ORDER BY granted_at DESC LIMIT 1", [studentId])).rows[0]?.id;
                if (consentId) {
                    await pool.query(
                        "INSERT INTO campus.biometric_profiles(id,student_id,consent_id,purpose,source,model_version,status) VALUES($1,$2,$3,'PARKING','REAL','sface-2021dec','ACTIVE')",
                        [id(), studentId, consentId]
                    );
                }
            } else if (action === 'erase') {
                await pool.query(
                    "UPDATE campus.biometric_profiles SET status='ERASED', erased_at=now() WHERE student_id=$1 AND status='ACTIVE'",
                    [studentId]
                );
            }
            return {
                ...result,
                studentId: student.id,
                studentCode: student.student_code,
                studentName: student.name,
            };
        }
        catch (error) {
            const stderr = (error as { stderr?: string }).stderr ?? '';
            if (stderr.includes('Exactly one face') || stderr.includes('Face is too small'))
                reject(422, 'FACE_FRAME_REJECTED', 'Đứng gần camera, đủ sáng và chỉ để một khuôn mặt trong khung.');
            reject(503, 'FACE_PILOT_FAILED', 'Không xử lý được ảnh. Kiểm tra kết nối camera rồi thử lại.');
        }
        finally {
            busy = false;
        }
    }

    // Student self-service routes
    app.get('/api/v1/me/face-pilot', handler(async (_req, res) => {
        const actor = res.locals.actor as Actor;
        requireRole(actor, 'STUDENT');
        const studentId = actor.studentId!;
        const meta = readMeta(studentId);
        const studentRes = await pool.query('SELECT s.student_code, u.name FROM campus.students s JOIN campus.users u ON u.id=s.user_id WHERE s.id=$1', [studentId]);
        const student = studentRes.rows[0];
        if (!student)
            reject(404, 'STUDENT_NOT_FOUND', 'Không tìm thấy hồ sơ sinh viên.');
        send(res, {
            data: {
                enabled: !!camera,
                enrolled: !!camera && profileExists(studentId),
                studentCode: student.student_code,
                studentName: student.name,
                metadata: meta,
            }
        });
    }));

    app.get('/api/v1/me/face-pilot/video', handler(async (_req, res) => {
        requireRole(res.locals.actor as Actor, 'STUDENT');
        attachVideoFeed(res);
    }));

    app.post('/api/v1/me/face-pilot', handler(async (req, res) => {
        const actor = res.locals.actor as Actor;
        requireRole(actor, 'STUDENT');
        if (!camera)
            reject(503, 'FACE_PILOT_DISABLED', 'Thử nghiệm camera chưa được bật.');
        const b = fields(req.body, ['action', 'consent'], ['action']);
        const action = choice(b.action, ['enroll', 'verify', 'erase'] as const);
        const data = await executeFaceAction(actor.studentId!, action, b.consent === true);
        send(res, { data });
    }));

    // Admin face management routes
    app.get('/api/v1/admin/face-profiles', handler(async (_req, res) => {
        requireRole(res.locals.actor as Actor, 'ADMIN');
        const students = (await pool.query(
            `SELECT DISTINCT ON (s.id) s.id AS "studentId", s.student_code AS "studentCode", u.name AS "studentName", u.email, u.id AS "userId",
                    bp.id AS "profileId", bp.status, bp.source, bp.model_version AS "modelVersion", bp.created_at AS "createdAt"
             FROM campus.students s
             JOIN campus.users u ON u.id=s.user_id
             LEFT JOIN campus.biometric_profiles bp ON bp.student_id=s.id AND bp.status='ACTIVE' AND bp.purpose='PARKING'
             ORDER BY s.id, s.student_code`
        )).rows;
        const data = students.map(s => {
            const meta = readMeta(s.studentId);
            const exists = profileExists(s.studentId);
            return {
                ...s,
                enrolled: exists,
                enrolledAt: meta?.enrolledAt ?? s.createdAt,
                model: meta?.model ?? s.modelVersion ?? (exists ? 'SFace' : null),
            };
        });
        send(res, { data });
    }));

    app.get('/api/v1/admin/face-pilot/video', handler(async (_req, res) => {
        requireRole(res.locals.actor as Actor, 'ADMIN');
        attachVideoFeed(res);
    }));

    app.post('/api/v1/admin/face-pilot', handler(async (req, res) => {
        requireRole(res.locals.actor as Actor, 'ADMIN');
        if (!camera)
            reject(503, 'FACE_PILOT_DISABLED', 'Thử nghiệm camera chưa được bật.');
        const b = fields(req.body, ['studentId', 'action', 'consent'], ['studentId', 'action']);
        const action = choice(b.action, ['enroll', 'verify', 'erase'] as const);
        const data = await executeFaceAction(uuid(b.studentId), action, b.consent === true);
        send(res, { data });
    }));
}
