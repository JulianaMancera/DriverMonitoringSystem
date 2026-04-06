<div align="center">
<h1> 🚗 Bantay Drive — Real-Time Driver Monitoring System </h1>
</div>
<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.16+-02569B?style=for-the-badge&logo=flutter&logoColor=white"/>
  <img src="https://img.shields.io/badge/Dart-3.x-0175C2?style=for-the-badge&logo=dart&logoColor=white"/>
  <img src="https://img.shields.io/badge/TFLite-DMS--HybridNet-FF6F00?style=for-the-badge&logo=tensorflow&logoColor=white"/>
  <img src="https://img.shields.io/badge/Platform-Android-3DDC84?style=for-the-badge&logo=android&logoColor=white"/>
  <img src="https://img.shields.io/badge/Status-In%20Development-yellow?style=for-the-badge"/>
</p>

<div align="center">
 <h2>Undergraduate Thesis Project — New Era University, 2026 <br> </h2>
 <h4>Authors: Macalanda, Pia Katleya V. & Mancera, Juliana R. </h4>
</div>

---

## 📖 About

**Bantay Drive** is a mobile-based real-time driver monitoring system powered by an on-device deep learning model. It uses the front-facing camera to detect drowsiness and distraction states in real time, escalating alerts before dangerous situations occur — all without any internet connection.

The app is the mobile implementation component of the thesis:
> *"DMS-HybridNet: A Hybrid CNN-BiLSTM-Attention Architecture for Real-Time Driver Monitoring Under Low-Light and Occlusion Conditions via Mobile-Based Computer Vision"*

---

## ✨ Features

### 📷 Real-Time Monitoring
- Front-facing camera live feed with AI inference
- **3-level escalating alert system:**
  - Level 1 — Notification banner (auto-dismisses after 4s)
  - Level 2 — Stronger pulse banner
  - Level 3 — Fullscreen alarm overlay with looping audio
- Configurable alert sensitivity (Low / Medium / High)
- Clear Glasses mode for EAR threshold adjustment
- Auto-start recording on app launch option

### 🤖 AI Inference Engine (DMS-HybridNet)
- On-device TFLite inference — no internet required
- **10-class V2 taxonomy** mapped to 3 main states:

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
| 9 | eyes_closed_perclos | DROWSY |

- Background isolate preprocessing (YUV420 → RGB → 224×224 → Float32)
- Gamma correction (γ = 0.3) via precomputed LUT
- Frame-skip gate (every 4th frame ≈ 7.5 FPS) + 100ms time gate
- NNAPI → CPU → default 3-attempt fallback initialization

### 📊 Analytics
- Session trends (7 Days / 30 Days / All Time)
- Drowsiness vs Distraction line chart (expandable, horizontally scrollable)
- Hourly Alert Distribution bar chart (expandable, all 24 hours)
- Summary cards with green/yellow status indicators

### 📋 History
- Chronological session list grouped by date
- Search by date, month, time, or "safe"/"alert"
- Filter chips: All / This Week / This Month / With Alerts / Safe Drives
- Session detail bottom sheet with state breakdown, alert events, and system log

### ⚙️ Settings
- Alert volume slider (controls system volume)
- Alert sensitivity control
- Auto-start recording toggle
- Session data retention policy
- CSV export via native share sheet (works on Android 8–15+)
- Clear all history

### 🗄️ Local Database (SQLite — 5 tables)
- `sessions` — drive sessions with timestamps and scores
- `state_counts` — neutral/drowsy/distracted frame counts
- `alert_events` — alert type, level, and timestamp per session
- `system_logs` — timestamped log entries per session
- `alertness_snapshots` — 5-second alertness readings per session

---

## 🏗️ Architecture

