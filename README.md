<div align="center">
<h1>🚗 Bantay Drive — Real-Time Driver Monitoring System</h1>
</div>

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.16+-02569B?style=for-the-badge&logo=flutter&logoColor=white"/>
  <img src="https://img.shields.io/badge/Dart-3.x-0175C2?style=for-the-badge&logo=dart&logoColor=white"/>
  <img src="https://img.shields.io/badge/TFLite-DMS--HybridNet-FF6F00?style=for-the-badge&logo=tensorflow&logoColor=white"/>
  <img src="https://img.shields.io/badge/Platform-Android%208.0+-3DDC84?style=for-the-badge&logo=android&logoColor=white"/>
  <img src="https://img.shields.io/badge/Status-In%20Development-yellow?style=for-the-badge"/>
</p>

<div align="center">
  <h2>Undergraduate Thesis Project — New Era University, 2026</h2>
  <h4>Authors: Macalanda, Pia Katleya V. & Mancera, Juliana R.</h4>
</div>

---

## 📖 About

**Bantay Drive** is a mobile-based real-time driver monitoring system powered by an on-device deep learning model. It uses the front-facing camera to detect drowsiness and distraction in real time, escalating alerts before dangerous situations occur — entirely offline, no internet connection required.

> *"DMS-HybridNet: A Hybrid CNN-BiLSTM-Attention Architecture for Real-Time Driver Monitoring Under Low-Light and Occlusion Conditions via Mobile-Based Computer Vision"*

---

## ✨ Features

### 📷 Real-Time Monitoring
- On-device TFLite inference (NNAPI → CPU fallback) — no server required
- **3-level escalating alert system:**
  - **Level 1** — Slide-in audio banner (auto-dismisses)
  - **Level 2** — Persistent banner with audio
  - **Level 3** — Full-screen blocking alarm overlay, requires manual dismissal
- Configurable alert sensitivity:

| Sensitivity | L1 | L2 | L3 |
|-------------|----|----|-----|
| Low         | 5 frames | 10 frames | 15 frames |
| Medium      | 3 frames | 6 frames  | 9 frames  |
| High        | 2 frames | 4 frames  | 6 frames  |

- **Head-pose visual indicator** — real-time circle overlay tracking driver head rotation
- **Video clip capture** — automatically records and saves clips when alerts trigger
- **Picture-in-Picture (PiP)** — monitoring continues in a floating window when app is backgrounded
- Foreground service with persistent notification showing live driver state + Stop button
- Clear Glasses toggle, Auto-start recording option

### 📊 Dashboard
- Circular Safety Score (0–100), color-coded green / amber / red
- Stat cards: Total Drive Time, Alerts (last 24h), Safety Streak, Avg Alertness
- Safety Score History line chart (last 30 days, horizontally scrollable)

### 📈 Analytics
- Time filter: 7 Days / 30 Days / All Time
- Drowsiness vs. Distraction daily line chart + Hourly Alert Distribution bar chart

### 📋 History
- Chronological session list grouped by date with search and filter chips
- **Advanced filtering** for both session logs and video logs
- Session detail: state breakdown, alert events (L1/L2/L3), system log
- **In-app session video playback** (non-mirrored)

### ⚙️ Settings
- Alert volume, sensitivity, auto-start recording, data retention (7 Days / 30 Days / Forever)
- Clear all history with confirmation

---

## 🏗️ Architecture

```
lib/
├── core/
│   ├── database/
│   │   ├── database_helper.dart       # SQLite — 6 tables, schema v4, migrations
│   │   └── db_change_notifier.dart    # Riverpod reactive DB counter
│   ├── inference/
│   │   ├── tflite_service.dart        # Model loading, inference, 13-class mapping
│   │   └── frame_preprocessor.dart   # YUV→RGB, gamma LUT, resize, normalize
│   ├── preference/
│   │   └── preference_helper.dart    # SharedPreferences wrapper
│   ├── services/
│   │   ├── notifications.dart        # Foreground service + notification management
│   │   ├── head_pose_service.dart    # ML Kit head-pose & euler angle calculation
│   │   ├── pip_service.dart          # Picture-in-Picture control
│   │   └── video_clip_service.dart   # Alert video recording & clip management
│   ├── providers.dart                # Riverpod state providers
│   └── session_state.dart           # Session data container
├── screens/
│   ├── monitor_screen.dart           # Camera + inference + alerts + PiP + head-pose
│   ├── dashboard_screen.dart         # Safety score + charts
│   ├── analytics_screen.dart         # Trend charts
│   ├── history_screen.dart           # Session list + video playback + filters
│   ├── settings_screen.dart          # App settings
│   ├── onboarding_screen.dart        # First-launch walkthrough
│   └── splash_screen.dart
├── utils/
│   └── responsive.dart              # Breakpoints + brand-specific scaling
└── main.dart                         # App shell + IndexedStack + landscape sidebar
```

