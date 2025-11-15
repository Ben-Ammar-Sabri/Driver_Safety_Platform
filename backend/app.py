from flask import Flask, request, jsonify
from flask_cors import CORS
import base64
import numpy as np
import cv2

app = Flask(__name__)
CORS(app)  # autoriser Flutter

def analyze_driver(frame_bytes, sensors, gps):
    # Décodage image
    nparr = np.frombuffer(frame_bytes, np.uint8)
    img = cv2.imdecode(nparr, cv2.IMREAD_COLOR)

    # Exemple simple : si la personne est fatiguée (dummy)
    fatigue_level = int(np.random.randint(5, 30))  # simuler

    # Exemple distraction
    distraction = int(np.random.randint(0, 15))

    # Combiner avec sensors et GPS si besoin
    # accel = sensors.get('accelerometer')
    # gps_speed = gps.get('speed')

    return {"fatigue_level": fatigue_level, "distraction": distraction}

def analyze_road(frame_bytes, sensors, gps):
    # Décodage image
    nparr = np.frombuffer(frame_bytes, np.uint8)
    img = cv2.imdecode(nparr, cv2.IMREAD_COLOR)

    # Dummy road safety score
    road_score = int(np.random.randint(50, 100))

    return {"road_score": road_score}

@app.route("/analyze", methods=["POST"])
def analyze():
    data = request.get_json()

    frame_type = data.get("type")
    frame_b64 = data.get("frame")
    sensors = data.get("sensors")
    gps = data.get("gps")

    frame_bytes = base64.b64decode(frame_b64)

    if frame_type == "driver":
        result = analyze_driver(frame_bytes, sensors, gps)
    elif frame_type == "road":
        result = analyze_road(frame_bytes, sensors, gps)
    else:
        return jsonify({"error": "Unknown type"}), 400

    return jsonify(result)

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)
""" 
from flask import Flask, request, jsonify
from flask_cors import CORS
import base64
import numpy as np
import cv2

# Import AI modules
from ai_fatigue import detect_fatigue
from models.road_model import analyze_road_image
from utils.alerts import evaluate_driver_alert
from utils.preprocessing import decode_image

app = Flask(__name__)
CORS(app)  # autoriser Flutter

# -----------------------------
# Endpoint principal
# -----------------------------
@app.route("/analyze", methods=["POST"])
def analyze():
    data = request.get_json()

    frame_type = data.get("type")
    sensors = data.get("sensors")
    gps = data.get("gps")
    frame_b64 = data.get("frame")

    if not frame_b64:
        return jsonify({"error": "No frame provided"}), 400

    try:
        frame_bytes = base64.b64decode(frame_b64)
    except Exception as e:
        return jsonify({"error": f"Invalid base64: {e}"}), 400

    img = decode_image(frame_bytes)

    if frame_type == "driver":
        # Analyse fatigue avec Mediapipe EAR
        res = detect_fatigue(img)
        alert = evaluate_driver_alert(res["fatigue"], 0)  # distraction = 0 pour l'instant
        res["alert"] = alert

    elif frame_type == "road":
        res = analyze_road_image(img)
    else:
        return jsonify({"error": "Unknown type"}), 400

    return jsonify(res)

# -----------------------------
# Main
# -----------------------------
if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)
"""
