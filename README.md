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

This app is the mobile implementation component of the thesis:
> *"DMS-HybridNet: A Hybrid CNN-BiLSTM-Attention Architecture for Real-Time Driver Monitoring Under Low-Light and Occlusion Conditions via Mobile-Based Computer Vision"*

---

## ✨ Features

### 📷 Real-Time Monitoring
- Front-facing camera live feed with on-device AI inference
- **3-level escalating alert system:**
  - **Level 1** — Slide-in audio banner (auto-dismisses)
  - **Level 2** — Stronger persistent banner with audio
  - **Level 3** — Full-screen blocking alarm overlay with looping audio, requires manual dismissal
- User-configurable alert sensitivity:

| Sensitivity | L1 Threshold | L2 Threshold | L3 Threshold |
|-------------|-------------|-------------|-------------|
| Low         | 5 frames    | 10 frames   | 15 frames   |
| Medium      | 3 frames    | 6 frames    | 9 frames    |
| High        | 2 frames    | 4 frames    | 6 frames    |

- **Picture-in-Picture (PiP) mode** — monitoring continues in a floating window when the user navigates away or presses home
- Foreground service with persistent notification showing live driver state + Stop button
- Clear Glasses toggle for periocular occlusion adjustment
- Auto-start recording on app launch option

### 🤖 AI Inference Engine (DMS-HybridNet)
- On-device TFLite inference — no internet or server required
- Currently outputs **3 main states** (Neutral, Drowsy, Distracted)
- Subclass modal UI prepared for **11-class model** (commented, ready to activate):

| Index | Subclass | Main State |
|-------|----------|------------|
| 0 | safe_driving | NEUTRAL |
| 1 | yawning | DROWSY |
| 2 | fatigue_head_droop | DROWSY |
| 3 | texting | DISTRACTED |
| 4 | phone_call | DISTRACTED |
| 5 | adjusting_radio | DISTRACTED |
| 6 | drinking | DISTRACTED |
| 7 | reaching_behind | DISTRACTED |
| 8 | hair_makeup | DISTRACTED |
| 9 | talking_passenger | DISTRACTED |
| 10 | eyes_closed_perclos | DROWSY |

- Background isolate preprocessing via `compute()` — UI thread never blocks
- YUV420 → RGB → 224×224 resize → Float32 normalization
- Gamma correction (γ = 0.3) via precomputed LUT
- Frame-skip gate: every 6th frame ≈ 5 FPS + 100ms time gate
- NNAPI (NPU/DSP) → CPU fallback initialization

### 📊 Dashboard
- Circular Safety Score (0–100), color-coded green / amber / red
- Four stat cards: Total Drive Time, Alerts (last 24h), Safety Streak, Avg Alertness
- Horizontally scrollable Safety Score History line chart (last 30 days)
- Auto-refreshes every 30 seconds + reactive to live session changes

### 📈 Analytics
- Time filter: 7 Days / 30 Days / All Time
- Summary cards: Total Sessions, Total Alerts, Drowsiness Events, Distraction Events
- Drowsiness vs Distraction daily line chart (expandable, horizontally scrollable)
- Hourly Alert Distribution bar chart (all 24 hours, expandable)

### 📋 History
- Chronological session list grouped by date (Today / Yesterday / date)
- Search by date, month name, day, time, or keyword `safe`
- Filter chips: All / This Week / This Month / With Alerts / Safe Drives
- Session detail bottom sheet: state breakdown bar, alert events (L1/L2/L3), system log

### ⚙️ Settings
- Alert volume slider (synchronized with system volume)
- Alert sensitivity control (Low / Medium / High)
- Auto-start recording toggle
- Session data retention (7 Days / 30 Days / Forever) — enforced immediately on change
- Clear all history with confirmation dialog
- About section with authors and GitHub profile links

### 🗄️ Local Database (SQLite — 5 tables, schema v2)
- `sessions` — drive sessions with timestamps, safety score, and optional trip label
- `state_counts` — neutral / drowsy / distracted frame counts per session
- `alert_events` — alert type (DROWSY / DISTRACTED), level (1/2/3), and timestamp
- `system_logs` — INFO / SUCCESS / WARNING log entries per session
- `alertness_snapshots` — 5-second alertness readings per session (for history chart)

---

## 🏗️ Architecture

