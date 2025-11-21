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

- **Flutter App:** captures camera frames, telematics, and sends to backend  
- **Python Backend:** processes frames, calculates EAR/MAR, triggers alerts  
- **Dashboard / Workflow:** logs events, computes safety metrics, sends recommendations  

---

## 4. Key Features

- **Driver monitoring:** real-time drowsiness and distraction detection  
- **Road safety monitoring:** obstacle and lane tracking (future hardware upgrade)  
- **Real-time alerts:** via WebSocket to app and dashboard  
- **Data logging:** for fleet managers, insurers, or family monitoring  
- **Safety score:** aggregated per trip and driver behavior  
- **Eco-driving guidance:** encourage fuel-efficient driving  
- **Prototype ready:** fully functional mobile app prototype for testing  

---

## 5. Prototype Note

The **mobile app** replaces hardware for testing purposes:  
- Utilizes front & rear cameras  
- Leverages phone sensors (accelerometer, GPS, gyroscope)  
- Streams all data to backend in real-time  

In production, the mobile app is swapped with **embedded vehicle hardware** while the backend AI engine and dashboard remain unchanged.  

---

## 6. Impact

Haniny provides:  
- **Accident reduction** through AI monitoring  
- **Lower insurance costs** with reliable driver behavior metrics  
- **24/7 automated monitoring** without manual intervention  
- **Eco-driving guidance** for efficient and safe trips  
- **Early detection of mechanical issues** from telematics  
- **Improved safety** for families, fleets, and insurers  

---

## 7. Tech Stack

- **Mobile App:** Flutter  
- **Backend:** Python 3, asyncio, WebSockets, OpenCV, MediaPipe  
- **AI Engine:** Drowsiness and yawning detection (EAR/MAR-based)  
- **Dashboard / Logging:**(database)  

---
