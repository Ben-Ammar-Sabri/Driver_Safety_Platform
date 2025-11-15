def evaluate_driver_alert(fatigue, distraction):
    # seuils simples
    if fatigue > 70:
        return "FATIGUE_HIGH"
    elif fatigue > 40:
        return "FATIGUE_MEDIUM"
    else:
        return "FATIGUE_LOW"
