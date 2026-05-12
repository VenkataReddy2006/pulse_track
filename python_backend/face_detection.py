"""
Face Detection & ROI Extraction (Server-Side)

Uses MediaPipe FaceMesh for precise facial landmark detection
to extract ROI regions for rPPG signal processing.

Forehead and cheek ROIs are optimal for rPPG because:
- Forehead: thin skin, good vascular density, minimal hair
- Cheeks: large surface area, good blood perfusion

Landmarks reference (MediaPipe 468-point FaceMesh):
  Forehead: 10, 67, 109, 338, 297, 299, 69, 108
  Left cheek: 50, 187, 123, 117, 118, 101
  Right cheek: 280, 411, 352, 346, 347, 330
"""

import cv2
import numpy as np
import mediapipe as mp
from typing import Optional, Tuple, List, Dict

# Initialize MediaPipe FaceMesh
mp_face_mesh = mp.solutions.face_mesh

# Landmark indices for ROI regions
FOREHEAD_LANDMARKS = [10, 67, 109, 338, 297, 299, 69, 108]
LEFT_CHEEK_LANDMARKS = [50, 187, 123, 117, 118, 101]
RIGHT_CHEEK_LANDMARKS = [280, 411, 352, 346, 347, 330]


def extract_roi_from_landmarks(image: np.ndarray, landmarks,
                                indices: List[int]) -> Optional[np.ndarray]:
    """
    Extract a polygonal ROI from facial landmarks.

    Args:
        image: BGR image from OpenCV
        landmarks: MediaPipe face landmarks
        indices: List of landmark indices defining the ROI polygon

    Returns:
        Masked ROI region pixels (Nx3 array of BGR values), or None
    """
    h, w = image.shape[:2]
    points = []
    for idx in indices:
        lm = landmarks.landmark[idx]
        x = int(lm.x * w)
        y = int(lm.y * h)
        points.append([x, y])

    points = np.array(points, dtype=np.int32)
    mask = np.zeros((h, w), dtype=np.uint8)
    cv2.fillConvexPoly(mask, points, 255)

    roi_pixels = image[mask == 255]
    if len(roi_pixels) == 0:
        return None
    return roi_pixels


def extract_rgb_from_frame(frame_bytes: bytes, width: int, height: int) -> Optional[Dict]:
    """
    Process a single camera frame to extract RGB channel averages
    from facial ROI regions.

    Args:
        frame_bytes: Raw image bytes (JPEG/PNG encoded)
        width: Frame width
        height: Frame height

    Returns:
        Dict with r, g, b channel averages, or None if no face detected
    """
    # Decode image
    nparr = np.frombuffer(frame_bytes, np.uint8)
    image = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
    if image is None:
        return None

    rgb_image = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)

    with mp_face_mesh.FaceMesh(
        static_image_mode=True,
        max_num_faces=1,
        refine_landmarks=True,
        min_detection_confidence=0.5,
    ) as face_mesh:
        results = face_mesh.process(rgb_image)

        if not results.multi_face_landmarks:
            return None

        face_landmarks = results.multi_face_landmarks[0]

        # Extract ROIs
        all_pixels = []
        for region_indices in [FOREHEAD_LANDMARKS, LEFT_CHEEK_LANDMARKS, RIGHT_CHEEK_LANDMARKS]:
            roi = extract_roi_from_landmarks(image, face_landmarks, region_indices)
            if roi is not None:
                all_pixels.append(roi)

        if not all_pixels:
            return None

        combined = np.vstack(all_pixels)
        # OpenCV uses BGR, convert to RGB averages
        return {
            "r": float(np.mean(combined[:, 2])),
            "g": float(np.mean(combined[:, 1])),
            "b": float(np.mean(combined[:, 0])),
        }


def get_face_roi_info(frame_bytes: bytes) -> Optional[Dict]:
    """
    Get face detection info and ROI bounding boxes for debugging.
    """
    nparr = np.frombuffer(frame_bytes, np.uint8)
    image = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
    if image is None:
        return None

    h, w = image.shape[:2]
    rgb_image = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)

    with mp_face_mesh.FaceMesh(
        static_image_mode=True,
        max_num_faces=1,
        min_detection_confidence=0.5,
    ) as face_mesh:
        results = face_mesh.process(rgb_image)
        if not results.multi_face_landmarks:
            return None

        face = results.multi_face_landmarks[0]
        # Get face bounding box from landmarks
        xs = [lm.x * w for lm in face.landmark]
        ys = [lm.y * h for lm in face.landmark]

        return {
            "face_detected": True,
            "face_bbox": {
                "x": int(min(xs)), "y": int(min(ys)),
                "w": int(max(xs) - min(xs)), "h": int(max(ys) - min(ys)),
            },
            "image_size": {"w": w, "h": h},
        }
