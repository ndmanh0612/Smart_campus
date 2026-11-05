import { audit, expected, fields, id, integer, notify, one, optional, reject, str, uuid, type Actor, type Db } from './platform.ts';
import { consumeIdentity } from './devices.ts';
import { authorize, capture, voidPayment } from './wallet.ts';
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
