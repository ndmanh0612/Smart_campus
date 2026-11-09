"""Real-time Face Detection (YuNet) and Face Recognition (SFace) Engine."""
import argparse
import base64
from datetime import datetime, timezone
import glob
import json
import os
from pathlib import Path
import sys
import urllib.request

import cv2
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
MODELS_DIR = ROOT / "models"
PROFILE_DIR = ROOT / ".work" / "face-profiles"
THRESHOLD = 0.50  # SFace cosine similarity threshold

def load_models():
    manifest = json.loads((MODELS_DIR / "manifest.json").read_text())
    cv2.setNumThreads(1)
    yunet_path = str(MODELS_DIR / manifest["yunet"]["file"])
    sface_path = str(MODELS_DIR / manifest["sface"]["file"])
    detector = cv2.FaceDetectorYN.create(yunet_path, "", (320, 240), 0.7, 0.3, 5000)
    recognizer = cv2.FaceRecognizerSF.create(sface_path, "")
    return detector, recognizer

def read_image_from_source(source: str) -> np.ndarray:
    """Read image from local file path, http(s) URL, or base64 string."""
    if source.startswith(("http://", "https://")):
        req = urllib.request.Request(source, headers={"User-Agent": "SmartCampus/1.0"})
        with urllib.request.urlopen(req, timeout=5) as res:
            raw = res.read()
    elif source.startswith("data:image") or len(source) > 500 and not os.path.exists(source):
        # Base64 string
        if "," in source:
            source = source.split(",", 1)[1]
        raw = base64.b64decode(source)
    elif source == "-":
        raw = sys.stdin.buffer.read()
    else:
        with open(source, "rb") as f:
            raw = f.read()
    
    frame = cv2.imdecode(np.frombuffer(raw, dtype=np.uint8), cv2.IMREAD_COLOR)
    if frame is None:
        raise ValueError("Could not decode image")
    return frame

def detect_single_face(detector, frame: np.ndarray):
    h, w = frame.shape[:2]
    detector.setInputSize((w, h))
    _, faces = detector.detect(frame)
    if faces is None or len(faces) == 0:
        return None
    # Return face with highest confidence score
    best_face = max(faces, key=lambda f: f[-1])
    return best_face

def action_detect(source: str):
    detector, _ = load_models()
    frame = read_image_from_source(source)
    h, w = frame.shape[:2]
    detector.setInputSize((w, h))
    _, faces = detector.detect(frame)
    results = []
    if faces is not None:
        for f in faces:
            x, y, fw, fh = map(int, f[:4])
            score = float(f[-1])
            results.append({"box": [x, y, fw, fh], "score": round(score, 4)})
    print(json.dumps({"success": True, "faces": results, "width": w, "height": h}))

def action_enroll(source: str, student_id: str, student_code: str = "", name: str = ""):
    detector, recognizer = load_models()
    frame = read_image_from_source(source)
    face = detect_single_face(detector, frame)
    if face is None:
        print(json.dumps({"success": False, "error": "NO_FACE_DETECTED", "message": "Không tìm thấy khuôn mặt trong ảnh."}))
        return

    x, y, w, h = map(int, face[:4])
    score = float(face[-1])
    if min(w, h) < 40:
        print(json.dumps({"success": False, "error": "FACE_TOO_SMALL", "message": "Khuôn mặt quá nhỏ hoặc ở quá xa camera."}))
        return

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
        "enrolledAt": datetime.now(timezone.utc).isoformat(),
        "model": "SFace",
        "score": round(score, 4),
        "box": [x, y, w, h]
    }
    meta_path.write_text(json.dumps(metadata, ensure_ascii=False, indent=2), encoding="utf-8")

    # Optionally save small avatar crop
    avatar_path = PROFILE_DIR / f"{student_id}-avatar.jpg"
    cv2.imwrite(str(avatar_path), aligned)

    print(json.dumps({
        "success": True,
        "status": "ENROLLED",
        "studentId": student_id,
        "studentCode": student_code,
        "name": name,
        "score": round(score, 4),
        "box": [x, y, w, h]
    }))

def action_identify(source: str):
    """1:N matching: Detect face in live frame, compare with all enrolled student profiles."""
    detector, recognizer = load_models()
    frame = read_image_from_source(source)
    face = detect_single_face(detector, frame)
    if face is None:
        print(json.dumps({
            "success": False,
            "outcome": "NO_FACE",
            "message": "Không phát hiện khuôn mặt trước camera."
        }))
        return

    x, y, w, h = map(int, face[:4])
    aligned = recognizer.alignCrop(frame, face)
    live_feature = recognizer.feature(aligned)

    profile_files = list(PROFILE_DIR.glob("*-v1.npy"))
    if not profile_files:
        print(json.dumps({
            "success": False,
            "outcome": "NO_PROFILES",
            "message": "Hệ thống chưa có hồ sơ khuôn mặt nào được đăng ký."
        }))
        return

    best_match = None
    best_score = -1.0

    for pf in profile_files:
        student_id = pf.name.replace("-v1.npy", "")
        try:
            enrolled_feature = np.load(pf, allow_pickle=False)
            score = recognizer.match(enrolled_feature, live_feature, cv2.FaceRecognizerSF_FR_COSINE)
            if score > best_score:
                best_score = float(score)
                best_match = student_id
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
        print(json.dumps({
            "success": True,
            "outcome": "MATCH",
            "studentId": best_match,
            "studentCode": meta.get("studentCode", ""),
            "name": meta.get("name", ""),
            "score": round(best_score, 4),
            "threshold": THRESHOLD,
            "box": [x, y, w, h]
        }))
    else:
        print(json.dumps({
            "success": False,
            "outcome": "NO_MATCH",
            "score": round(best_score, 4),
            "threshold": THRESHOLD,
            "box": [x, y, w, h],
            "message": "Khuôn mặt không khớp với bất kỳ sinh viên nào đã đăng ký."
        }))

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Real Face Engine")
    parser.add_argument("action", choices=["detect", "enroll", "identify"])
    parser.add_argument("--source", default="http://192.168.2.43/capture", help="File path, URL, or '-' for stdin")
    parser.add_argument("--student-id", default="", help="Student UUID for enrollment")
    parser.add_argument("--student-code", default="", help="Student code")
    parser.add_argument("--name", default="", help="Student name")
    args = parser.parse_args()

    try:
        if args.action == "detect":
            action_detect(args.source)
        elif args.action == "enroll":
            if not args.student_id:
                parser.error("--student-id is required for enrollment")
            action_enroll(args.source, args.student_id, args.student_code, args.name)
        elif args.action == "identify":
            action_identify(args.source)
    except Exception as err:
        print(json.dumps({"success": False, "error": str(err)}))
        sys.exit(1)