```
lib/
├── core/
│   ├── database/
│   │   ├── database_helper.dart       # SQLite — 5 tables, schema v2, migrations
│   │   └── db_change_notifier.dart    # Riverpod reactive DB change counter
│   ├── inference/
│   │   ├── tflite_service.dart        # Model loading, inference, 3-class mapping
│   │   └── frame_preprocessor.dart   # YUV→RGB, gamma LUT, resize, normalize
│   ├── preference/
│   │   └── preference_helper.dart    # SharedPreferences wrapper
│   └── services/
│       └── notifications.dart        # Foreground service + notification management
├── screens/
│   ├── dashboard_screen.dart         # Safety score ring + stat cards + chart
│   ├── monitor_screen.dart           # Camera + inference + 3-level alert system + PiP
│   ├── analytics_screen.dart         # Trend charts + summary cards
│   ├── history_screen.dart           # Session list + search + filter + detail sheet
│   ├── settings_screen.dart          # App settings + retention enforcement
│   ├── onboarding_screen.dart        # First-launch walkthrough
│   └── splash_screen.dart            # Animated splash screen
├── utils/
│   └── responsive.dart              # Breakpoints + layout helpers
└── main.dart                         # App shell + IndexedStack + landscape sidebar
```

---

## 📱 Navigation

- **Portrait** — Persistent bottom navigation bar with animated sliding cyan pill indicator
- **Landscape** — Hamburger (☰) button opens a collapsible push sidebar
  - Sidebar slides in via animated push layout (preserves screen space for Monitor)
  - Close with the ✕ button or navigate away

---

## 🚀 Getting Started

### Prerequisites
- Flutter SDK 3.16+
- Android Studio / VS Code
- Android device or emulator (API 26+, Android 8.0 Oreo minimum)
- JDK 17 (required — JDK 24 causes CameraX build errors)

### Installation

```bash
# Clone the repository
git clone https://github.com/your-username/DriverMonitoringSystem.git
cd DriverMonitoringSystem/drivermonitorngsystem

# Install dependencies
flutter pub get

# Run the app (debug mode)
flutter run

# Build release APK
flutter build apk --release
```

### Model Setup
Place the trained TFLite model in:
```
assets/dms_hybridnet.tflite
```

Ensure `pubspec.yaml` includes:
```yaml
assets:
  - assets/dms_hybridnet.tflite
  - assets/L1_L2_sound.mp3
  - assets/L3_critical_alert.wav
  - assets/car.png
  - assets/text_logo.png
  - assets/bantay_drive_logo.png
```

### Android Gradle Setup
`android/app/build.gradle.kts` must use Java 17 and include the concurrent-futures dependency:
```kotlin
compileOptions {
    isCoreLibraryDesugaringEnabled = true
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}
kotlinOptions { jvmTarget = "17" }
```
```kotlin
dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("androidx.concurrent:concurrent-futures:1.2.0")
    implementation("androidx.concurrent:concurrent-futures-ktx:1.2.0")
}
```

`android/gradle/wrapper/gradle-wrapper.properties`:
```properties
distributionUrl=https\://services.gradle.org/distributions/gradle-8.13-all.zip
```

---

## 📦 Key Dependencies

| Package | Purpose |
|---------|---------|
| `flutter_riverpod` | State management (providers, StateProvider) |
| `sqflite` | Local SQLite database |
| `camera` | Camera feed + image stream |
| `tflite_flutter` | On-device TFLite inference |
| `flutter_foreground_task` | Foreground service + persistent notification |
| `fl_chart` | Line + bar charts |
| `audioplayers` | Alert sounds (L1/L2/L3) |
| `volume_controller` | System volume control |
| `shared_preferences` | Settings persistence |
| `permission_handler` | Runtime permissions |
| `device_info_plus` | Device name display in app bar |
| `url_launcher` | Authors' GitHub links in About section |
| `path_provider` | App documents directory |

---

## 🎓 Thesis Context

This app implements the mobile inference pipeline for **DMS-HybridNet**, a hybrid deep learning architecture combining:
- **EfficientNet-B0** — spatial feature extraction (full face, 224×224)
- **Eye MicroCNN** — periocular feature extraction (eye patch, 32×64)
- **MobileNetV3-Small** — upper body / posture feature extraction (112×112)
- **BiLSTM** — bidirectional temporal sequence modeling (20-frame window)
- **Multi-Head Self-Attention** — occlusion-tolerant frame weighting
- **Geometric feature fusion** — EAR, MAR, PERCLOS, Head Pose (PnP)

**Datasets used for training:**
- MRL Eye Dataset (drowsiness — eye region images, IR + RGB)
- YawDD — Yawning Detection Dataset (temporal, dashboard + mirror cameras)
- UTA-RLDD — Real-Life Drowsiness Dataset (Fold 5 held out as novelty test)
- State Farm Distracted Driver Detection (distraction — 10 classes)
- AUC Distracted Driver Dataset v2 (distraction — dual camera)

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

This project is developed as an undergraduate thesis and is intended for academic and non-commercial research purposes only.

---

<p align="center">Made with ❤️ for safer driving in the Philippines 🇵🇭</p>