### 🗄️ Local Database (SQLite — 6 tables, schema v4)
- `sessions` — drive sessions with timestamps, safety score, trip label
- `state_counts` — neutral / drowsy / distracted frame counts per session
- `alert_events` — alert type, level (1/2/3), timestamp
- `system_logs` — INFO / SUCCESS / WARNING log entries per session
- `alertness_snapshots` — 5-second alertness readings per session
- `video_clips` — saved alert clip paths, alert types, duration

---

## 🚀 Getting Started

### Prerequisites
- Flutter SDK 3.16+
- Android Studio / VS Code
- Android device or emulator (API 26+, Android 8.0 Oreo minimum)
- **JDK 21** 

### Installation

```bash
git clone https://github.com/your-username/DriverMonitoringSystem.git
cd DriverMonitoringSystem/drivermonitorngsystem

flutter pub get

# Debug
flutter run

# Release APK
flutter build apk --release
```

### Model & Asset Setup

Place the following under `assets/`:

```
assets/
├── models/
│   └── dms_hybridnet_v3_float32.tflite
├── norm_params.json
├── L1_L2_sound.mp3
├── L3_critical_alert.wav
├── car.png
├── text_logo.png
└── bantay_drive_logo.png
```

Verify `pubspec.yaml` declares all of these under `flutter: assets:`.

### Android Gradle Setup

**`android/app/build.gradle.kts`** — Java 21 target:
```kotlin
compileOptions {
    isCoreLibraryDesugaringEnabled = true
    sourceCompatibility = JavaVersion.VERSION_21
    targetCompatibility = JavaVersion.VERSION_21
}
kotlinOptions { jvmTarget = "21" }
```
```kotlin
dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("androidx.concurrent:concurrent-futures:1.2.0")
    implementation("androidx.concurrent:concurrent-futures-ktx:1.2.0")
    implementation("androidx.multidex:multidex:2.0.1")
}
```

**`android/gradle/wrapper/gradle-wrapper.properties`:**
```properties
distributionUrl=https\://services.gradle.org/distributions/gradle-8.13-all.zip
```

**`android/app/build.gradle.kts`** — suppress `.tflite` compression:
```kotlin
aaptOptions {
    noCompress += listOf("tflite")
}
```

Release builds use ProGuard minification + resource shrinking by default.

---

## 📦 Key Dependencies

| Package | Purpose |
|---------|---------|
| `flutter_riverpod` | State management |
| `sqflite` | Local SQLite database |
| `camera` | Camera feed + image stream |
| `tflite_flutter` | On-device TFLite inference |
| `google_mlkit_face_detection` | Face detection for head-pose |
| `flutter_foreground_task` | Foreground service + persistent notification |
| `fl_chart` | Line + bar charts |
| `audioplayers` | Alert sounds |
| `volume_controller` | System volume control |
| `video_player` | Session video playback |
| `sensors_plus` | Accelerometer (phone tilt) |
| `shared_preferences` | Settings persistence |
| `permission_handler` | Runtime permissions |
| `device_info_plus` | Brand-specific UI scaling |
| `package_info_plus` | App version display |
| `path_provider` | App documents directory |
| `url_launcher` | Authors' GitHub links |

---

## 🎓 Thesis Context

**DMS-HybridNet** combines:
- **EfficientNet-B0** — spatial feature extraction (224×224)
- **Eye MicroCNN** — periocular feature extraction (32×64)
- **MobileNetV3-Small** — upper body/posture features (112×112)
- **BiLSTM** — bidirectional temporal sequence modeling (20-frame window)
- **Multi-Head Self-Attention** — occlusion-tolerant frame weighting
- **Geometric feature fusion** — EAR, MAR, PERCLOS, Head Pose (PnP)

**Training datasets:** MRL Eye, YawDD, UTA-RLDD, State Farm Distracted Driver, AUC Distracted Driver v2

---

## 👥 Authors

| Name | Role |
|------|------|
| Pia Katleya V. Macalanda | Machine Learning Engineer, Dataset Preparation, UI/UX Design, Researcher |
| Juliana R. Mancera | Mobile App Developer, Model Integration, Testing & Deployment, Researcher |

**Institution:** New Era University, College of Informatics and Computing Studies  
**Program:** Bachelor of Science in Computer Science  
**Year:** 2026

---

## 📄 License

Developed as an undergraduate thesis. Intended for academic and non-commercial research purposes only.
