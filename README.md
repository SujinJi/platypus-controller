# 🦆 Platypus Robot Controller App

A Flutter-based mobile controller for the Platypus robot — a Raspberry Pi–powered quadruped that responds to its owner's voice, face, and touch.

> **This app is one half of a full-stack robotics system.**  
> The other half is the [Platypus Robot firmware](https://github.com/SujinJi/platypus-app-and-robot) running on Raspberry Pi.

---

## Screenshots

> _(Add screenshots here — Home screen / Owner registration / Status dashboard)_

---

## Features

### Owner Registration (3-Step Flow)
- **Step 1 — Voice Training**: Reads 3 custom scripts aloud; recognized via `speech_to_text`
- **Step 2 — Face Capture**: Takes a front-camera photo and extracts facial landmarks (eye distance, eye-to-nose ratio) using **Google ML Kit**
- **Step 3 — Save**: Stores owner profile with name, voice pitch, and face features

### MQTT Communication
- Connects to the robot over **MQTT** (`test.mosquitto.org`)
- Sends real-time control commands to `robot/control` topic
- Subscribes to `robot/status` topic for live feedback
- **Dummy mode**: App stays fully functional even without hardware connected

### Robot Status Dashboard
- Real-time monitoring of battery, temperature, network, and sensor health
- Color-coded status cards (Excellent → Critical) with animated transitions
- Auto-refreshes every 3 seconds
- Warning snackbar when sensor enters critical state

### GPS Location Tracking
- Fetches robot's current GPS coordinates via `geolocator`
- Displays latitude, longitude, and accuracy

---

## Architecture

```
┌─────────────────────────────────────┐
│           Flutter App               │
│                                     │
│  HomeMenuScreen (main.dart)         │
│  ├── MultiOwnerControlScreen        │  ← owner_manager.dart
│  │   ├── Voice Training (STT)       │
│  │   ├── Face Capture (ML Kit)      │
│  │   └── GPS Tracking               │
│  └── RobotStatusScreen              │  ← robot_status.dart
│      └── Live sensor dashboard      │
│                                     │
│  MqttManager (mqtt_manager.dart)    │  ← MQTT bridge
│  RobotData   (robot_model.dart)     │  ← Data model
└──────────────┬──────────────────────┘
               │ MQTT (port 1883)
               ▼
┌─────────────────────────────────────┐
│     Platypus Robot (Raspberry Pi)   │
│     C firmware + pigpio             │
└─────────────────────────────────────┘
```

---

## Tech Stack

| Category | Technology |
|---|---|
| Framework | Flutter 3.x (Dart) |
| Communication | MQTT (`mqtt_client ^10.2.0`) |
| Face Detection | Google ML Kit (`google_mlkit_face_detection ^0.13.2`) |
| Voice Recognition | `speech_to_text ^7.3.0` |
| Camera | `camera ^0.12.0` |
| Location | `geolocator ^14.0.2` |
| Auth | `local_auth ^2.1.6` |
| Permissions | `permission_handler ^12.0.1` |

---

## Getting Started

### Prerequisites
- Flutter SDK `^3.11.1`
- Android or iOS device/emulator
- (Optional) Platypus Robot hardware for full functionality

### Installation

```bash
git clone https://github.com/SujinJi/platypus-controller.git
cd platypus-controller
flutter pub get
flutter run
```

### Running Without Hardware
The app launches in **Dummy Mode** automatically if the MQTT broker is unreachable.  
All UI features (owner registration, status dashboard) work normally without a physical robot.

---

## Project Structure

```
platypus-controller/
├── main.dart           # App entry, HomeMenuScreen UI & navigation
├── mqtt_manager.dart   # MQTT connection, publish & subscribe logic
├── owner_manager.dart  # Owner registration flow (voice + face + GPS)
├── robot_model.dart    # RobotData JSON model
├── robot_status.dart   # Real-time status dashboard screen
└── pubspec.yaml        # Dependencies
```

---

## Related Repository

| Repo | Description |
|---|---|
| [platypus-app-and-robot](https://github.com/SujinJi/platypus-app-and-robot) | C firmware for Raspberry Pi — servo control, sensor reading, state machine |

---

## Author

**Sujin Ji** — Embedded systems & Flutter developer  
📧 suj50737@gmail.com 
🔗 [GitHub](https://github.com/SujinJi)
