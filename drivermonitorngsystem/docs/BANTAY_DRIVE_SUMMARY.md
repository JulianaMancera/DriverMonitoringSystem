# Bantay Drive — Project File Summary

**Bantay Drive** is a real-time mobile driver monitoring system developed as an undergraduate thesis at New Era University (2026) by **Pia Katleya V. Macalanda** and **Juliana R. Mancera**. It uses an on-device deep learning model to detect drowsiness and distraction — fully offline, no internet required.

---

## Project Structure at a Glance

```
drivermonitorngsystem/
├── lib/
│   ├── main.dart
│   ├── core/
│   │   ├── database/
│   │   ├── inference/
│   │   ├── services/
│   │   ├── preference/
│   │   ├── providers.dart
│   │   └── session_state.dart
│   ├── screens/
│   ├── widgets/
│   └── utils/
├── assets/
│   ├── models/
│   └── [audio, images, normalization params]
└── pubspec.yaml
```

---

## DART FILES

### App Entry

| File | Role |
|------|------|
| `lib/main.dart` | App shell. Handles device brand detection (Samsung/MIUI/ColorOS scaling), splash → onboarding → main navigation state machine, and the bottom navigation bar with 5 screens. |

---

### Core — Inference (AI Engine)

| File | Role |
|------|------|
| `lib/core/inference/tflite_service.dart` | The brain of the app. Runs the DMS-HybridNet V3 model on camera frames. Handles YUV→RGB conversion, 224×224 resize, float32 normalization, frame skipping (~5 FPS), NNAPI/CPU fallback, 13-class behavior detection, debouncing logic, and yaw compensation for right-side phone mount. |
| `lib/core/services/head_pose_service.dart` | Uses Google ML Kit Face Detection to extract head pose (pitch/yaw/roll), Eye Aspect Ratio (EAR), Mouth Aspect Ratio (MAR), and facial landmarks (gaze, wrist, shoulder positions) — used as the 25-feature input vector for the model. |

---

### Core — Database

| File | Role |
|------|------|
| `lib/core/database/database_helper.dart` | SQLite database with 6 tables: `sessions`, `state_counts`, `alert_events`, `system_logs`, `alertness_snapshots`, `video_clips`. Handles all CRUD operations, schema migrations (v4), and data retention enforcement. |
| `lib/core/database/db_change_notifier.dart` | Riverpod reactive notifier that triggers UI rebuilds whenever the database changes (new session, alert, or log entry). |

---

### Core — State & Services

| File | Role |
|------|------|
| `lib/core/providers.dart` | All Riverpod state providers: driver state (neutral/drowsy/distracted), alertness percentages, recording status, alert banner visibility, PiP mode, active behavior subclass. |
| `lib/core/session_state.dart` | Persists active session ID and start time via SharedPreferences so session data survives PiP transitions, isolate restarts, and app backgrounding. |
| `lib/core/services/notifications.dart` | Manages the Android foreground service with a persistent notification showing live driver state and a Stop button. Throttles updates to every 2 seconds to avoid dropped taps. |
| `lib/core/services/pip_service.dart` | Picture-in-Picture mode so monitoring continues in a floating window when the user navigates away or presses home. |
| `lib/core/services/video_clip_service.dart` | Records and saves 10-second alert clips to app-private storage. Validates disk space (50 MB minimum) before writing, verifies file existence and size post-copy, and handles bulk export to the Downloads folder. |
| `lib/core/preference/preference_helper.dart` | SharedPreferences wrapper for user settings: alert sensitivity, auto-start toggle, session retention policy, and onboarding completion status. |

---

### Screens

| File | Role |
|------|------|
| `lib/screens/splash_screen.dart` | Animated splash screen on first launch showing Bantay Drive branding; transitions to onboarding or main app. |
| `lib/screens/onboarding_screen.dart` | First-launch walkthrough introducing app features. Shown only once (persisted via SharedPreferences). |
| `lib/screens/monitor_screen.dart` | **Core screen.** Live camera feed + real-time AI inference. Implements the 3-level escalating alert system (L1 = slide-in banner, L2 = persistent warning, L3 = full-screen blocking alarm). Manages session recording, foreground service, and PiP mode. |
| `lib/screens/dashboard_screen.dart` | Home screen with circular Safety Score (0–100, color-coded), 4 stat cards (Total Drive Time, Alerts, Safety Streak, Avg Alertness), and a 30-day safety score line chart. Auto-refreshes every 30 seconds. |
| `lib/screens/analytics_screen.dart` | Trend analysis with 7-day/30-day/all-time filters, summary cards, drowsiness vs. distraction daily line chart, and hourly alert distribution bar chart. |
| `lib/screens/history_screen.dart` | Two-tab screen: **Session Logs** — date-grouped session list with search and filters (date range, detection type, alert level); tap a session to see alertness timeline, alert events, system log, and linked clips. **Video Logs** — all saved alert clips with thumbnail, duration, alert type; supports multi-select bulk export to Downloads, in-app playback (non-mirrored), and swipe-to-delete. |
| `lib/screens/settings_screen.dart` | App configuration: alert volume slider, sensitivity (Low/Medium/High), auto-start toggle, show session summary toggle, data retention policy (7 Days/30 Days/90 Days/Forever), clear all history, and About section with authors. |

---

### Widgets & Utils

