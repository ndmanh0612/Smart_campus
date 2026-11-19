"""Quality gates shared by enrollment and recognition on the campus camera."""
import cv2
import numpy as np

QUALITY_VERSION = "camera-quality-v1"
MATCH_THRESHOLD = 0.50
MATCH_MARGIN = 0.05


def check_registration_position(frame, face):
    if face is None:
        raise ValueError("Không tìm thấy khuôn mặt trong ảnh.")
    height, width = frame.shape[:2]
    x, y, face_width, face_height = map(float, face[:4])
    center_x = (x + face_width / 2.0) / width
    center_y = (y + face_height / 2.0) / height

    # Yêu cầu tâm khuôn mặt nằm chính giữa khung hình
    if abs(center_x - 0.5) > 0.08 or abs(center_y - 0.5) > 0.09:
        raise ValueError("Di chuyển khuôn mặt vào chính giữa khung hướng dẫn.")

    # Yêu cầu toàn bộ khuôn mặt nằm gọn trong phạm vi khung hướng dẫn
    if (x / width < 0.18 or (x + face_width) / width > 0.82
            or y / height < 0.08 or (y + face_height) / height > 0.92):
        raise ValueError("Đưa toàn bộ khuôn mặt vào trong khung hướng dẫn.")

    # Yêu cầu khuôn mặt đủ lớn (người dùng đến đủ gần camera)
    if face_width / width < 0.22 or face_height / height < 0.28:
        raise ValueError("Đến gần hơn để khuôn mặt đủ lớn trong khung.")


def check_face_quality(frame, faces):
    if faces is None or len(faces) == 0:
        raise ValueError("Không thấy khuôn mặt. Hãy nhìn vào camera.")
    if len(faces) != 1:
        raise ValueError("Chỉ để một người trong khung hình.")
    face = faces[0]
    if not np.isfinite(face).all() or float(face[-1]) < 0.80:
        raise ValueError("Khuôn mặt chưa rõ. Giữ yên và nhìn thẳng vào camera.")

    x, y, width, height = map(float, face[:4])
    image_height, image_width = frame.shape[:2]
    if min(width, height) < 70:
        raise ValueError("Khuôn mặt quá nhỏ. Hãy đến gần camera.")
    if x < 0 or y < 0 or x + width > image_width or y + height > image_height:
        raise ValueError("Đưa toàn bộ khuôn mặt vào khung hình.")

    eyes = np.array(face[4:8], dtype=float).reshape(2, 2)
    nose = np.array(face[8:10], dtype=float)
    mouths = np.array(face[10:14], dtype=float).reshape(2, 2)
    eye_distance = np.linalg.norm(eyes[1] - eyes[0])
    if eye_distance < 20:
        raise ValueError("Hai mắt chưa đủ rõ. Hãy đến gần camera.")

    roll = abs(np.degrees(np.arctan2(eyes[1, 1] - eyes[0, 1], abs(eyes[1, 0] - eyes[0, 0]))))
    eye_midpoint = eyes.mean(axis=0)
    mouth_midpoint = mouths.mean(axis=0)
    eye_to_mouth = mouth_midpoint[1] - eye_midpoint[1]
    nose_ratio = (nose[1] - eye_midpoint[1]) / max(eye_to_mouth, 1)
    if (roll > 15 or abs(nose[0] - eye_midpoint[0]) / eye_distance > 0.25
            or eye_to_mouth < 10 or not 0.20 <= nose_ratio <= 0.85):
        raise ValueError("Nhìn thẳng, giữ đầu ngay và mở mắt trước camera.")

    crop = frame[int(y):int(y + height), int(x):int(x + width)]
    if crop.size == 0:
        raise ValueError("Không cắt được vùng khuôn mặt.")
    gray = cv2.cvtColor(crop, cv2.COLOR_BGR2GRAY)
    normalized = cv2.resize(gray, (112, 112), interpolation=cv2.INTER_AREA)
    brightness = float(normalized.mean())
    clipped = float(np.mean((normalized < 10) | (normalized > 245)))
    sharpness = float(cv2.Laplacian(normalized, cv2.CV_64F).var())

    if brightness < 40 or brightness > 215 or clipped > 0.30:
        raise ValueError("Ánh sáng chưa phù hợp. Tránh quá tối hoặc quá chói.")
    if float(normalized.std()) < 15 or sharpness < 50:
        raise ValueError("Ảnh khuôn mặt bị mờ. Giữ yên để lấy nét rõ hơn.")

    return face, {
        "version": QUALITY_VERSION,
        "sharpness": round(sharpness, 1),
        "brightness": round(brightness, 1),
    }
