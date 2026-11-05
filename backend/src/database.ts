import { readFile } from 'node:fs/promises';
import { hash, id, passwordHash, transaction, uidHash, type Db } from './platform.ts';
import type { Pool } from 'pg';
export async function migrate(pool: Pool) {
    await transaction(pool, async (db) => {
        await db.query("SELECT pg_advisory_xact_lock(hashtextextended('smartcampus:migrations',0))");
        for (const version of ['002-campus', '003-operational-indexes']) {
            const sql = await readFile(new URL('../../database/migrations/' + version + '.sql', import.meta.url), 'utf8');
            const checksum = hash(sql);
            const found = await db.query("SELECT to_regclass('campus.schema_migrations') AS table_name");
            if (found.rows[0].table_name) {
                const prior = await db.query('SELECT checksum FROM campus.schema_migrations WHERE version=$1', [version]);
                if (prior.rowCount) {
                    if (prior.rows[0].checksum !== checksum)
                        throw Error('Migration checksum changed; add a new migration instead.');
                    continue;
                }
            }
            await db.query(sql);
            await db.query('INSERT INTO campus.schema_migrations(version,checksum) VALUES($1,$2)', [version, checksum]);
        }
    });
}
export async function grantRuntime(pool: Pool) {
    await pool.query("DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='smartcampus_runtime') THEN CREATE ROLE smartcampus_runtime NOLOGIN; END IF; END $$");
    await pool.query(`GRANT USAGE ON SCHEMA campus TO smartcampus_runtime;
    GRANT SELECT,INSERT,UPDATE,DELETE ON ALL TABLES IN SCHEMA campus TO smartcampus_runtime;
    REVOKE INSERT,UPDATE,DELETE ON campus.wallet_transactions,campus.wallet_ledger_entries FROM smartcampus_runtime;
    REVOKE UPDATE,DELETE ON campus.audit_logs,campus.inventory_movements,campus.parking_events,campus.attendance_corrections FROM smartcampus_runtime;
    REVOKE UPDATE,DELETE ON campus.ledger_accounts FROM smartcampus_runtime;
    REVOKE INSERT,UPDATE,DELETE ON campus.schema_migrations FROM smartcampus_runtime;
    REVOKE INSERT,UPDATE,DELETE ON campus.roles,campus.permissions,campus.role_permissions FROM smartcampus_runtime;
    GRANT EXECUTE ON FUNCTION campus.post_wallet(uuid,text,uuid,bigint,uuid,uuid,uuid,uuid,uuid) TO smartcampus_runtime`);
}
export function fixtureId(name: string) { const h = hash('smartcampus-fixture:' + name); return `${h.slice(0, 8)}-${h.slice(8, 12)}-4${h.slice(13, 16)}-a${h.slice(17, 20)}-${h.slice(20, 32)}`; }
export async function seed(pool: Pool, options: {
    password: string;
    pin: string;
    cardKey: string;
    deviceToken: string;
    testUid?: string;
}) {
    if (options.password.length < 12 || !/^\d{6,12}$/.test(options.pin))
        throw Error('Seed password >=12 characters and PIN >=6 digits required.');
    const passHash = await passwordHash(options.password), pinHash = await passwordHash(options.pin);
    return transaction(pool, async (db) => {
        for (const role of ['ADMIN', 'STUDENT', 'LECTURER', 'PARKING_STAFF', 'CANTEEN_STAFF'])
            await db.query('INSERT INTO roles VALUES($1) ON CONFLICT DO NOTHING', [role]);
        const grants: Record<string, string[]> = { ADMIN: ['simulator.use', 'device.configure', 'wallet.adjust', 'parking.exception.resolve', 'parking.fee.waive', 'canteen.refund', 'audit.read'], LECTURER: ['simulator.use'], PARKING_STAFF: ['simulator.use', 'parking.exception.resolve'], CANTEEN_STAFF: ['simulator.use', 'canteen.refund'] };
        for (const [role, list] of Object.entries(grants))
            for (const permission of list) {
                await db.query('INSERT INTO permissions VALUES($1) ON CONFLICT DO NOTHING', [permission]);
                await db.query('INSERT INTO role_permissions VALUES($1,$2) ON CONFLICT DO NOTHING', [role, permission]);
            }
        for (const [name, role, display] of [['admin', 'ADMIN', 'Quản trị thử nghiệm'], ['student', 'STUDENT', 'Sinh viên mẫu 001'], ['student2', 'STUDENT', 'Sinh viên mẫu 002'], ['lecturer', 'LECTURER', 'Giảng viên mẫu'], ['parking', 'PARKING_STAFF', 'Nhân viên bãi xe'], ['canteen', 'CANTEEN_STAFF', 'Nhân viên cantin']]) {
            const userId = fixtureId('user:' + name);
            const created = await db.query("INSERT INTO users(id,email,name,password_hash) VALUES($1,$2,$3,$4) ON CONFLICT DO NOTHING RETURNING id", [userId, `${name}@campus.test`, display, passHash]);
            if (created.rowCount)
                await db.query('INSERT INTO user_roles VALUES($1,$2) ON CONFLICT DO NOTHING', [userId, role]);
            if (role === 'STUDENT') {
                const studentId = fixtureId(name), accountId = fixtureId('account:' + name);
                await db.query('INSERT INTO students(id,user_id,student_code,synthetic) VALUES($1,$2,$3,true) ON CONFLICT DO NOTHING', [studentId, userId, name === 'student' ? 'DEMO001' : 'DEMO002']);
                await db.query("INSERT INTO ledger_accounts(id,kind) VALUES($1,'STUDENT') ON CONFLICT DO NOTHING", [accountId]);
                await db.query('INSERT INTO wallets(id,student_id,account_id) VALUES($1,$2,$3) ON CONFLICT DO NOTHING', [fixtureId('wallet:' + name), studentId, accountId]);
                await db.query('INSERT INTO wallet_security_settings(student_id,pin_hash) VALUES($1,$2) ON CONFLICT DO NOTHING', [studentId, pinHash]);
                for (const purpose of ['PARKING', 'CANTEEN', 'ATTENDANCE']) {
                    const consentId = fixtureId('consent:' + name + purpose);
                    await db.query("INSERT INTO biometric_consents(id,student_id,purpose,policy_version,source) VALUES($1,$2,$3,'fixture-v1','DEMO') ON CONFLICT DO NOTHING", [consentId, studentId, purpose]);
                    await db.query("INSERT INTO biometric_profiles(id,student_id,consent_id,purpose,source,model_version,status) VALUES($1,$2,$3,$4,'DEMO','demo-v1','ACTIVE') ON CONFLICT DO NOTHING", [fixtureId('profile:' + name + purpose), studentId, consentId, purpose]);
                }
            }
            if (role === 'LECTURER')
                await db.query('INSERT INTO lecturers VALUES($1,$2,$3) ON CONFLICT DO NOTHING', [fixtureId('lecturer'), userId, 'GV-DEMO']);
        }
        for (const kind of ['MOCK_SOURCE', 'CANTEEN', 'PARKING', 'ADJUSTMENT'])
            await db.query('INSERT INTO ledger_accounts(id,kind) VALUES($1,$2) ON CONFLICT DO NOTHING', [fixtureId('account:' + kind), kind]);
        await db.query("INSERT INTO point_conversion_policies VALUES('dev-v1',1,true) ON CONFLICT DO NOTHING");
        await db.query("INSERT INTO system_settings(key,value) VALUES('wallet_limits',$1) ON CONFLICT DO NOTHING", [{ transactionPoints: '100000', dailyPoints: '500000' }]);
        const lot = fixtureId('lot'), room = fixtureId('room'), reader = fixtureId('reader'), camera = fixtureId('camera');
        await db.query("INSERT INTO parking_lots VALUES($1,'DEMO','Bãi xe thử nghiệm',100) ON CONFLICT DO NOTHING", [lot]);
        await db.query("INSERT INTO classrooms VALUES($1,'DEMO-A101','Phòng học thử nghiệm') ON CONFLICT DO NOTHING", [room]);
        await db.query("INSERT INTO devices(id,name,kind,token_hash,role,parking_lot_id) VALUES($1,'ESP32 RFID thật','RFID_READER',$2,'RFID_ENROLLMENT',$3) ON CONFLICT DO NOTHING", [reader, hash(options.deviceToken), lot]);
        await db.query("INSERT INTO devices(id,name,kind,role,classroom_id,ack_version) VALUES($1,'Camera điểm danh DEMO','ATTENDANCE_CAMERA','ATTENDANCE_CAMERA',$2,1) ON CONFLICT DO NOTHING", [camera, room]);
        for (const [name, role] of [['demo-entry', 'PARKING_ENTRY'], ['demo-exit', 'PARKING_EXIT'], ['demo-pos', 'CANTEEN_POS']])
            await db.query("INSERT INTO devices(id,name,kind,role,parking_lot_id,ack_version) VALUES($1,$2,'DEMO_TERMINAL',$3,$4,1) ON CONFLICT DO NOTHING", [fixtureId(name), 'Bảng Face DEMO: ' + role, role, lot]);
        await db.query("INSERT INTO device_role_bindings(id,device_id,role,config_version) VALUES($1,$2,'RFID_ENROLLMENT',1) ON CONFLICT DO NOTHING", [fixtureId('reader:binding'), reader]);
        await db.query("INSERT INTO parking_fee_policies(id,lot_id,version,mode,unit_points,active) VALUES($1,$2,'DEMO-VISIT-1','PER_VISIT',3000,true) ON CONFLICT DO NOTHING", [fixtureId('rate'), lot]);
        for (const name of ['student', 'student2']) {
            const vehicle = fixtureId('vehicle:' + name);
            await db.query("INSERT INTO vehicles VALUES($1,$2,$3,'MOTORCYCLE',true) ON CONFLICT DO NOTHING", [vehicle, name === 'student' ? '59A112345' : '59A154321', name === 'student' ? '59-A1 123.45' : '59-A1 543.21']);
            await db.query('INSERT INTO vehicle_authorizations(vehicle_id,student_id) VALUES($1,$2) ON CONFLICT DO NOTHING', [vehicle, fixtureId(name)]);
        }
        if (options.testUid)
            await db.query("INSERT INTO rfid_cards(id,student_id,uid_hmac,status) VALUES($1,$2,$3,'ACTIVE') ON CONFLICT DO NOTHING", [fixtureId('testcard'), fixtureId('student'), uidHash(options.testUid, options.cardKey)]);
        const category = fixtureId('category');
        await db.query("INSERT INTO product_categories VALUES($1,'Đồ ăn và thức uống') ON CONFLICT DO NOTHING", [category]);
        for (const [sku, name, price, stock] of [['DEMO-01', 'Bánh mì', 15000, 30], ['DEMO-02', 'Nước suối', 5000, 50], ['DEMO-03', 'Cơm trưa', 25000, 20]] as const) {
            const product = fixtureId(sku);
            await db.query('INSERT INTO products(id,category_id,sku,name,price_points) VALUES($1,$2,$3,$4,$5) ON CONFLICT DO NOTHING', [product, category, sku, name, price]);
            await db.query('INSERT INTO inventory(product_id,on_hand) VALUES($1,$2) ON CONFLICT DO NOTHING', [product, stock]);
        }
        await academicSeed(db, room, camera);
        return { readerId: reader, cameraId: camera, studentId: fixtureId('student'), lotId: lot };
    });
}
async function academicSeed(db: Db, room: string, _camera: string) {
    const term = fixtureId('term'), course = fixtureId('course'), section = fixtureId('section');
    await db.query("INSERT INTO academic_terms VALUES($1,'DEMO-2026',now()-interval '180 days',now()+interval '180 days') ON CONFLICT DO NOTHING", [term]);
    await db.query("INSERT INTO courses VALUES($1,'AIOT-DEMO','Ứng dụng AIoT thử nghiệm') ON CONFLICT DO NOTHING", [course]);
    await db.query("INSERT INTO class_sections VALUES($1,$2,$3,'AIOT-01') ON CONFLICT DO NOTHING", [section, term, course]);
    await db.query('INSERT INTO teaching_assignments VALUES($1,$2) ON CONFLICT DO NOTHING', [section, fixtureId('lecturer')]);
    for (const name of ['student', 'student2'])
        await db.query('INSERT INTO enrollments VALUES($1,$2) ON CONFLICT DO NOTHING', [section, fixtureId(name)]);
    const day = new Date().toISOString().slice(0, 13);
    await db.query("INSERT INTO schedules VALUES($1,$2,$3,now()-interval '5 minutes',now()+interval '4 hours') ON CONFLICT DO NOTHING", [fixtureId('schedule:' + day), section, room]);
}
