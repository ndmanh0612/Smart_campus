const fs = require('fs');
const path = require('path');

const accessFile = path.resolve(__dirname, '../.work/campus-access.txt');
const accessContent = fs.readFileSync(accessFile, 'utf8');
const passMatch = accessContent.match(/Mật khẩu chung fixture:\s*([^\r\n]+)/);
const password = passMatch ? passMatch[1].trim() : '';

async function testFlow() {
  const base = 'http://localhost:8081/api/v1';

  console.log('1. Logging in as admin...');
  const loginRes = await fetch(`${base}/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: 'admin@campus.test', password })
  });
  const loginData = await loginRes.json();
  if (!loginData.data?.accessToken) {
    throw new Error('Admin login failed: ' + JSON.stringify(loginData));
  }
  const token = loginData.data.accessToken;
  console.log('   Admin logged in successfully!');

  console.log('2. Checking simulator events & identities...');
  const evRes = await fetch(`${base}/simulator/events`, {
    headers: { Authorization: `Bearer ${token}` }
  });
  const evData = await evRes.json();
  console.log('   Identities in events:', evData.data?.identities?.length);

  console.log('3. Simulating physical card tap via /device/raw-tap (as bridge does)...');
  // First get device token
  const localCfg = JSON.parse(fs.readFileSync(path.resolve(__dirname, '../.work/campus-local.json'), 'utf8'));
  const rawTapRes = await fetch(`${base}/device/raw-tap`, {
    method: 'POST',
    headers: { 
      'Content-Type': 'application/json',
      Authorization: `Bearer ${localCfg.deviceToken}`
    },
    body: JSON.stringify({ uid: '132BF813' })
  });
  const rawTapData = await rawTapRes.json();
  console.log('   raw-tap response:', rawTapData);

  console.log('4. Admin polling /admin/latest-tapped-card...');
  const latestRes = await fetch(`${base}/admin/latest-tapped-card`, {
    headers: { Authorization: `Bearer ${token}` }
  });
  const latestData = await latestRes.json();
  console.log('   latest-tapped-card:', latestData.data);
  if (latestData.data?.uid !== '132BF813') {
    throw new Error('Latest tapped card UID did not match!');
  }

  console.log('All checks passed successfully! System is ready for real RFID card.');
}

testFlow().catch(err => {
  console.error(err);
  process.exit(1);
});
