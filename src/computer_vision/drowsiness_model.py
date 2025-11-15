import time

# thresholds - tune these in real data
EAR_SLEEP_THRESHOLD = 0.18   # lower EAR -> eyes closed
CONSEC_FRAMES_SLEEP = 3      # number of consecutive frames to consider a blink/closure

def drowsiness_from_face(face_metrics):
    """
    face_metrics: result from face_tracking.analyze_face_from_b64
    returns: dict {drowsy:bool, score:0-100, reason:str}
    """
    if not face_metrics.get("face_detected"):
        return {"drowsy": False, "score": 50, "reason": "no_face_detected"}

    ear = face_metrics.get("ear", 0.3)
    # interpret EAR
    # smaller ear => eyes closed; map to score
    if ear < EAR_SLEEP_THRESHOLD:
        # strong drowsiness signal
        score = max(0, int(100 - (EAR_SLEEP_THRESHOLD - ear) * 1000))
        return {"drowsy": True, "score": score, "reason": f"low_ear:{ear:.3f}"}
    else:
        score = int(100 - max(0, (0.4 - ear) * 200))  # neutral mapping
        return {"drowsy": False, "score": score, "reason": f"ear_ok:{ear:.3f}"}
