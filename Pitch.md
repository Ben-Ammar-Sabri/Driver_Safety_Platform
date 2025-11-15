The Driver Safety Platform is an AI-powered solution designed to monitor driving behavior and road conditions in real time. 
Our goal is simple: reduce accidents by giving insurers, fleets, and families reliable and automatic safety insights.
The system combines three major elements. First, an embedded module that uses cameras and sensors to capture key driving data: driver distraction, fatigue, road obstacles, speed, and harsh braking. 
In our prototype, this data is fully simulated.
Second, an AI backend processes all inputs. Vision models analyze the driver and the road, while behavioral models compute a Safety Score based on distraction, fatigue, speed, braking, and environmental risk. 
If the score drops below a threshold, the system immediately generates an alert.
The third component is n8n, which acts as the automation core of our prototype. 
It receives simulated sensor data, sends it to the AI, calculates the score, stores results, and triggers alerts—all without any human interaction.
Finally, our web dashboard provides a clear overview for managers and insurers: real-time score, recent alerts, vehicle status, trip history, and AI recommendations.
The Driver Safety Platform is scalable, low‑cost, and ready to integrate with real hardware. The next step is connecting an actual dashcam and telematic sensors to create a fully operational safety device.
