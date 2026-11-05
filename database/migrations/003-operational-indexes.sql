CREATE INDEX parking_pass_lookup ON campus.parking_passes(student_id,vehicle_id,lot_id,valid_to);
CREATE INDEX parking_student_history ON campus.parking_sessions(student_id,created_at DESC);
CREATE INDEX order_student_history ON campus.orders(student_id,created_at DESC);
CREATE INDEX attendance_student_history ON campus.attendance_records(student_id,received_at DESC);
CREATE INDEX notification_recipient_history ON campus.notifications(recipient_user_id,created_at DESC);
CREATE INDEX device_event_history ON campus.device_events(device_id,created_at DESC);
CREATE INDEX stock_reservation_expiry ON campus.inventory_reservations(status,expires_at);
CREATE INDEX audit_history ON campus.audit_logs(created_at DESC);
