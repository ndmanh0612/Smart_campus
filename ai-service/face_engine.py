"""Real-time Face Detection (YuNet) and Face Recognition (SFace) Engine."""
import argparse
import base64
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import sys
import urllib.request

import cv2
import numpy as np
from face_quality import check_face_quality, check_registration_position, QUALITY_VERSION, MATCH_THRESHOLD, MATCH_MARGIN

ROOT = Path(__file__).resolve().parents[1]
MODELS_DIR = ROOT / "models"
PROFILE_DIR = ROOT / ".work" / "face-profiles"
THRESHOLD = MATCH_THRESHOLD

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
    elif source.startswith("data:image") or (len(source) > 500 and not os.path.exists(source)):
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
    eligible = False
    guidance = ""
    try:
        face, _ = check_face_quality(frame, faces)
        check_registration_position(frame, face)
        eligible = True
    except ValueError as error:
        guidance = str(error)
    print(json.dumps({
        "success": True,
        "faces": results,
        "width": w,
        "height": h,
        "enrollmentEligible": eligible,
        "guidance": guidance
    }))

def action_enroll(source: str, student_id: str, student_code: str = "", name: str = ""):
    detector, recognizer = load_models()
    frame = read_image_from_source(source)
    h, w = frame.shape[:2]
    detector.setInputSize((w, h))
    _, faces = detector.detect(frame)

    try:
        face, quality = check_face_quality(frame, faces)
        check_registration_position(frame, face)
    except ValueError as err:
        print(json.dumps({
            "success": False,
            "error": "FACE_FRAME_REJECTED",
            "message": str(err)
        }))
        return

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
        "enrolledAt": datetime.now(timezone.utc).isoformat(),
        "model": "SFace",
        "qualityVersion": QUALITY_VERSION,
        "quality": quality,
        "score": round(score, 4),
        "box": [x, y, fw, fh]
    }
    meta_path.write_text(json.dumps(metadata, ensure_ascii=False, indent=2), encoding="utf-8")

    avatar_path = PROFILE_DIR / f"{student_id}-avatar.jpg"
    cv2.imwrite(str(avatar_path), aligned)

    print(json.dumps({
        "success": True,
        "status": "ENROLLED",
        "studentId": student_id,
        "studentCode": student_code,
        "name": name,
        "score": round(score, 4),
        "box": [x, y, fw, fh]
    }))

def action_identify(source: str):
    """1:N matching: Detect face in live frame, compare with all enrolled student profiles."""
    detector, recognizer = load_models()
    frame = read_image_from_source(source)
    h, w = frame.shape[:2]
    detector.setInputSize((w, h))
    _, faces = detector.detect(frame)

    if faces is None or len(faces) == 0:
        print(json.dumps({
            "success": False,
            "outcome": "NO_FACE",
            "message": "Không phát hiện khuôn mặt trước camera."
        }))
        return

    # Lấy khuôn mặt có độ tự tin cao nhất
    face = max(faces, key=lambda f: f[-1])
    if float(face[-1]) < 0.60:
        print(json.dumps({
            "success": False,
            "outcome": "NO_FACE",
            "message": "Khuôn mặt chưa đủ rõ nét để nhận diện."
        }))
        return

    x, y, fw, fh = map(int, face[:4])
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
        print(json.dumps({
            "success": True,
            "outcome": "MATCH",
            "studentId": best_match,
            "studentCode": meta.get("studentCode", ""),
            "name": meta.get("name", ""),
            "score": round(best_score, 4),
            "threshold": THRESHOLD,
            "box": [x, y, fw, fh]
        }))
    else:
        print(json.dumps({
            "success": False,
            "outcome": "NO_MATCH",
            "score": round(best_score, 4),
            "threshold": THRESHOLD,
            "box": [x, y, fw, fh],
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
    except ValueError as err:
        print(json.dumps({"success": False, "error": "FACE_FRAME_REJECTED", "message": str(err)}))
        sys.exit(0)
    except Exception as err:
        print(json.dumps({"success": False, "error": "AI_ERROR", "message": str(err)}))
        sys.exit(0)
