import cv2
import numpy as np

def analyze_road_image(img):
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)

    # Detect edges (simulates lane/obstacle detection)
    edges = cv2.Canny(gray, 50, 150)

    edge_intensity = np.mean(edges)

    road_score = int(max(50, min(100, 100 - edge_intensity / 3)))

    return {
        "road_score": road_score,
        "status": "ok"
    }
