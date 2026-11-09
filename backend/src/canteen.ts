import { audit, expected, fields, id, integer, notify, one, optional, reject, str, uidHash, uuid, type Actor, type Db } from './platform.ts';
import { consumeIdentity } from './devices.ts';
import { authorize, authorizeDirect, capture, voidPayment } from './wallet.ts';
export async function createOrder(db: Db, a: Actor, body: unknown) {
    const b = fields(body, ['items']);
    if (!Array.isArray(b.items) || b.items.length < 1 || b.items.length > 50)
        reject(400, 'INVALID_ITEMS', 'Đơn cần 1–50 mặt hàng.');
    const items = (b.items as unknown[]).map(v => { const i = fields(v, ['productId', 'quantity']); return { productId: uuid(i.productId), quantity: integer(i.quantity, 1, 100) }; }).sort((a, b) => a.productId.localeCompare(b.productId));
    if (new Set(items.map(i => i.productId)).size !== items.length)
        reject(400, 'DUPLICATE_ITEM', 'Gộp số lượng của sản phẩm trùng trước khi gửi.');
    let total = 0n;
    const rows = [];
    for (const item of items) {
        const product = await one(db, 'SELECT p.*,i.on_hand,i.reserved FROM products p JOIN inventory i ON i.product_id=p.id WHERE p.id=$1 FOR UPDATE OF p,i', [item.productId]);
        if (!product.active)
            reject(422, 'PRODUCT_UNAVAILABLE', 'Sản phẩm đã ngừng bán.');
        if (product.on_hand - product.reserved < item.quantity)
            reject(422, 'INSUFFICIENT_STOCK', `Không đủ tồn kho: ${product.name}.`);
        total += BigInt(product.price_points) * BigInt(item.quantity);
        rows.push({ ...item, product });
    }
    const orderId = id();
    await db.query("INSERT INTO orders(id,created_by,status,total_points,expires_at) VALUES($1,$2,'AWAITING_PAYMENT',$3,now()+interval '5 minutes')", [orderId, a.id, total.toString()]);
    for (const row of rows) {
        await db.query('INSERT INTO order_items VALUES($1,$2,$3,$4,$5,$6)', [id(), orderId, row.productId, row.quantity, row.product.price_points, row.product.price_version]);
        await db.query('UPDATE inventory SET reserved=reserved+$2 WHERE product_id=$1', [row.productId, row.quantity]);
        await db.query("INSERT INTO inventory_reservations SELECT $1,$2,$3,'ACTIVE',expires_at FROM orders WHERE id=$1", [orderId, row.productId, row.quantity]);
        await db.query("INSERT INTO inventory_movements(id,product_id,order_id,kind,quantity_delta) VALUES($1,$2,$3,'RESERVE',0)", [id(), row.productId, orderId]);
    }
    await audit(db, a, 'CANTEEN_ORDER_CREATED', orderId);
    return one(db, 'SELECT * FROM orders WHERE id=$1', [orderId]);
}
export async function cancelOrder(db: Db, a: Actor | null, orderId: string, reason: string, expired = false) {
    const order = await one(db, 'SELECT * FROM orders WHERE id=$1 FOR UPDATE', [orderId]);
    if (['CANCELLED', 'EXPIRED'].includes(order.status))
        return order;
    if (order.status !== 'AWAITING_PAYMENT')
        reject(409, 'ORDER_STATE', 'Không thể hủy đơn đã hoàn thành.');
    const reservations = (await db.query("SELECT * FROM inventory_reservations WHERE order_id=$1 AND status='ACTIVE' ORDER BY product_id FOR UPDATE", [orderId])).rows;
    for (const row of reservations) {
        await db.query('UPDATE inventory SET reserved=reserved-$2 WHERE product_id=$1', [row.product_id, row.quantity]);
        await db.query("INSERT INTO inventory_movements(id,product_id,order_id,kind,quantity_delta,reason) VALUES($1,$2,$3,'RELEASE',0,$4)", [id(), row.product_id, orderId, reason]);
    }
    await db.query("UPDATE inventory_reservations SET status='RELEASED' WHERE order_id=$1 AND status='ACTIVE'", [orderId]);
    const payments = (await db.query("SELECT id FROM payments WHERE order_id=$1 AND status IN('AWAITING_CONFIRMATION','AUTHORIZED') ORDER BY id FOR UPDATE", [orderId])).rows;
    for (const p of payments)
        await voidPayment(db, p.id);
    await db.query("UPDATE device_contexts SET status='CANCELLED' WHERE order_id=$1 AND status='OPEN'", [orderId]);
    await db.query('UPDATE orders SET status=$2,version=version+1 WHERE id=$1', [orderId, expired ? 'EXPIRED' : 'CANCELLED']);
    await audit(db, a, expired ? 'CANTEEN_ORDER_EXPIRED' : 'CANTEEN_ORDER_CANCELLED', orderId, reason);
    return { id: orderId, status: expired ? 'EXPIRED' : 'CANCELLED' };
}
export async function identify(db: Db, a: Actor, orderId: string, body: unknown) {
    const b = fields(body, ['identityAssertionId']);
    const order = await one(db, 'SELECT * FROM orders WHERE id=$1 FOR UPDATE', [orderId]);
    if (order.status !== 'AWAITING_PAYMENT' || new Date(order.expires_at) < new Date())
        reject(422, 'RESERVATION_EXPIRED', 'Đơn không còn chờ thanh toán hoặc đã hết hạn.');
    if (order.student_id)
        reject(409, 'ORDER_ALREADY_IDENTIFIED', 'Đơn đã có sinh viên xác nhận.');
    const identity = await consumeIdentity(db, uuid(b.identityAssertionId), 'CANTEEN', orderId);
    const paymentId = id();
    await db.query('UPDATE orders SET student_id=$2 WHERE id=$1', [orderId, identity.student_id]);
    await db.query("INSERT INTO payments(id,student_id,order_id,amount_points,status,identity_assertion_id) VALUES($1,$2,$3,$4,'AWAITING_CONFIRMATION',$5)", [paymentId, identity.student_id, orderId, order.total_points, identity.id]);
    await notify(db, identity.student_id, 'payment.changed', `Đơn cantin cần xác nhận ${order.total_points} point.`, paymentId);
    await audit(db, a, 'CANTEEN_IDENTIFIED', orderId);
    return { paymentId, studentId: identity.student_id, amountPoints: order.total_points, sourceVersion: order.version, approvalRequired: true };
}
export async function checkout(db: Db, a: Actor, orderId: string, body: unknown) {
    const b = fields(body, ['paymentId', 'approvalId', 'expectedVersion']);
    const order = await one(db, 'SELECT * FROM orders WHERE id=$1 FOR UPDATE', [orderId]);
    if (order.status === 'COMPLETED')
        return { orderId, status: 'COMPLETED', transaction: await one(db, 'SELECT t.id FROM wallet_transactions t JOIN payments p ON p.id=t.payment_id WHERE p.order_id=$1', [orderId]) };
    expected(order.version, b.expectedVersion);
    if (order.status !== 'AWAITING_PAYMENT' || new Date(order.expires_at) < new Date())
        reject(422, 'RESERVATION_EXPIRED', 'Đơn đã hết thời gian thanh toán.');
    const payment = await one(db, 'SELECT * FROM payments WHERE id=$1 AND order_id=$2 FOR UPDATE', [uuid(b.paymentId), orderId]);
    const items = (await db.query('SELECT r.*,i.on_hand,i.reserved FROM inventory_reservations r JOIN inventory i ON i.product_id=r.product_id WHERE r.order_id=$1 ORDER BY r.product_id FOR UPDATE OF r,i', [orderId])).rows;
    if (items.length === 0 || items.some(i => i.status !== 'ACTIVE' || i.reserved < i.quantity || i.on_hand < i.quantity || new Date(i.expires_at) < new Date()))
        reject(422, 'INSUFFICIENT_STOCK', 'Phần tồn kho giữ cho đơn không còn hợp lệ.');
    await authorize(db, payment, order.version, uuid(b.approvalId));
    const receipt = await capture(db, { ...payment, status: 'AUTHORIZED' });
    for (const item of items) {
        await db.query('UPDATE inventory SET on_hand=on_hand-$2,reserved=reserved-$2 WHERE product_id=$1', [item.product_id, item.quantity]);
        await db.query("INSERT INTO inventory_movements(id,product_id,order_id,kind,quantity_delta) VALUES($1,$2,$3,'SALE',$4)", [id(), item.product_id, orderId, -item.quantity]);
    }
    await db.query("UPDATE inventory_reservations SET status='CONSUMED' WHERE order_id=$1", [orderId]);
    await db.query("UPDATE orders SET status='COMPLETED',version=version+1,completed_at=now() WHERE id=$1", [orderId]);
    await audit(db, a, 'CANTEEN_PAID', orderId);
    return { orderId, status: 'COMPLETED', transactionId: receipt.id, amountPoints: order.total_points };
}

