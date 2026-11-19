"""Enroll and verify one consenting volunteer in a local SFace pilot."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
from uuid import UUID

import cv2
import numpy as np

from detect_faces import load_frame
from runtime import Runtime
from face_quality import check_face_quality, check_registration_position, QUALITY_VERSION, MATCH_THRESHOLD

THRESHOLD = MATCH_THRESHOLD
PROFILE_DIR = Path(__file__).resolve().parents[1] / ".work" / "face-profiles"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["enroll", "verify", "erase"])
    parser.add_argument("source", nargs="?", help="Camera /capture URL or JPEG path")
    parser.add_argument("--consent", action="store_true", help="Confirm the volunteer agreed to local enrollment")
    parser.add_argument("--student-id", type=UUID, help="Isolate a local app user's profile")
    parser.add_argument("--student-code", help="Student identification code")
    parser.add_argument("--name", help="Student full name")
    args = parser.parse_args()
    key = args.student_id or "volunteer"
    profile = PROFILE_DIR / f"{key}-v1.npy"
    meta_file = PROFILE_DIR / f"{key}-meta.json"
    if args.action == "erase":
        profile.unlink(missing_ok=True)
        meta_file.unlink(missing_ok=True)
        print(json.dumps({"status": "ERASED"}))
        return
    if not args.source:
        parser.error("A camera URL or JPEG is required")
    if args.action == "enroll" and not args.consent:
        parser.error("Enrollment requires the volunteer's explicit consent")
    if args.action == "verify" and not profile.exists():
        parser.error("Enroll the volunteer first")

    try:
        runtime = Runtime()
        frame = load_frame(args.source)
        height, width = frame.shape[:2]
        runtime.detector.setInputSize((width, height))
        _, faces = runtime.detector.detect(frame)
        face, quality = check_face_quality(frame, faces)
        if args.action == "enroll":
            check_registration_position(frame, face)
        if args.action == "verify":
            metadata = json.loads(meta_file.read_text(encoding="utf-8"))
            if metadata.get("qualityVersion") != QUALITY_VERSION:
                raise ValueError("Hãy đăng ký lại mẫu khuôn mặt rõ nét theo kiểm tra chất lượng mới.")
        aligned = runtime.recognizer.alignCrop(frame, face)
        feature = runtime.recognizer.feature(aligned)
        if args.action == "enroll":
            PROFILE_DIR.mkdir(parents=True, exist_ok=True)
            with profile.open("xb") as file:
                np.save(file, feature, allow_pickle=False)
            metadata = {
                "studentId": str(args.student_id) if args.student_id else None,
                "studentCode": args.student_code or "",
                "name": args.name or "",
                "enrolledAt": datetime.now(timezone.utc).isoformat(),
                "model": "SFace",
                "qualityVersion": QUALITY_VERSION,
                "quality": quality,
                "liveness": "NOT_CHECKED"
            }
            meta_file.write_text(json.dumps(metadata, ensure_ascii=False, indent=2), encoding="utf-8")
            print(json.dumps({
                "status": "ENROLLED",
                "model": "SFace",
                "studentCode": args.student_code or "",
                "name": args.name or "",
                "liveness": "NOT_CHECKED"
            }))
            return

        reference = np.load(profile, allow_pickle=False)
        score = runtime.recognizer.match(reference, feature, cv2.FaceRecognizerSF_FR_COSINE)
        if not np.isfinite(score):
            raise ValueError("Invalid similarity score")
        print(json.dumps({
            "status": "MATCH" if score >= THRESHOLD else "NO_MATCH",
            "score": round(score, 4),
            "threshold": THRESHOLD,
            "studentCode": args.student_code or "",
            "name": args.name or "",
            "liveness": "NOT_CHECKED",
        }))
    except FileExistsError:
        parser.exit(1, "A volunteer is already enrolled. Erase that profile before replacing it.\n")
    except (OSError, ValueError, cv2.error) as error:
        parser.exit(1, f"Face pilot failed: {error}\n")


if __name__ == "__main__":
    main()
