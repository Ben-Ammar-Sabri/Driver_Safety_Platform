# ai_road.py
import cv2
import numpy as np

def analyze_road_image(img):
    """
    Analyse simple de la route pour prototype.
    - Entrée : image BGR (OpenCV)
    - Sortie : dict avec score et alerte
    """
    # Convertir en gris
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)

    # Détecter les bords
    edges = cv2.Canny(gray, 50, 150)

    # Calculer un score simple : plus de bords -> risque plus élevé
    road_score = max(50, 100 - int(np.mean(edges)))

    # Déterminer l'alerte
    alert = "ROAD_RISK_HIGH" if road_score < 60 else "ROAD_RISK_LOW"

    return {
        "road_score": road_score,
        "alert": alert
    }
