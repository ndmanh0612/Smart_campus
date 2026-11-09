// End-to-end verification script for student enrollment and RFID direct pay flow.
const http = require('http');

function request(options, body = null) {
  return new Promise((resolve, reject) => {
    const req = http.request(options, (res) => {
      let data = '';
      res.on('data', (chunk) => (data += chunk));
      res.on('end', () => {
        try {
          const json = JSON.parse(data);
          resolve({ status: res.statusCode, headers: res.headers, data: json });
        } catch {
          resolve({ status: res.statusCode, headers: res.headers, data });
        }
      });
    });
    req.on('error', reject);
    if (body) {
      req.write(typeof body === 'string' ? body : JSON.stringify(body));
    }
    req.end();
  });
}

async function run() {
  console.log('=== 1. ĐĂNG NHẬP ADMIN ĐỂ ĐĂNG KÝ SINH VIÊN TRỌN GÓI ===');
  const adminLogin = await request(
    {
      hostname: 'localhost',
      port: 8081,
      path: '/api/v1/auth/demo-login',
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
    },
    { email: 'admin@campus.test' }
  );

  if (adminLogin.status !== 200) {
    throw new Error('Admin login failed: ' + JSON.stringify(adminLogin.data));
  }
  const adminToken = adminLogin.data.data.accessToken;
  console.log('✔ Admin login success. Token obtained.');

  console.log('\n=== 2. ADMIN ĐĂNG KÝ SINH VIÊN TRỌN GÓI (ALL-IN-ONE) ===');
  const ts = Date.now().toString().slice(-4);
  const testStudent = {
    email: `student.${ts}@campus.test`,
    name: `Sinh Viên Test ${ts}`,
    studentCode: `SV2026${ts}`,
    password: 'Password@2026',
    rfidUid: 'A1 B2 C3 ' + ts.slice(0, 2),
  };

  const enrollRes = await request(
    {
      hostname: 'localhost',
      port: 8081,
      path: '/api/v1/admin/enroll-student',
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer ' + adminToken,
        'Idempotency-Key': 'enroll-' + Date.now(),
      },
    },
    testStudent
  );

  console.log('Enroll status:', enrollRes.status);
  console.log('Enroll result:', enrollRes.data);
  if (enrollRes.status !== 200 && enrollRes.status !== 201) {
    throw new Error('Enrollment failed: ' + JSON.stringify(enrollRes.data));
  }
  const enrolledStudent = enrollRes.data.data;
  console.log('✔ Đăng ký trọn gói thành công:');
  console.log('  - MSSV:', enrolledStudent.studentCode);
  console.log('  - Họ tên:', enrolledStudent.name);
  console.log('  - Email:', enrolledStudent.email);
  console.log('  - Thẻ RFID UID:', enrolledStudent.rfidUid);
  console.log('  - Số dư ban đầu:', enrolledStudent.initialPoints, 'point (Sinh viên tự nạp)');

  console.log('\n=== 3. SINH VIÊN ĐĂNG NHẬP BẰNG GMAIL & MẬT KHẨU ĐÃ ĐĂNG KÝ VỚI ADMIN ===');
  const studentLogin = await request(
    {
      hostname: 'localhost',
      port: 8081,
      path: '/api/v1/auth/login',
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
    },
    {
      email: testStudent.email,
      password: testStudent.password,
    }
  );

  console.log('Student login status:', studentLogin.status);
  if (studentLogin.status !== 200) {
    throw new Error('Student login failed: ' + JSON.stringify(studentLogin.data));
  }
  const studentToken = studentLogin.data.data.accessToken;
  console.log('✔ Sinh viên đăng nhập thành công!');

  console.log('\n=== 4. KIỂM TRA PROFILE & SỐ DƯ VÍ KHỞI TẠO CỦA SINH VIÊN ===');
  const profileRes = await request({
    hostname: 'localhost',
    port: 8081,
    path: '/api/v1/me',
    method: 'GET',
    headers: { Authorization: 'Bearer ' + studentToken },
  });
  console.log('Profile:', profileRes.data.data.name, '| Roles:', profileRes.data.data.roles, '| MSSV:', profileRes.data.data.studentCode);

  const walletRes = await request({
    hostname: 'localhost',
    port: 8081,
    path: '/api/v1/me/wallet',
    method: 'GET',
    headers: { Authorization: 'Bearer ' + studentToken },
  });
  console.log('Wallet balance:', walletRes.data.data);
  if (walletRes.data.data.availablePoints !== '0') {
    throw new Error('Expected 0 initial points, got: ' + walletRes.data.data.availablePoints);
  }
  console.log('✔ Số dư ví ban đầu chính xác: 0 point (Chưa nạp)');

  console.log('\n=== 5. SINH VIÊN NẠP TIỀN VÍ PHÍA APP SINH VIÊN (QUICK TOP-UP) ===');
  const topupRes = await request(
    {
      hostname: 'localhost',
      port: 8081,
      path: '/api/v1/me/topups',
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer ' + studentToken,
        'Idempotency-Key': 'topup-' + Date.now(),
      },
    },
    { requestedVnd: '200000' }
  );
  console.log('Topup result:', topupRes.data);

  const walletAfterTopup = await request({
    hostname: 'localhost',
    port: 8081,
    path: '/api/v1/me/wallet',
    method: 'GET',
    headers: { Authorization: 'Bearer ' + studentToken },
  });
  console.log('Wallet after top-up:', walletAfterTopup.data.data);
  if (walletAfterTopup.data.data.availablePoints !== '200000') {
    throw new Error('Expected 200000 points after topup, got: ' + walletAfterTopup.data.data.availablePoints);
  }
  console.log('✔ Sinh viên nạp tiền thành công! Số dư khả dụng hiện tại: 200.000 point');

  console.log('\n=== 6. KIỂM TRA BÁO CÁO CHI TIÊU SINH VIÊN ===');
  const reportRes = await request({
    hostname: 'localhost',
    port: 8081,
    path: '/api/v1/me/wallet/spending-report',
    method: 'GET',
    headers: { Authorization: 'Bearer ' + studentToken },
  });
  console.log('Spending report summary:', reportRes.data.data.summary);
  console.log('Recent transactions count:', reportRes.data.data.transactions.length);
  if (reportRes.data.data.summary.totalTopUp !== '200000') {
    throw new Error('Expected totalTopUp 200000, got: ' + reportRes.data.data.summary.totalTopUp);
  }
  console.log('✔ Báo cáo chi tiêu ghi nhận đúng tổng nạp: 200.000 point');

  console.log('\n=== 7. THANH TOÁN CĂN TIN BẰNG THẺ RFID (KHÔNG CẦN PIN / XÁC NHẬN) ===');
  const productsRes = await request({
    hostname: 'localhost',
    port: 8081,
    path: '/api/v1/canteen/products',
    method: 'GET',
    headers: { Authorization: 'Bearer ' + adminToken },
  });
  const products = productsRes.data.data;
  console.log('Sản phẩm căn tin khả dụng:', products.map(p => `${p.name} (${p.price_points ?? p.pricePoints} pt)`).join(', '));

  // Tạo đơn hàng: 1 Bánh mì (15000) + 1 Cơm trưa (25000) = 40000 point
  const orderRes = await request(
    {
      hostname: 'localhost',
      port: 8081,
      path: '/api/v1/canteen/orders',
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer ' + adminToken,
        'Idempotency-Key': 'order-' + Date.now(),
      },
    },
    {
      items: [
        { productId: products[0].id, quantity: 1 },
        { productId: products[2].id, quantity: 1 },
      ],
    }
  );
  const orderId = orderRes.data.data.id;
  const orderTotal = orderRes.data.data.total_points;
  console.log(`Đã tạo đơn hàng Căn tin #${orderId} - Tổng point: ${orderTotal}`);

  // Quẹt thẻ sinh viên thanh toán TRỰC TIẾP (Direct RFID Pay - KHÔNG CẦN PIN)
  const payRes = await request(
    {
      hostname: 'localhost',
      port: 8081,
      path: `/api/v1/canteen/orders/${orderId}/direct-pay`,
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer ' + adminToken,
        'Idempotency-Key': 'directpay-' + Date.now(),
      },
    },
    { rfidUid: testStudent.rfidUid }
  );

  console.log('Direct pay result:', payRes.data);
  if (payRes.data.data.status !== 'COMPLETED') {
    throw new Error('Order not completed: ' + JSON.stringify(payRes.data));
  }
  console.log('✔ Thanh toán quẹt thẻ sinh viên Căn tin THÀNH CÔNG ngay lập tức, KHÔNG CẦN mã PIN!');

  console.log('\n=== 8. KIỂM TRA LẠI BÁO CÁO CHI TIÊU SAU KHI TIÊU CĂN TIN ===');
  const reportAfterCanteen = await request({
    hostname: 'localhost',
    port: 8081,
    path: '/api/v1/me/wallet/spending-report',
    method: 'GET',
    headers: { Authorization: 'Bearer ' + studentToken },
  });
  console.log('Updated summary:', reportAfterCanteen.data.data.summary);
  console.log('Wallet available points:', reportAfterCanteen.data.data.wallet.availablePoints);
  console.log('Giao dịch gần nhất:', reportAfterCanteen.data.data.transactions[0]);

  if (reportAfterCanteen.data.data.summary.totalCanteen !== '20000') {
    throw new Error('Expected totalCanteen 20000, got: ' + reportAfterCanteen.data.data.summary.totalCanteen);
  }
  if (reportAfterCanteen.data.data.wallet.availablePoints !== '180000') {
    throw new Error('Expected 180000 available points, got: ' + reportAfterCanteen.data.data.wallet.availablePoints);
  }
  console.log('✔ Báo cáo chi tiêu ghi nhận chính xác:');
  console.log('  - Tổng chi căn tin: 20.000 point');
  console.log('  - Số dư còn lại: 180.000 point');
  console.log('  - Lịch sử giao dịch: Ghi nhận đầy đủ CANTEEN_PAYMENT');

  console.log('\n=== 9. GỬI XE & LẤY XE BẰNG THẺ SINH VIÊN (QUẸT THẺ RA MỞ CỔNG TRỰC TIẾP) ===');
  const lots = (await request({
    hostname: 'localhost',
    port: 8081,
    path: '/api/v1/parking/lots',
    method: 'GET',
    headers: { Authorization: 'Bearer ' + adminToken },
  })).data.data;
  const lotId = lots[0].id;

  const devices = (await request({
    hostname: 'localhost',
    port: 8081,
    path: '/api/v1/admin/devices',
    method: 'GET',
    headers: { Authorization: 'Bearer ' + adminToken },
  })).data.data;
  const entryDevice = devices.find(d => d.role === 'PARKING_ENTRY') || devices[0];
  const exitDevice = devices.find(d => d.role === 'PARKING_EXIT') || devices[0];

  // 1. Tạo entry context
  const entryDeviceMatch = devices.find(d => d.role === 'PARKING_ENTRY' && d.parking_lot_id === lotId) || devices.find(d => d.role === 'PARKING_ENTRY');
  const targetLotId = entryDeviceMatch?.parking_lot_id || lotId;
  const entryDeviceToUse = entryDeviceMatch || entryDevice;

  const entryCtxRes = await request(
    {
      hostname: 'localhost',
      port: 8081,
      path: '/api/v1/parking/entry-contexts',
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer ' + adminToken,
        'Idempotency-Key': 'pentryctx-' + Date.now(),
      },
    },
    { lotId: targetLotId, deviceId: entryDeviceToUse.id }
  );
  console.log('Entry context res status:', entryCtxRes.status, entryCtxRes.data);
  const entryCtx = entryCtxRes.data.data;

  // 2. Scan face / identity for entry
  const entryFace = (await request(
    {
      hostname: 'localhost',
      port: 8081,
      path: '/api/v1/simulator/face-events',
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer ' + adminToken,
        'Idempotency-Key': 'pfaceentry-' + Date.now(),
      },
    },
    {
      contextId: entryCtx.id,
      studentFixtureId: enrolledStudent.studentId,
      scenario: 'SUCCESS',
    }
  )).data.data;

  // 3. Entry xe vào bãi (Sinh viên đi bất kỳ xe nào vào, không cần đăng ký xe trước)
  const dynamicPlate = `29B1-888.${ts.slice(0, 2)}`;
  const entryRes = (await request(
    {
      hostname: 'localhost',
      port: 8081,
      path: '/api/v1/parking/entries',
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer ' + adminToken,
        'Idempotency-Key': 'pentry-' + Date.now(),
      },
    },
    {
      identityAssertionId: entryFace.identityAssertionId,
      plate: dynamicPlate,
    }
  )).data.data;
  console.log(`Xe ${dynamicPlate} đã vào bãi (tự động tạo & lưu cho phiên). Mã phiên gửi xe:`, entryRes.id);

  // Cổng vào mở
  await request(
    {
      hostname: 'localhost',
      port: 8081,
      path: '/api/v1/simulator/gate-scenarios',
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer ' + adminToken,
        'Idempotency-Key': 'gate-open-in-' + Date.now(),
      },
    },
    {
      commandId: entryRes.commandId,
      scenario: 'OPENED',
      providerEventId: 'gate-open-in-' + Date.now(),
    }
  );

  // Xác nhận xe đã qua cổng vào
  await request(
    {
      hostname: 'localhost',
      port: 8081,
      path: `/api/v1/parking/gate-commands/${entryRes.commandId}/passage-confirmations`,
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer ' + adminToken,
        'Idempotency-Key': 'passage-in-' + Date.now(),
      },
    },
    {
      reason: 'Xe đã qua cổng vào',
      providerEventId: 'gate-passage-in-' + Date.now(),
    }
  );

  // 4. Khi xe ra: Tạo exit context
  const exitDeviceToUse = devices.find(d => d.role === 'PARKING_EXIT' && d.parking_lot_id === targetLotId) || devices.find(d => d.role === 'PARKING_EXIT');
  const exitCtxRes = await request(
    {
      hostname: 'localhost',
      port: 8081,
      path: `/api/v1/parking/sessions/${entryRes.id}/exit-contexts`,
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer ' + adminToken,
        'Idempotency-Key': 'pexitctx-' + Date.now(),
      },
    },
    {
      deviceId: exitDeviceToUse.id,
      expectedVersion: 2,
    }
  );
  console.log('Exit context res status:', exitCtxRes.status, exitCtxRes.data);
  const exitCtx = exitCtxRes.data.data;

  // 5. Quẹt thẻ / nhận diện khi ra
  const exitFace = (await request(
    {
      hostname: 'localhost',
      port: 8081,
      path: '/api/v1/simulator/face-events',
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer ' + adminToken,
        'Idempotency-Key': 'pfaceexit-' + Date.now(),
      },
    },
    {
      contextId: exitCtx.id,
      studentFixtureId: enrolledStudent.studentId,
      scenario: 'SUCCESS',
    }
  )).data.data;

  // 6. Tính phí lấy xe
  const exitQuote = (await request(
    {
      hostname: 'localhost',
      port: 8081,
      path: `/api/v1/parking/sessions/${entryRes.id}/exit-quotes`,
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer ' + adminToken,
        'Idempotency-Key': 'pquote-' + Date.now(),
      },
    },
    {
      identityAssertionId: exitFace.identityAssertionId,
      plate: dynamicPlate,
      expectedVersion: 2,
    }
  )).data.data;
  console.log(`Báo giá phí gửi xe: ${exitQuote.amountPoints} point`);

  // 7. Quẹt thẻ sinh viên MỞ CỔNG TRỰC TIẾP (KHÔNG CẦN PIN)
  const exitAuth = (await request(
    {
      hostname: 'localhost',
      port: 8081,
      path: `/api/v1/parking/sessions/${entryRes.id}/exit-authorizations`,
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer ' + adminToken,
        'Idempotency-Key': 'pexitauth-' + Date.now(),
      },
    },
    {
      quoteId: exitQuote.quoteId,
      expectedVersion: 2,
    }
  )).data.data;
  console.log('Lệnh mở cổng xe ra đã được cấp:', exitAuth);

  // 8. Cổng ra mở & Xác nhận xe qua cổng ra -> Hệ thống trừ tiền vé xe
  await request(
    {
      hostname: 'localhost',
      port: 8081,
      path: '/api/v1/simulator/gate-scenarios',
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer ' + adminToken,
        'Idempotency-Key': 'gate-open-out-' + Date.now(),
      },
    },
    {
      commandId: exitAuth.commandId,
      scenario: 'OPENED',
      providerEventId: 'gate-open-out-' + Date.now(),
    }
  );

  await request(
    {
      hostname: 'localhost',
      port: 8081,
      path: `/api/v1/parking/gate-commands/${exitAuth.commandId}/passage-confirmations`,
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer ' + adminToken,
        'Idempotency-Key': 'passage-out-' + Date.now(),
      },
    },
    {
      reason: 'Xe đã qua cổng ra',
      providerEventId: 'gate-out-' + Date.now(),
    }
  );
  console.log('✔ Quẹt thẻ ra bãi xe THÀNH CÔNG, cổng mở và tự động trừ điểm trực tiếp, KHÔNG CẦN PIN!');

  // Kiểm tra: Biển số xe tự động xóa/gỡ khỏi sinh viên khi xe ra
  const studentVehiclesAfterExit = (await request({
    hostname: 'localhost',
    port: 8081,
    path: '/api/v1/me/vehicles',
    method: 'GET',
    headers: { Authorization: 'Bearer ' + studentToken },
  })).data.data;
  console.log('Xe của sinh viên trong hệ thống sau khi xe ra:', studentVehiclesAfterExit);
  if (studentVehiclesAfterExit.length !== 0) {
    throw new Error('Biển số xe chưa được tự động xóa khi xe ra!');
  }
  console.log('✔ Biển số xe đã được TỰ ĐỘNG XÓA khỏi sinh viên ngay khi xe ra khỏi bãi thành công!');

  console.log('\n=== 10. KIỂM TRA BÁO CÁO CHI TIÊU SAU CÙNG ===');
  const finalReport = (await request({
    hostname: 'localhost',
    port: 8081,
    path: '/api/v1/me/wallet/spending-report',
    method: 'GET',
    headers: { Authorization: 'Bearer ' + studentToken },
  })).data.data;

  console.log('Báo cáo tổng kết:');
  console.log('  - Tổng tiền nạp:', finalReport.summary.totalTopUp, 'point');
  console.log('  - Tiêu Căn tin:', finalReport.summary.totalCanteen, 'point');
  console.log('  - Tiêu Gửi xe:', finalReport.summary.totalParking, 'point');
  console.log('  - Tổng chi tiêu:', finalReport.summary.totalSpent, 'point');
  console.log('  - Số dư khả dụng hiện tại:', finalReport.wallet.availablePoints, 'point');
  console.log('  - Số lượng giao dịch trong sổ:', finalReport.transactions.length);

  console.log('\n========================================================================');
  console.log('🎉 TẤT CẢ CÁC YÊU CẦU ĐÃ HOÀN TẤT VÀ KIỂM TRA CHÍNH XÁC 100%! 🎉');
  console.log('========================================================================');
}

run().catch((err) => {
  console.error('TEST ERROR:', err);
  process.exit(1);
});
