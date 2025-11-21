import mediapipe as mp
import numpy as np
from face_utils import get_aspect_ratio
from config import HEAD_TILT_THRESHOLD, EAR_THRESHOLD, MAR_THRESHOLD, FRAME_COUNT_LIMIT

# Initialize Holistic globally
mp_holistic = mp.solutions.holistic
HOLISTIC = mp_holistic.Holistic(min_detection_confidence=0.5,
                                min_tracking_confidence=0.5)

# Keep track of consecutive frame counts
frame_count_dict = {'eye': 0, 'yawn': 0}

# ----------------- Detection Functions -----------------
def is_driver_distracted(pose_landmarks):
    if pose_landmarks is None:
        return False
    left_eye = pose_landmarks.landmark[mp_holistic.PoseLandmark.LEFT_EYE]
    right_eye = pose_landmarks.landmark[mp_holistic.PoseLandmark.RIGHT_EYE]
    angle = np.arctan2(right_eye.y - left_eye.y, right_eye.x - left_eye.x) * 180 / np.pi
    return abs(angle) > HEAD_TILT_THRESHOLD

def is_driver_drowsy(face_landmarks):
    """
    Returns a string alert or None
    """
    if face_landmarks is None:
        return None

    # Eye Aspect Ratio
    ear_left = get_aspect_ratio(face_landmarks, 'left_eye')
    ear_right = get_aspect_ratio(face_landmarks, 'right_eye')
    ear = (ear_left + ear_right) / 2.0

    # Mouth Aspect Ratio
    mar = get_aspect_ratio(face_landmarks, 'mouth')

    alert_msg = None

    # Check eye closure
    if ear < EAR_THRESHOLD:
        frame_count_dict['eye'] += 1
    else:
        frame_count_dict['eye'] = 0

    # Check yawning
    if mar > MAR_THRESHOLD:
        frame_count_dict['yawn'] += 1
    else:
        frame_count_dict['yawn'] = 0

    if frame_count_dict['eye'] > FRAME_COUNT_LIMIT:
        alert_msg = "Drowsy: Eyes closed"
    elif frame_count_dict['yawn'] > FRAME_COUNT_LIMIT:
        alert_msg = "Drowsy: Yawning"

    return alert_msg