```
lib/
├── core/
│   ├── database/
│   │   ├── database_helper.dart       # SQLite (5 tables)
│   │   └── db_change_notifier.dart    # Riverpod reactive DB counter
│   ├── inference/
│   │   ├── tflite_service.dart        # Model loading + inference + V2 mapping
│   │   └── frame_preprocessor.dart   # YUV→RGB, gamma, resize, normalize
│   └── preference/
│       └── preference_helper.dart    # SharedPreferences wrapper
├── screens/
│   ├── dashboard_screen.dart         # Safety score + metrics + alertness chart
│   ├── monitor_screen.dart           # Camera + AI inference + alert system
│   ├── analytics_screen.dart         # Charts + summary cards
│   ├── history_screen.dart           # Session list + detail sheet
│   └── settings_screen.dart         # App settings + CSV export
├── utils/
│   └── responsive.dart              # Breakpoints + responsive helpers
└── main.dart                         # App shell + navigation + landscape sidebar
```

---

## 📱 Navigation

- **Portrait** — Bottom navigation bar with sliding cyan pill indicator
- **Landscape** — Hamburger (☰) button opens a push sidebar (Claude-style)
  - Sidebar stays open when navigating between screens
  - Close with the ✕ button only

---

## 🚀 Getting Started

### Prerequisites
- Flutter SDK 3.16+
- Android Studio / VS Code
- Android device (API 24+ recommended)

### Installation

```bash
# Clone the repository
git clone https://github.com/your-username/DriverMonitoringSystem.git
cd DriverMonitoringSystem/drivermonitorngsystem

# Install dependencies
flutter pub get

# Run the app
flutter run
```

### Model Setup
Place the trained TFLite model in:
```
assets/dms_hybridnet.tflite
```

Make sure `pubspec.yaml` includes:
```yaml
assets:
  - assets/dms_hybridnet.tflite
  - assets/L1_L2_sound.mp3
  - assets/L3_critical_alert.wav
```

And `android/app/build.gradle` has:
```groovy
android {
    aaptOptions {
        noCompress "tflite"
    }
}
```

---

## 📦 Key Dependencies

| Package | Purpose |
|---------|---------|
| `flutter_riverpod` | State management |
| `sqflite` | Local SQLite database |
| `camera` | Camera feed + image stream |
| `tflite_flutter` | On-device TFLite inference |
| `fl_chart` | Line + bar charts |
| `share_plus` | CSV file export |
| `audioplayers` | Alert sounds |
| `volume_controller` | System volume control |
| `path_provider` | App documents directory |
| `shared_preferences` | Settings persistence |
| `permission_handler` | Runtime permissions |

---

## 🔧 Android Permissions

```xml
<uses-permission android:name="android.permission.CAMERA"/>
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"
    android:maxSdkVersion="29"
    tools:replace="android:maxSdkVersion"/>
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"
    android:maxSdkVersion="32"/>
```

---

## 🎓 Thesis Context

This app implements the inference pipeline for **DMS-HybridNet**, a hybrid deep learning architecture combining:
- **CNN** — spatial feature extraction from face/body crops
- **BiLSTM** — temporal sequence modeling (bidirectional)
- **Attention mechanism** — focus on salient temporal features

**Datasets used for training:**
- StateFarm Distracted Driver Detection
- AUC Distracted Driver Dataset
- YawDD (Yawning Detection Dataset)
- NTHU Drowsy Driver Detection
- UTA-RLDD (Real-Life Drowsiness Dataset)

**V2 Taxonomy:** 10 subclasses across 3 main states (Neutral, Drowsy, Distracted) with PERCLOS-based sub12 split via H04 threshold pass.

---

## 👥 Authors

| Name | Role |
|------|------|
| Pia Katleya V. Macalanda | Model Training, Dataset Preparation, UI/UX, Researcher |
| Juliana R. Mancera | System Developer, Model Implementation, Testing & Deployment, Researcher |

**Institution:** New Era University, College of Informatics and Computing Studies
**Year:** 2026

---

## 📄 License

This project is developed as an undergraduate thesis and is intended for academic purposes.

---

<p align="center">Made with ❤️ for safer driving in the Philippines 🇵🇭</p>
