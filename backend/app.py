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
# app.py
from flask import Flask, request, jsonify
from flask_cors import CORS
import base64
import numpy as np
import cv2
from ai_fatigue import detect_fatigue
from ai_road import analyze_road_image

app = Flask(__name__)
CORS(app)  # autoriser Flutter à appeler l'API

def decode_image(frame_bytes):
    """
    Convertit les bytes en image OpenCV
    """
    nparr = np.frombuffer(frame_bytes, np.uint8)
    img = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
    return img

@app.route("/analyze", methods=["POST"])
def analyze():
    """
    Endpoint pour analyser driver ou road
    JSON attendu:
    {
        "type": "driver" ou "road",
        "frame": "<image en base64>",
        "sensors": {...},   # facultatif
        "gps": {...}        # facultatif
    }
    """
    data = request.get_json()

    frame_type = data.get("type")
    frame_b64 = data.get("frame")
    sensors = data.get("sensors", {})
    gps = data.get("gps", {})

    if not frame_b64:
        return jsonify({"error": "No frame provided"}), 400

    # Décoder l'image
    frame_bytes = base64.b64decode(frame_b64)
    img = decode_image(frame_bytes)

    # Analyse selon le type
    if frame_type == "driver":
        result = detect_fatigue(img)
        # Ajouter éventuellement les capteurs/GPS au résultat
        result.update({"sensors": sensors, "gps": gps})

    elif frame_type == "road":
        result = analyze_road_image(img)
        result.update({"sensors": sensors, "gps": gps})

    else:
        return jsonify({"error": "Unknown type"}), 400

    return jsonify(result)

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)

"""
