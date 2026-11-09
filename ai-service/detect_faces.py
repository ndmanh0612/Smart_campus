"""Run YuNet against one JPEG from a camera URL or a local file."""
import argparse
import json
from pathlib import Path
import sys
from time import perf_counter
from urllib.error import URLError
from urllib.request import urlopen

import cv2
import numpy as np

from runtime import ROOT, create_face_detector

MAX_JPEG_BYTES = 2 * 1024 * 1024


def load_frame(source):
    if source == "-":
        jpeg = sys.stdin.buffer.read(MAX_JPEG_BYTES + 1)
    elif source.startswith(("http://", "https://")):
        with urlopen(source, timeout=5) as response:
            jpeg = response.read(MAX_JPEG_BYTES + 1)
    else:
        with Path(source).open("rb") as file:
            jpeg = file.read(MAX_JPEG_BYTES + 1)
    if len(jpeg) > MAX_JPEG_BYTES or not jpeg.startswith(b"\xff\xd8"):
        raise ValueError("Expected a JPEG of at most 2 MiB")
    frame = cv2.imdecode(np.frombuffer(jpeg, dtype=np.uint8), cv2.IMREAD_COLOR)
    if frame is None:
        raise ValueError("Could not decode JPEG")
    return frame


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", help="HTTP(S) /capture URL or local JPEG path")
    parser.add_argument("--output", type=Path, help="Optional annotated JPEG")
    args = parser.parse_args()

    try:
        spec = json.loads((ROOT / "manifest.json").read_text())["yunet"]
        cv2.setNumThreads(1)
        detector = create_face_detector(spec)

        started = perf_counter()
        frame = load_frame(args.source)
        capture_ms = (perf_counter() - started) * 1000

        height, width = frame.shape[:2]
        detector.setInputSize((width, height))
        started = perf_counter()
        _, detections = detector.detect(frame)
        detect_ms = (perf_counter() - started) * 1000
        faces = []
        if detections is not None:
            for detection in detections:
                x, y, w, h = map(int, detection[:4])
                faces.append({"box": [x, y, w, h], "score": round(float(detection[-1]), 4)})
                if args.output:
                    cv2.rectangle(frame, (x, y), (x + w, y + h), (0, 255, 0), 2)
        if args.output:
            ok, encoded = cv2.imencode(".jpg", frame)
            if not ok:
                raise ValueError("Could not encode annotated JPEG")
            args.output.write_bytes(encoded.tobytes())
        print(json.dumps({
            "width": width, "height": height, "faces": faces,
            "capture_ms": round(capture_ms, 1), "detect_ms": round(detect_ms, 1),
        }))
    except (OSError, URLError, ValueError, cv2.error) as error:
        parser.exit(1, f"Face detection failed: {error}\n")


if __name__ == "__main__":
    main()
