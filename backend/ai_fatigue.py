import cv2
import numpy as np
import mediapipe as mp

mp_face_mesh = mp.solutions.face_mesh

LEFT_EYE = [33, 160, 158, 133, 153, 144]
RIGHT_EYE = [263, 387, 385, 362, 380, 373]

def euclidean_dist(a, b):
    return np.linalg.norm(a - b)

def eye_aspect_ratio(landmarks, eye_points):
    p1 = np.array([landmarks[eye_points[1]].x, landmarks[eye_points[1]].y])
    p2 = np.array([landmarks[eye_points[5]].x, landmarks[eye_points[5]].y])
    p3 = np.array([landmarks[eye_points[2]].x, landmarks[eye_points[2]].y])
    p4 = np.array([landmarks[eye_points[4]].x, landmarks[eye_points[4]].y])
    p5 = np.array([landmarks[eye_points[0]].x, landmarks[eye_points[0]].y])
    p6 = np.array([landmarks[eye_points[3]].x, landmarks[eye_points[3]].y])
    return (euclidean_dist(p1, p2) + euclidean_dist(p3, p4)) / (2 * euclidean_dist(p5, p6))

def detect_fatigue(img):
    img_rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
    with mp_face_mesh.FaceMesh(max_num_faces=1, refine_landmarks=True,
                               min_detection_confidence=0.5,
                               min_tracking_confidence=0.5) as face_mesh:
        output = face_mesh.process(img_rgb)
        if not output.multi_face_landmarks:
            return {"fatigue": 0, "status": "no_face"}
        landmarks = output.multi_face_landmarks[0].landmark
        ear_left = eye_aspect_ratio(landmarks, LEFT_EYE)
        ear_right = eye_aspect_ratio(landmarks, RIGHT_EYE)
        ear = (ear_left + ear_right) / 2.0
        if ear < 0.20:
            return {"fatigue": 100, "status": "eyes_closed"}
        elif ear < 0.25:
            return {"fatigue": 60, "status": "drowsy"}
        else:
            return {"fatigue": 10, "status": "awake"}
