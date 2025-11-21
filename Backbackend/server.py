import asyncio
import websockets
import json
import base64
import cv2
import numpy as np
from detection import HOLISTIC, is_driver_distracted, is_driver_drowsy

async def handler(websocket, path):
    print(f"Client connected on path: {path}")

    if path != "/ws":
        print(f"Rejected connection on unexpected path: {path}")
        return

    async for message in websocket:
        try:
            data = json.loads(message)
            if 'camera' not in data or 'frame' not in data:
                continue

            frame_bytes = base64.b64decode(data['frame'])
            np_arr = np.frombuffer(frame_bytes, np.uint8)
            frame = cv2.imdecode(np_arr, cv2.IMREAD_COLOR)
            if frame is None:
                continue

            alert = None
            if data['camera'] == 'driver':
                # Recolor BGR to RGB for MediaPipe
                image_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
                results = HOLISTIC.process(image_rgb)

                alert_msg = None
                if is_driver_distracted(results.pose_landmarks):
                    alert_msg = "Distracted (Head Tilt)"
                else:
                    alert_msg = is_driver_drowsy(results.face_landmarks)
                    if alert_msg is None:
                        alert_msg = "OK"

                alert = {
                    'camera': 'driver',
                    'status': alert_msg,
                    'critical': alert_msg != "OK"
                }

            # Optional: Road camera logic
            # elif data['camera'] == 'road':
            #     alert = {'camera': 'road', 'status': 'Monitoring', 'critical': False}

            if alert:
                await websocket.send(json.dumps(alert))

        except json.JSONDecodeError:
            print("Invalid JSON received")
        except Exception as e:
            print(f"Error during processing: {e}")

# Start WebSocket server
start_server = websockets.serve(handler, "0.0.0.0", 8765, path="/ws")
print("Backend running on ws://0.0.0.0:8765/ws")

asyncio.get_event_loop().run_until_complete(start_server)
asyncio.get_event_loop().run_forever()
