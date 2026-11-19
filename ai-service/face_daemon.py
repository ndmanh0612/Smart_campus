"""High-performance persistent daemon for YuNet face detection and SFace recognition.
Keeps models and OpenCV in memory to achieve 20-35ms response time per frame.
Communicates via line-delimited JSON over stdin / stdout.
"""
import base64
import json
import os
from pathlib import Path
import sys
import time

import cv2
import numpy as np
from face_quality import check_face_quality, check_registration_position, QUALITY_VERSION, MATCH_THRESHOLD, MATCH_MARGIN

ROOT = Path(__file__).resolve().parents[1]
MODELS_DIR = ROOT / "models"
PROFILE_DIR = ROOT / ".work" / "face-profiles"
THRESHOLD = MATCH_THRESHOLD

def load_models():
    manifest = json.loads((MODELS_DIR / "manifest.json").read_text(encoding="utf-8"))
    cv2.setNumThreads(2)
    yunet_path = str(MODELS_DIR / manifest["yunet"]["file"])
    sface_path = str(MODELS_DIR / manifest["sface"]["file"])
    detector = cv2.FaceDetectorYN.create(yunet_path, "", (320, 240), 0.7, 0.3, 5000)
    recognizer = cv2.FaceRecognizerSF.create(sface_path, "")
    return detector, recognizer

print("[DAEMON] Pre-loading models and OpenCV runtime...", file=sys.stderr)
t0 = time.time()
detector, recognizer = load_models()
# Warm-up inference
dummy = np.zeros((240, 320, 3), dtype=np.uint8)
detector.setInputSize((320, 240))
detector.detect(dummy)
print(f"[DAEMON] Ready in {round((time.time() - t0) * 1000, 1)}ms", file=sys.stderr)

def decode_image(raw_bytes: bytes) -> np.ndarray:
    frame = cv2.imdecode(np.frombuffer(raw_bytes, dtype=np.uint8), cv2.IMREAD_COLOR)
    if frame is None:
        raise ValueError("Could not decode image")
    return frame

def handle_detect(raw_bytes: bytes):
    frame = decode_image(raw_bytes)
    h, w = frame.shape[:2]
    detector.setInputSize((w, h))
    _, faces = detector.detect(frame)
    results = []
    if faces is not None:
        for f in faces:
            x, y, fw, fh = map(int, f[:4])
            score = float(f[-1])
            results.append({"box": [x, y, fw, fh], "score": round(score, 4)})
    eligible = False
    guidance = ""
    try:
        face, _ = check_face_quality(frame, faces)
        check_registration_position(frame, face)
        eligible = True
    except ValueError as error:
        guidance = str(error)
    return {
        "success": True,
        "faces": results,
        "width": w,
        "height": h,
        "enrollmentEligible": eligible,
        "guidance": guidance
    }

def handle_enroll(raw_bytes: bytes, student_id: str, student_code: str = "", name: str = ""):
    frame = decode_image(raw_bytes)
    h, w = frame.shape[:2]
    detector.setInputSize((w, h))
    _, faces = detector.detect(frame)

    try:
        face, quality = check_face_quality(frame, faces)
        check_registration_position(frame, face)
    except ValueError as err:
        return {
            "success": False,
            "error": "FACE_FRAME_REJECTED",
            "message": str(err)
        }

    x, y, fw, fh = map(int, face[:4])
    score = float(face[-1])

    aligned = recognizer.alignCrop(frame, face)
    feature = recognizer.feature(aligned)

    PROFILE_DIR.mkdir(parents=True, exist_ok=True)
    profile_path = PROFILE_DIR / f"{student_id}-v1.npy"
    meta_path = PROFILE_DIR / f"{student_id}-meta.json"

    np.save(profile_path, feature, allow_pickle=False)

    metadata = {
        "studentId": student_id,
        "studentCode": student_code,
        "name": name,
        "enrolledAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "model": "SFace",
        "qualityVersion": QUALITY_VERSION,
        "quality": quality,
        "score": round(score, 4),
        "box": [x, y, fw, fh]
    }
    meta_path.write_text(json.dumps(metadata, ensure_ascii=False, indent=2), encoding="utf-8")

    avatar_path = PROFILE_DIR / f"{student_id}-avatar.jpg"
    cv2.imwrite(str(avatar_path), aligned)

    return {
        "success": True,
        "status": "ENROLLED",
        "studentId": student_id,
        "studentCode": student_code,
        "name": name,
        "score": round(score, 4),
        "box": [x, y, fw, fh]
    }