export async function directCheckout(db: Db, a: Actor, orderId: string, body: unknown, cardKey?: string) {
    const b = body as Record<string, any>;
    const order = await one(db, 'SELECT * FROM orders WHERE id=$1 FOR UPDATE', [orderId]);
    if (order.status === 'COMPLETED')
        return { orderId, status: 'COMPLETED', transaction: await one(db, 'SELECT t.id FROM wallet_transactions t JOIN payments p ON p.id=t.payment_id WHERE p.order_id=$1', [orderId]) };
    if (order.status !== 'AWAITING_PAYMENT' || new Date(order.expires_at) < new Date())
        reject(422, 'RESERVATION_EXPIRED', 'Đơn không còn chờ thanh toán hoặc đã hết hạn.');

    let studentId: string | null = null;
    let cardId: string | null = null;
    let assertionId: string | null = null;

    if (b.identityAssertionId) {
        const identity = await consumeIdentity(db, uuid(b.identityAssertionId), 'CANTEEN', orderId);
        studentId = identity.student_id;
        cardId = identity.card_id ?? null;
        assertionId = identity.id;
    } else if (b.rfidUid && cardKey) {
        const rawUid = str(b.rfidUid, 50).replace(/[^0-9a-fA-F]/g, '').toUpperCase();
        const digest = uidHash(rawUid, cardKey);
        const card = await optional(db, "SELECT c.*, s.active, u.status AS user_status FROM rfid_cards c JOIN students s ON s.id=c.student_id JOIN users u ON u.id=s.user_id WHERE c.uid_hmac=$1 AND c.status='ACTIVE'", [digest]);
        if (!card || !card.active || card.user_status !== 'ACTIVE')
            reject(422, 'CARD_NOT_ACTIVE', 'Thẻ không hợp lệ hoặc sinh viên không còn hoạt động.');
        studentId = card.student_id;
        cardId = card.id;
    } else if (b.cardId) {
        const card = await one(db, "SELECT c.*, s.active, u.status AS user_status FROM rfid_cards c JOIN students s ON s.id=c.student_id JOIN users u ON u.id=s.user_id WHERE c.id=$1 AND c.status='ACTIVE'", [uuid(b.cardId)]);
        if (!card.active || card.user_status !== 'ACTIVE')
            reject(422, 'CARD_NOT_ACTIVE', 'Thẻ không hợp lệ hoặc sinh viên không còn hoạt động.');
        studentId = card.student_id;
        cardId = card.id;
    } else if (b.studentId) {
        const student = await one(db, "SELECT s.*, u.status AS user_status FROM students s JOIN users u ON u.id=s.user_id WHERE s.id=$1", [uuid(b.studentId)]);
        if (!student.active || student.user_status !== 'ACTIVE')
            reject(422, 'STUDENT_INACTIVE', 'Sinh viên không còn hoạt động.');
        studentId = student.id;
        const card = await optional(db, "SELECT id FROM rfid_cards WHERE student_id=$1 AND status='ACTIVE' ORDER BY created_at DESC LIMIT 1", [studentId]);
        cardId = card?.id ?? null;
    } else {
        reject(400, 'STUDENT_OR_CARD_REQUIRED', 'Cần quẹt thẻ RFID hoặc chọn thẻ sinh viên để thanh toán trực tiếp.');
    }

    if (!assertionId) {
        let device = await optional(db, "SELECT id, config_version FROM devices WHERE role='CANTEEN_POS' AND active LIMIT 1");
        if (!device) {
            device = await one(db, "SELECT id, config_version FROM devices WHERE active LIMIT 1");
        }
        const contextId = id();
        await db.query(
            "INSERT INTO device_contexts(id,device_id,purpose,order_id,config_version,status,expires_at) VALUES($1,$2,'CANTEEN',$3,$4,'CONSUMED',now()+interval '15 minutes')",
            [contextId, device.id, orderId, device.config_version]
        );
        assertionId = id();
        await db.query(
            "INSERT INTO identity_assertions(id,student_id,device_id,context_id,source,card_id,expires_at,consumed_at) VALUES($1,$2,$3,$4,'REAL',$5,now()+interval '15 minutes',now())",
            [assertionId, studentId, device.id, contextId, cardId]
        );
    }

    const paymentId = id();
    await db.query('UPDATE orders SET student_id=$2 WHERE id=$1', [orderId, studentId]);
    await db.query("INSERT INTO payments(id,student_id,order_id,amount_points,status,identity_assertion_id) VALUES($1,$2,$3,$4,'AWAITING_CONFIRMATION',$5)", [paymentId, studentId, orderId, order.total_points, assertionId]);

    const items = (await db.query('SELECT r.*,i.on_hand,i.reserved FROM inventory_reservations r JOIN inventory i ON i.product_id=r.product_id WHERE r.order_id=$1 ORDER BY r.product_id FOR UPDATE OF r,i', [orderId])).rows;
    if (items.length === 0 || items.some(i => i.status !== 'ACTIVE' || i.reserved < i.quantity || i.on_hand < i.quantity || new Date(i.expires_at) < new Date()))
        reject(422, 'INSUFFICIENT_STOCK', 'Phần tồn kho giữ cho đơn không còn hợp lệ.');

    const payment = await one(db, 'SELECT * FROM payments WHERE id=$1 FOR UPDATE', [paymentId]);
    await authorizeDirect(db, payment);
    const receipt = await capture(db, { ...payment, status: 'AUTHORIZED' });

    for (const item of items) {
        await db.query('UPDATE inventory SET on_hand=on_hand-$2,reserved=reserved-$2 WHERE product_id=$1', [item.product_id, item.quantity]);
        await db.query("INSERT INTO inventory_movements(id,product_id,order_id,kind,quantity_delta) VALUES($1,$2,$3,'SALE',$4)", [id(), item.product_id, orderId, -item.quantity]);
    }
    await db.query("UPDATE inventory_reservations SET status='CONSUMED' WHERE order_id=$1", [orderId]);
    await db.query("UPDATE orders SET status='COMPLETED',version=version+1,completed_at=now() WHERE id=$1", [orderId]);
    await audit(db, a, 'CANTEEN_PAID_DIRECT_RFID', orderId, undefined, { studentId, cardId, amountPoints: order.total_points });
    return { orderId, status: 'COMPLETED', transactionId: receipt.id, amountPoints: order.total_points, studentId };
}
