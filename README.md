# 🚗 Haniny - Driver Safety Platform

An intelligent, AI-powered driver monitoring solution designed to improve road safety through **real-time analysis** of driving behavior and road conditions.  

Haniny combines a **mobile app prototype**, **Python AI backend**, automated workflows, and a **web dashboard** for insurers, fleet managers, and families.

---

## 1. The Problem

Road accidents are commonly caused by:  
- Driver distraction  
- Fatigue or drowsiness  
- Overspeeding  

Additional challenges:  
- Lack of real-time driving behavior analysis tools  
- Insurers and fleet companies lack reliable incident data  
- Existing solutions rely too heavily on manual driver input  

➡️ **There is a strong need for an automatic, autonomous, and intelligent driver safety system.**

---

## 2. Our Solution: Haniny

A complete end-to-end platform consisting of:

### 🔹 1. Mobile App Prototype (replaces embedded hardware for testing)
- **Front-facing camera:** monitors driver attention, fatigue, and yawning  
- **Rear/road-facing camera:** detects obstacles and monitors safe distance  
- **Phone sensors:** GPS, accelerometer, gyroscope for telematics data  
- **Real-time data streaming:** sends frames and sensor data to backend via **WebSockets**  

> In production, this will be replaced by a dedicated **in-vehicle hardware module**, while the backend and AI engine remain the same.

### 🔹 2. Python AI Backend
- WebSocket server receives camera frames and sensor data  
- Uses **MediaPipe Face Mesh** and custom detection logic to monitor:  
  - Eye closure (drowsiness detection)  
  - Yawning (alert for fatigue)  
- Computes **driver safety score**  
- Generates **real-time alerts** for unsafe behavior  

### 🔹 3. Automated Workflow
- Ingests real-time data from mobile app or hardware module  
- Processes images through AI pipeline  
- Computes safety scores and logs events  
- Sends alerts automatically to dashboard or external systems  

### 🔹 4. Web Dashboard
- Displays **recent alerts** and driving events  
- Monitors **vehicle health** and trip history  
- Provides **AI-driven recommendations** for safe driving  

---

## 3. Architecture Overview