def handle_identify(raw_bytes: bytes):
    frame = decode_image(raw_bytes)
    h, w = frame.shape[:2]
    detector.setInputSize((w, h))
    _, faces = detector.detect(frame)

    if faces is None or len(faces) == 0:
        return {
            "success": False,
            "outcome": "NO_FACE",
            "message": "Không phát hiện khuôn mặt trước camera."
        }

    face = max(faces, key=lambda f: f[-1])
    if float(face[-1]) < 0.60:
        return {
            "success": False,
            "outcome": "NO_FACE",
            "message": "Khuôn mặt chưa đủ rõ nét để nhận diện."
        }

    x, y, fw, fh = map(int, face[:4])
    aligned = recognizer.alignCrop(frame, face)
    live_feature = recognizer.feature(aligned)

    profile_files = list(PROFILE_DIR.glob("*-v1.npy"))
    if not profile_files:
        return {
            "success": False,
            "outcome": "NO_PROFILES",
            "message": "Hệ thống chưa có hồ sơ khuôn mặt nào được đăng ký."
        }

    best_match = None
    best_score = -1.0
    second_score = -1.0

    for pf in profile_files:
        student_id = pf.name.replace("-v1.npy", "")
        try:
            enrolled_feature = np.load(pf, allow_pickle=False)
            score = recognizer.match(enrolled_feature, live_feature, cv2.FaceRecognizerSF_FR_COSINE)
            if not np.isfinite(score):
                continue
            if score > best_score:
                second_score = best_score
                best_score = float(score)
                best_match = student_id
            elif score > second_score:
                second_score = float(score)
        except Exception:
            continue

    meta = {}
    if best_match:
        meta_file = PROFILE_DIR / f"{best_match}-meta.json"
        if meta_file.exists():
            try:
                meta = json.loads(meta_file.read_text(encoding="utf-8"))
            except Exception:
                pass

    if best_score >= THRESHOLD and best_match:
        return {
            "success": True,
            "outcome": "MATCH",
            "studentId": best_match,
            "studentCode": meta.get("studentCode", ""),
            "name": meta.get("name", ""),
            "score": round(best_score, 4),
            "threshold": THRESHOLD,
            "box": [x, y, fw, fh]
        }
    else:
        return {
            "success": False,
            "outcome": "NO_MATCH",
            "score": round(best_score, 4),
            "threshold": THRESHOLD,
            "box": [x, y, fw, fh],
            "message": "Khuôn mặt không khớp với bất kỳ sinh viên nào đã đăng ký."
        }

def main():
    # Notify parent process that daemon is initialized and ready
    print(json.dumps({"ready": True}), flush=True)

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
            req_id = req.get("id")
            action = req.get("action")
            raw_b64 = req.get("image", "")
            if "," in raw_b64:
                raw_b64 = raw_b64.split(",", 1)[1]
            raw_bytes = base64.b64decode(raw_b64)

            if action == "detect":
                resp = handle_detect(raw_bytes)
            elif action == "enroll":
                resp = handle_enroll(
                    raw_bytes,
                    req.get("studentId", ""),
                    req.get("studentCode", ""),
                    req.get("name", "")
                )
            elif action == "identify":
                resp = handle_identify(raw_bytes)
            else:
                resp = {"success": False, "error": f"Unknown action: {action}"}

            resp["id"] = req_id
            print(json.dumps(resp), flush=True)
        except Exception as err:
            print(json.dumps({"id": req.get("id") if 'req' in locals() else None, "success": False, "error": str(err)}), flush=True)

if __name__ == "__main__":
    main()