| File | Role |
|------|------|
| `lib/widgets/head_pose_indicator.dart` | Color-coded ring widget on the monitor screen (green/yellow/red/dashed) showing the driver's current head orientation (yaw/roll as angle and rotation) as real-time alignment feedback. |
| `lib/widgets/exit.dart` | Exit confirmation dialog to prevent accidental app closure; stops the foreground service and clears recording state before exiting. |
| `lib/utils/responsive.dart` | OEM-specific UI scaling utilities. Applies multipliers per brand: Samsung (0.95×), MIUI/OPPO/Vivo (0.97×), stock Android (1.0×) for text, padding, sizes, icons, and border radii. |

---

## ASSET FILES

| File | Role |
|------|------|
| `assets/models/dms_hybridnet_v3_float32.tflite` | The TFLite model. Hybrid CNN-BiLSTM-Attention architecture combining EfficientNet-B0 (face), Eye MicroCNN (eyes), and MobileNetV3-Small (upper body) with BiLSTM temporal modeling and Multi-head Attention. Outputs 13 behavior classes from a 224×224 image + 25 geometric features. |
| `assets/norm_params.json` | Mean and scale normalization parameters for the 25 input features (EAR, MAR, head pose, gaze, wrist/shoulder positions, temporal trends) — required before feeding features into the model. |
| `assets/L1_L2_sound.mp3` | Audio alert used for Level 1 and Level 2 alerts. L1 plays it once; L2 plays it 3× consecutively via a dedicated secondary audio player (`_alarmPlayer`). |
| `assets/L3_critical_alert.wav` | Looping alarm played during Level 3 full-screen blocking alert requiring manual dismissal. |
| `assets/bantay_drive_logo.png` | Main app logo used in splash and onboarding screens. |
| `assets/text_logo.png` | Text-based "Bantay Drive" logo variant used in UI. |
| `assets/car.png` | Car illustration used in dashboard or onboarding screens. |

---

## CONFIGURATION & DOCUMENTATION FILES

| File | Role |
|------|------|
| `pubspec.yaml` | Project manifest declaring 24+ dependencies: `tflite_flutter` (inference), `google_mlkit_face_detection` (face landmarks), `sqflite` (database), `flutter_riverpod` (state), `flutter_foreground_task` (background service), `audioplayers` (alerts), `fl_chart` (charts), and more. |
| `DETECTION_THRESHOLDS.md` | Documents per-class confidence thresholds for all 13 behavior classes, global detection gates, and debouncing logic. |
| `QUICK_REFERENCE.md` | Threshold tuning guide with old vs. new comparisons, debug log cheat sheet, and instructions for reducing false positives/negatives. |
| `TESTING_GUIDE.md` | Testing procedures and troubleshooting steps for the detection pipeline. |
| `README.md` | Full project documentation: architecture, features, authors, and installation steps. |

---

## Model Architecture — DMS-HybridNet V3

```
Input 1: 224×224 RGB face image
  ├── EfficientNet-B0         → full face spatial features
  ├── Eye MicroCNN            → periocular / eye region features
  └── MobileNetV3-Small       → upper body / hand features

Input 2: 25-dimensional feature vector
  (EAR, MAR, head pose, gaze, wrist/shoulder positions, temporal trends)

Combined → BiLSTM (temporal modeling, 20-frame window)
         → Multi-head Attention (occlusion-tolerant frame weighting)
         → 13-class softmax output
```

### 13 Behavior Classes

| Category | Classes |
|----------|---------|
| **Natural** | Safe Driving, Talking to Passenger |
| **Drowsy** | Yawning, Yawning (Occluded), Fatigue, Microsleep |
| **Distracted** | Texting, Phone Call, Radio, Drinking, Body/Reaching, Grooming, Smoking |

### Training Datasets

| Purpose | Datasets |
|---------|---------|
| Drowsiness | MRL Eye, YawDD, UTA-RLDD |
| Distraction | State Farm, AUC Distracted Driver v2 |

---

## Alert System

| Level | Trigger | UI | Audio |
|-------|---------|-----|-------|
| **L1** | Initial detection | Slide-in banner (top of screen, auto-dismisses) | `L1_L2_sound.mp3` plays once |
| **L2** | Sustained or repeated detection | Persistent warning banner | `L1_L2_sound.mp3` plays 3× consecutively via `_alarmPlayer` |
| **L3** | Critical / driver unresponsive | Full-screen blocking overlay (manual dismiss required) | `L3_critical_alert.wav` loops until dismissed |

---

## Key Features

| Feature | Implementation |
|---------|---------------|
| Real-Time Detection | DMS-HybridNet V3 TFLite model (224×224 RGB + 25 features) at ~5 FPS |
| 3-Level Alert System | Escalating L1 → L2 → L3 with distinct audio and visual alerts |
| Video Clip Recording | Auto-records 10-second alert clips on L2/L3; stored in app-private storage with export to Downloads |
| Background Monitoring | Android foreground service with persistent notification |
| Picture-in-Picture | Monitoring continues in floating window when app is minimized |
| Database | SQLite v4 with 6 tables for sessions, alerts, logs, snapshots, and video clips |
| Analytics Dashboard | Safety score ring, trend charts, hourly distribution |
| Session History | Two-tab view: session logs with search/filters + video logs with bulk export |
| Sensitivity Control | Low / Medium / High with adjustable frame thresholds |
| Responsive Design | OEM-specific scaling for Samsung, MIUI, ColorOS, stock Android |
| Fully Offline | All inference runs on-device — no internet required |

---

*Bantay Drive — Real-Time Driver Monitoring System*
*New Era University, 2026*
*Pia Katleya V. Macalanda & Juliana R. Mancera*
