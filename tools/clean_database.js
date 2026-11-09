const { Pool } = require('../backend/node_modules/pg');
const fs = require('fs');
const path = require('path');

const passFile = path.resolve(__dirname, '../.work/rfid-pg.pass');
const pass = fs.existsSync(passFile) ? fs.readFileSync(passFile, 'utf8').trim() : '';
const ownerUrl = `postgresql://rfid_owner:${encodeURIComponent(pass)}@127.0.0.1:54334/smartcampus_local`;

const pool = new Pool({ connectionString: ownerUrl });

async function clean() {
  console.log('Connecting to database as rfid_owner...');

  const client = await pool.connect();
  try {
    await client.query('SET search_path TO campus, public');

    console.log('Truncating operational tables with CASCADE...');

    // Truncate all student and operational activity tables
    await client.query(`
      TRUNCATE TABLE 
        campus.parking_occupancies,
        campus.parking_events,
        campus.parking_quotes,
        campus.parking_payments,
        campus.gate_commands,
        campus.gate_provider_events,
        campus.parking_sessions,
        campus.vehicle_authorizations,
        campus.vehicles,
        campus.order_items,
        campus.orders,
        campus.refund_items,
        campus.refunds,
        campus.inventory_movements,
        campus.inventory_reservations,
        campus.biometric_profiles,
        campus.biometric_consents,
        campus.identity_assertions,
        campus.device_events,
        campus.simulation_events,
        campus.rfid_cards,
        campus.wallet_ledger_entries,
        campus.wallet_transactions,
        campus.wallet_daily_usage,
        campus.wallet_holds,
        campus.wallet_security_settings,
        campus.wallet_adjustments,
        campus.topup_orders,
        campus.wallets,
        campus.enrollments,
        campus.attendance_adjustment_requests,
        campus.attendance_corrections,
        campus.attendance_records,
        campus.attendance_session_roster,
        campus.attendance_sessions,
        campus.auth_sessions,
        campus.notifications,
        campus.audit_logs,
        campus.outbox_events,
        campus.students
      CASCADE;
    `);

    // Reset inventory stock to default
    await client.query('UPDATE campus.inventory SET on_hand = 50');

    // Clean student accounts from user_roles and users, keep system staff
    await client.query("DELETE FROM campus.user_roles WHERE role = 'STUDENT'");
    await client.query("DELETE FROM campus.users WHERE id NOT IN (SELECT user_id FROM campus.user_roles WHERE role IN ('ADMIN', 'PARKING_STAFF', 'CANTEEN_STAFF', 'LECTURER'))");

    console.log('--- Cleaned Database Successfully ---');
    const q2 = await client.query(`
      SELECT 
        (SELECT count(*) FROM campus.users) as remaining_users,
        (SELECT count(*) FROM campus.students) as remaining_students,
        (SELECT count(*) FROM campus.rfid_cards) as remaining_rfid_cards,
        (SELECT count(*) FROM campus.parking_sessions) as remaining_parking_sessions,
        (SELECT count(*) FROM campus.orders) as remaining_orders
    `);
    console.log(q2.rows[0]);

    // List remaining users to verify admin exists
    const users = await client.query('SELECT id, email, name FROM campus.users');
    console.log('Remaining system accounts:');
    users.rows.forEach(u => console.log(` - ${u.email} (${u.name})`));

  } finally {
    client.release();
    await pool.end();
  }

  // Clean face profiles folder in .work/face-profiles
  const faceProfilesDir = path.resolve(__dirname, '../.work/face-profiles');
  if (fs.existsSync(faceProfilesDir)) {
    const files = fs.readdirSync(faceProfilesDir);
    let removed = 0;
    for (const f of files) {
      if (f.endsWith('.json') || f.endsWith('.jpg') || f.endsWith('.png')) {
        fs.unlinkSync(path.join(faceProfilesDir, f));
        removed++;
      }
    }
    console.log(`Cleaned face-profiles directory (${removed} files removed)`);
  }
}

clean().catch(err => {
  console.error('Error cleaning database:', err);
  process.exit(1);
});
