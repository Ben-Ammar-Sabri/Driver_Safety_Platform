import cv2
from scipy.spatial import distance as dis

# Helper to calculate Euclidean distance between 2 points
def euclidean_distance(image, top, bottom):
    h, w = image.shape[:2]
    p1 = int(top.x * w), int(top.y * h)
    p2 = int(bottom.x * w), int(bottom.y * h)
    return dis.euclidean(p1, p2)

# Aspect ratio function for EAR/MAR
def get_aspect_ratio(face_landmarks, part, image=None):
    """
    part: 'left_eye', 'right_eye', 'mouth'
    image: optional, used if coordinates are normalized
    """
    if part == 'left_eye':
        top, bottom = 386, 374
        left, right = 263, 362
    elif part == 'right_eye':
        top, bottom = 159, 145
        left, right = 133, 33
    elif part == 'mouth':
        top, bottom = 13, 14
        left, right = 78, 308
    else:
        raise ValueError("Unknown part")

    if image is None:
        # landmarks already normalized -> simple distance
        top_pt = face_landmarks.landmark[top]
        bottom_pt = face_landmarks.landmark[bottom]
        left_pt = face_landmarks.landmark[left]
        right_pt = face_landmarks.landmark[right]
    else:
        # Use pixel coordinates
        h, w = image.shape[:2]
        top_pt = face_landmarks.landmark[top]
        bottom_pt = face_landmarks.landmark[bottom]
        left_pt = face_landmarks.landmark[left]
        right_pt = face_landmarks.landmark[right]

    top_bottom_dist = dis.euclidean((top_pt.x, top_pt.y), (bottom_pt.x, bottom_pt.y))
    left_right_dist = dis.euclidean((left_pt.x, left_pt.y), (right_pt.x, right_pt.y))

    return left_right_dist / top_bottom_dist