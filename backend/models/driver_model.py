import cv2
import numpy as np

# Load Haar Cascade models (OpenCV built-in)
face_cascade = cv2.CascadeClassifier(cv2.data.haarcascades + "haarcascade_frontalface_default.xml")
eye_cascade = cv2.CascadeClassifier(cv2.data.haarcascades + "haarcascade_eye.xml")

def analyze_driver_image(img):
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)

    faces = face_cascade.detectMultiScale(gray, 1.1, 4)

    if len(faces) == 0:
        return {"fatigue_level": 0, "distraction": 10, "status": "no_face_detected"}

    # Assume 1 face
    (x, y, w, h) = faces[0]
    roi_gray = gray[y:y+h, x:x+w]

    eyes = eye_cascade.detectMultiScale(roi_gray)

    fatigue_level = 5
    distraction = 5

    if len(eyes) < 2:
        fatigue_level = 90  # eyes closed
    else:
        fatigue_level = 10  # eyes open

    return {
        "fatigue_level": fatigue_level,
        "distraction": distraction,
        "status": "ok"
    }
