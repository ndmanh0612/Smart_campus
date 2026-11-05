import { audit, emit, fields, hash, id, integer, notify, one, optional, points, reject, requirePermission, str, type Actor, type Db, type Result } from './platform.ts';
import { checkPin } from './auth.ts';
import { hasFaceProfile } from './devices.ts';
export async function balance(db: Db, studentId: string, lock = false) {
    // Lock first: a joined balance fetched before waiting can keep an obsolete READ COMMITTED snapshot.
    if (lock)
        await one(db, 'SELECT id FROM wallets WHERE student_id=$1 FOR UPDATE', [studentId]);
    const w = await one(db, "SELECT w.*,a.balance_points,coalesce((SELECT sum(h.amount_points) FROM wallet_holds h WHERE h.wallet_id=w.id AND h.status='ACTIVE'),0)::text AS held FROM wallets w JOIN ledger_accounts a ON a.id=w.account_id WHERE w.student_id=$1", [studentId]);
    return { walletId: w.id, postedPoints: w.balance_points as string, heldPoints: w.held as string, availablePoints: (BigInt(w.balance_points) - BigInt(w.held)).toString(), status: w.status };
}
export async function post(db: Db, type: string, studentId: string, amount: string, source: {
    payment?: string;
    topup?: string;
    original?: string;
    refund?: string;
    adjustment?: string;
}) {
    const txId = id();
    await db.query('SELECT post_wallet($1,$2,$3,$4,$5,$6,$7,$8,$9)', [txId, type, studentId, amount, source.payment ?? null, source.topup ?? null, source.original ?? null, source.refund ?? null, source.adjustment ?? null]);
    await notify(db, studentId, 'wallet.changed', `Ví vừa có giao dịch ${type}: ${amount} point.`, txId);
    return txId;
}
export async function topup(db: Db, a: Actor, body: unknown) {
    const b = fields(body, ['requestedVnd']);
    const amount = points(b.requestedVnd, 10000000n);
    if (!a.studentId)
        reject(403, 'STUDENT_REQUIRED', 'Chỉ sinh viên được nạp ví cá nhân.');
    const wallet = await balance(db, a.studentId!);
    if (wallet.status !== 'ACTIVE')
        reject(422, 'WALLET_FROZEN', 'Ví đang bị khóa.');
    const conversion = await one(db, 'SELECT * FROM point_conversion_policies WHERE active');
    const amountPoints = (BigInt(amount) * BigInt(conversion.points_per_vnd)).toString();
    const orderId = id();
    await db.query("INSERT INTO topup_orders(id,wallet_id,requested_vnd,amount_points,conversion_version,status,provider,expires_at) VALUES($1,$2,$3,$4,$5,'PENDING','MOCK',now()+interval '15 minutes')", [orderId, wallet.walletId, amount, amountPoints, conversion.version]);
    await emit(db, 'mock.topup.requested', orderId);
    await audit(db, a, 'TOPUP_REQUESTED', orderId, undefined, { provider: 'MOCK', amountPoints });
    return { id: orderId, status: 'PENDING', mock: true, amountPoints, message: 'Nạp point mô phỏng — không phải tiền thật.' };
}
export async function callback(db: Db, body: unknown) {
    const b = fields(body, ['callbackId', 'topupId', 'amountPoints', 'status']);
    const callbackId = str(b.callbackId, 128), topupId = str(b.topupId, 36), amount = points(b.amountPoints);
    const status = str(b.status, 20);
    if (!['SUCCEEDED', 'FAILED'].includes(status))
        reject(400, 'INVALID_CALLBACK', 'Trạng thái callback không hợp lệ.');
    await db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))', ['callback:' + callbackId]);
    const digest = hash(JSON.stringify({ topupId, amount, status }));
    const prior = await optional(db, 'SELECT * FROM payment_callbacks WHERE provider_event_id=$1', [callbackId]);
    if (prior) {
        if (prior.payload_hash !== digest)
            reject(409, 'CALLBACK_CONFLICT', 'Callback bị thay đổi nội dung.');
        return { status: prior.processing_result, mock: true };
    }
    const order = await one(db, 'SELECT t.*,w.student_id FROM topup_orders t JOIN wallets w ON w.id=t.wallet_id WHERE t.id=$1 FOR UPDATE OF t', [topupId]);
    if (order.amount_points !== amount)
        reject(422, 'CALLBACK_AMOUNT_MISMATCH', 'Số point callback không khớp yêu cầu.');
    let outcome = order.status;
    if (order.status === 'PENDING') {
        if (new Date(order.expires_at) < new Date())
            outcome = 'REVIEW_REQUIRED';
        else if (status === 'FAILED')
            outcome = 'FAILED';
        else {
            await post(db, 'TOP_UP', order.student_id, amount, { topup: order.id });
            outcome = 'SUCCEEDED';
        }
        await db.query('UPDATE topup_orders SET status=$2 WHERE id=$1', [order.id, outcome]);
    }
    else if (['EXPIRED', 'CANCELLED'].includes(order.status)) {
        outcome = 'REVIEW_REQUIRED';
        await db.query("UPDATE topup_orders SET status='REVIEW_REQUIRED' WHERE id=$1", [order.id]);
    }
    await db.query('INSERT INTO payment_callbacks(id,provider_event_id,topup_order_id,payload_hash,processing_result) VALUES($1,$2,$3,$4,$5)', [id(), callbackId, order.id, digest, outcome]);
    await audit(db, null, 'MOCK_CALLBACK', order.id, undefined, { outcome });
    return { status: outcome, mock: true };
}
export async function paymentSource(db: Db, paymentId: string) {
    const reference = await one(db, 'SELECT order_id,parking_session_id FROM payments WHERE id=$1', [paymentId]);
    const source = reference.order_id ? await one(db, 'SELECT * FROM orders WHERE id=$1 FOR UPDATE', [reference.order_id]) : await one(db, 'SELECT * FROM parking_sessions WHERE id=$1 FOR UPDATE', [reference.parking_session_id]);
    const p = await one(db, 'SELECT * FROM payments WHERE id=$1 FOR UPDATE', [paymentId]);
    return { p, source };
}
async function identityStillValid(db: Db, p: Record<string, any>) {
    const student = await one(db, 'SELECT s.active,u.status FROM students s JOIN users u ON u.id=s.user_id WHERE s.id=$1', [p.student_id]);
    if (!student.active || student.status !== 'ACTIVE')
        reject(422, 'STUDENT_INACTIVE', 'Tài khoản sinh viên không còn hiệu lực.');
    const identity = await one(db, 'SELECT * FROM identity_assertions WHERE id=$1', [p.identity_assertion_id]);
    if (identity.card_id && !await optional(db, "SELECT id FROM rfid_cards WHERE id=$1 AND status='ACTIVE' AND (expires_at IS NULL OR expires_at>now())", [identity.card_id]))
        reject(422, 'CARD_NOT_ACTIVE', 'Thẻ đã bị khóa hoặc hết hiệu lực.');
    if (!identity.card_id && !identity.credential_hmac) {
        const purpose = p.order_id ? 'CANTEEN' : 'PARKING';
        if (!await hasFaceProfile(db, p.student_id, purpose, identity.source))
            reject(422, 'CONSENT_REQUIRED', 'Đồng ý nhận diện đã bị thu hồi.');
    }
}
export async function approve(db: Db, a: Actor, paymentId: string, body: unknown): Promise<Result> {
    const b = fields(body, ['pin', 'expectedSourceVersion']);
    const { p, source } = await paymentSource(db, paymentId);
    if (p.student_id !== a.studentId)
        reject(403, 'FORBIDDEN', 'Bạn không được xác nhận giao dịch của người khác.');
    if (p.status !== 'AWAITING_CONFIRMATION')
        reject(409, 'PAYMENT_STATE', 'Giao dịch không còn chờ xác nhận.');
    if (source.version !== integer(b.expectedSourceVersion))
        reject(409, 'VERSION_CONFLICT', 'Nội dung thanh toán đã thay đổi.');
    if (p.order_id && new Date(source.expires_at) < new Date())
        reject(422, 'RESERVATION_EXPIRED', 'Đơn đã hết thời gian thanh toán.');
    if (p.quote_id) {
        const q = await one(db, 'SELECT * FROM parking_quotes WHERE id=$1', [p.quote_id]);
        if (new Date(q.expires_at) < new Date())
            reject(422, 'QUOTE_EXPIRED', 'Báo giá đã hết hạn.');
    }
    await identityStillValid(db, p);
    const pinError = await checkPin(db, a, b.pin);
    if (pinError)
        return pinError;
    const security = await one(db, 'SELECT pin_version FROM wallet_security_settings WHERE student_id=$1', [a.studentId]);
    const approvalId = id();
    await db.query("INSERT INTO payment_approvals(id,payment_id,student_id,amount_points,source_version,pin_version,expires_at) VALUES($1,$2,$3,$4,$5,$6,now()+interval '2 minutes') ON CONFLICT(payment_id) DO UPDATE SET id=EXCLUDED.id,source_version=EXCLUDED.source_version,pin_version=EXCLUDED.pin_version,expires_at=EXCLUDED.expires_at,consumed_at=NULL", [approvalId, p.id, a.studentId, p.amount_points, source.version, security.pin_version]);
    await audit(db, a, 'PAYMENT_APPROVED', p.id);
    await emit(db, p.order_id ? 'canteen.order.changed' : 'parking.session.changed', p.order_id ?? p.parking_session_id, { paymentId: p.id, status: 'APPROVED' });
    return { data: { approvalId, paymentId: p.id, amountPoints: p.amount_points, expiresIn: 120 } };
}
export async function authorize(db: Db, p: Record<string, any>, sourceVersion: number, approvalId: string) {
    if (p.status !== 'AWAITING_CONFIRMATION')
        reject(409, 'PAYMENT_STATE', 'Giao dịch không còn chờ thanh toán.');
    const approval = await one(db, `SELECT a.*,s.pin_version AS current_pin_version FROM payment_approvals a JOIN wallet_security_settings s ON s.student_id=a.student_id WHERE a.id=$1 AND a.payment_id=$2 FOR UPDATE OF a`, [approvalId, p.id]);
    if (approval.consumed_at || new Date(approval.expires_at) < new Date() || approval.source_version !== sourceVersion || approval.pin_version !== approval.current_pin_version || approval.amount_points !== p.amount_points)
        reject(422, 'APPROVAL_EXPIRED', 'Xác nhận hết hiệu lực hoặc nội dung đã thay đổi.');
    await identityStillValid(db, p);
    const wallet = await balance(db, p.student_id, true);
    if (wallet.status !== 'ACTIVE')
        reject(422, 'WALLET_FROZEN', 'Ví đang bị khóa.');
    const amount = BigInt(p.amount_points);
    const limits = (await one(db, "SELECT value FROM system_settings WHERE key='wallet_limits'")).value;
    if (amount > BigInt(limits.transactionPoints))
        reject(422, 'TRANSACTION_LIMIT', 'Vượt hạn mức point/giao dịch thử nghiệm.');
    if (BigInt(wallet.availablePoints) < amount)
        reject(422, 'INSUFFICIENT_POINTS', 'Ví chưa đủ point.', { requiredPoints: p.amount_points, availablePoints: wallet.availablePoints, shortfallPoints: (amount - BigInt(wallet.availablePoints)).toString() });
    const daily = await optional(db, "SELECT charged_points FROM wallet_daily_usage WHERE wallet_id=$1 AND business_date=(now() AT TIME ZONE 'Asia/Ho_Chi_Minh')::date", [wallet.walletId]);
    if (BigInt(daily?.charged_points ?? 0) + BigInt(wallet.heldPoints) + amount > BigInt(limits.dailyPoints))
        reject(422, 'DAILY_LIMIT', 'Vượt hạn mức point trong ngày thử nghiệm.');
    await db.query('UPDATE payment_approvals SET consumed_at=now() WHERE id=$1', [approvalId]);
    await db.query("INSERT INTO wallet_holds(id,wallet_id,payment_id,amount_points,status) VALUES($1,$2,$3,$4,'ACTIVE')", [id(), wallet.walletId, p.id, p.amount_points]);
    await db.query("UPDATE payments SET status='AUTHORIZED' WHERE id=$1", [p.id]);
}
export async function capture(db: Db, p: Record<string, any>) {
    if (p.status === 'CAPTURED')
        return one(db, 'SELECT id FROM wallet_transactions WHERE payment_id=$1', [p.id]);
    if (p.status !== 'AUTHORIZED')
        reject(409, 'PAYMENT_STATE', 'Giao dịch chưa được giữ point.');
    await db.query("UPDATE wallet_holds SET status='CAPTURED' WHERE payment_id=$1 AND status='ACTIVE'", [p.id]);
    const txId = await post(db, p.order_id ? 'CANTEEN_PAYMENT' : 'PARKING_PAYMENT', p.student_id, p.amount_points, { payment: p.id });
    await db.query("UPDATE payments SET status='CAPTURED' WHERE id=$1", [p.id]);
    await db.query("INSERT INTO wallet_daily_usage(wallet_id,business_date,charged_points) SELECT id,(now() AT TIME ZONE 'Asia/Ho_Chi_Minh')::date,$2 FROM wallets WHERE student_id=$1 ON CONFLICT(wallet_id,business_date) DO UPDATE SET charged_points=wallet_daily_usage.charged_points+EXCLUDED.charged_points", [p.student_id, p.amount_points]);
    return { id: txId };
}
export async function voidPayment(db: Db, paymentId: string) { await db.query("UPDATE wallet_holds SET status='RELEASED' WHERE payment_id=$1 AND status='ACTIVE'", [paymentId]); await db.query("UPDATE payments SET status='VOIDED' WHERE id=$1 AND status IN('AUTHORIZED','AWAITING_CONFIRMATION')", [paymentId]); }
export async function refund(db: Db, a: Actor, body: unknown) {
    const b = fields(body, ['originalTransactionId', 'amountPoints', 'reason', 'restock'], ['originalTransactionId', 'amountPoints', 'reason']);
    const amount = points(b.amountPoints), reason = str(b.reason, 1000, 5);
    const ref = await one(db, 'SELECT t.*,p.order_id,p.parking_session_id FROM wallet_transactions t JOIN payments p ON p.id=t.payment_id WHERE t.id=$1', [b.originalTransactionId]);
    requirePermission(a, ref.type === 'CANTEEN_PAYMENT' ? 'canteen.refund' : 'parking.exception.resolve');
    if (ref.order_id)
        await one(db, 'SELECT id FROM orders WHERE id=$1 FOR UPDATE', [ref.order_id]);
    else
        await one(db, 'SELECT id FROM parking_sessions WHERE id=$1 FOR UPDATE', [ref.parking_session_id]);
    await db.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))', ['refund:' + ref.id]);
    if (ref.type === 'PARKING_PAYMENT')
        reject(422, 'USE_PARKING_RESOLUTION', 'Hoàn phí xe cần xác minh qua luồng xử lý ngoại lệ.');
    const already = await one(db, 'SELECT coalesce(sum(amount_points),0)::text AS total FROM refunds WHERE original_transaction_id=$1', [ref.id]);
    if (BigInt(already.total) + BigInt(amount) > BigInt(ref.amount_points))
        reject(422, 'REFUND_EXCEEDS_ORIGINAL', 'Tổng hoàn vượt số point đã thu.');
    if (b.restock === true && (amount !== ref.amount_points || already.total !== '0'))
        reject(422, 'RESTOCK_REQUIRES_FULL_REFUND', 'Chỉ hoàn kho toàn đơn khi hoàn toàn bộ lần đầu và thực nhận hàng trả.');
    const refundId = id();
    await db.query('INSERT INTO refunds(id,original_transaction_id,amount_points,reason,actor_id,restock) VALUES($1,$2,$3,$4,$5,$6)', [refundId, ref.id, amount, reason, a.id, b.restock === true]);
    if (b.restock === true) {
        const items = (await db.query('SELECT * FROM order_items WHERE order_id=$1 ORDER BY product_id', [ref.order_id])).rows;
        for (const item of items) {
            await db.query('UPDATE inventory SET on_hand=on_hand+$2 WHERE product_id=$1', [item.product_id, item.quantity]);
            await db.query("INSERT INTO inventory_movements(id,product_id,refund_id,kind,quantity_delta,reason) VALUES($1,$2,$3,'RETURN',$4,$5)", [id(), item.product_id, refundId, item.quantity, reason]);
            await db.query('INSERT INTO refund_items VALUES($1,$2,$3)', [refundId, item.id, item.quantity]);
        }
    }
    const txId = await post(db, 'REFUND', ref.student_id, amount, { original: ref.id, refund: refundId });
    await audit(db, a, 'CANTEEN_REFUND', refundId, reason);
    return { id: refundId, transactionId: txId, amountPoints: amount };
}
