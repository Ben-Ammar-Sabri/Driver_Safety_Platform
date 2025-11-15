# src/computer_vision/face_tracking.py
import cv2
import numpy as np
import mediapipe as mp
import base64
import io

mp_face_mesh = mp.solutions.face_mesh

def b64_to_cv2(b64str):
    data = base64.b64decode(b64str)
    arr = np.frombuffer(data, np.uint8)
    img = cv2.imdecode(arr, cv2.IMREAD_COLOR)
    return img

def landmarks_to_array(landmarks, image_w, image_h):
    return np.array([(int(l.x * image_w), int(l.y * image_h)) for l in landmarks])

def eye_aspect_ratio(eye_pts):
    # eye_pts: Nx2 points; approximate EAR using vertical/horizontal distances
    # Using simple geometry (not exact DLIB EAR indices), works as proxy.
    a = np.linalg.norm(eye_pts[1] - eye_pts[5])
    b = np.linalg.norm(eye_pts[2] - eye_pts[4])
    c = np.linalg.norm(eye_pts[0] - eye_pts[3]) + 1e-6
    ear = (a + b) / (2.0 * c)
    return float(ear)

def analyze_face_from_b64(b64str):
    img = b64_to_cv2(b64str)
    h, w = img.shape[:2]
    with mp_face_mesh.FaceMesh(static_image_mode=True, max_num_faces=1,
                               refine_landmarks=True, min_detection_confidence=0.5) as fm:
        img_rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
        results = fm.process(img_rgb)
        if not results.multi_face_landmarks:
            return {"face_detected": False}
        lm = results.multi_face_landmarks[0].landmark
        pts = landmarks_to_array(lm, w, h)
        # choose approximate eye indices from Mediapipe face mesh (use a cluster)
        # left eye sample indices (approx)
        left_eye_idx = [33, 246, 161, 160, 159, 158]
        right_eye_idx = [362, 398, 384, 385, 386, 387]

        left_eye = np.array([pts[i] for i in left_eye_idx])
        right_eye = np.array([pts[i] for i in right_eye_idx])

        left_ear = eye_aspect_ratio(left_eye)
        right_ear = eye_aspect_ratio(right_eye)
        ear = float((left_ear + right_ear) / 2.0)

        # basic head direction via nose and midpoints
        nose_idx = 1
        nose = pts[nose_idx]
        face_center = pts[1]  # simple proxy
        # rudimentary head pose proxy: nose x shift relative to center
        head_offset_x = float(nose[0] - (w / 2)) / w

        return {
            "face_detected": True,
            "left_ear": left_ear,
            "right_ear": right_ear,
            "ear": ear,
            "head_offset_x": head_offset_x
        }

if __name__ == "__main__":
    import sys, json
    path = sys.argv[1] if len(sys.argv) > 1 else "../../data/samples/driver_1.jpg"
    with open(path, "rb") as f:
        b64 = base64.b64encode(f.read()).decode("utf-8")
    print(json.dumps(analyze_face_from_b64(b64), indent=2))
