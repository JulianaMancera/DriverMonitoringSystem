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

## About

**Bantay Drive** is a mobile-based real-time driver monitoring system powered by an on-device deep learning model. It uses the front-facing camera to classify driver behavior into 13 sub-classes across three parent states (NATURAL, DISTRACTED, DROWSY), escalating tiered alerts before dangerous situations occur — entirely offline, 14.12 MB, no cloud dependency.

> *"DMS-HybridNet: A Dual-Stream Architecture Combining MobileNetV3 and Residual 1D-CNN for Real-Time Multi-Class Driver Behavior Monitoring on Mobile Edge Devices"*

---

## Features

### Real-Time Monitoring
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
- **Video clip capture** — automatically records and saves clips (up to 10 s) when alerts trigger
- **Picture-in-Picture (PiP)** — monitoring continues in a floating window when app is backgrounded
- Foreground service with persistent notification showing live driver state + Stop button
- Clear Glasses toggle, Auto-start recording option

### Dashboard
- Circular Safety Score (0–100), color-coded green / amber / red
- Stat cards: Total Drive Time, Alerts (last 24 h), Safety Streak, Avg Alertness
- Safety Score History line chart (last 30 days, horizontally scrollable)
- **Shimmer skeleton loading** while data is being fetched

### Analytics
- Time filter: 7 Days / 30 Days / All Time
- Drowsiness vs. Distraction daily line chart + Hourly Alert Distribution bar chart
- **Shimmer skeleton loading** while analytics data is being fetched

### History
- Chronological session list grouped by date with search and filter chips
- **Advanced filtering** for both session logs and video logs
- Session detail: state breakdown, alert events (L1/L2/L3), system log
- **In-app session video playback** (non-mirrored)

### Settings
- Alert volume, sensitivity, auto-start recording, data retention (7 Days / 30 Days / Forever)
- Clear all history with confirmation

---

## Architecture

```
lib/
├── core/
│   ├── database/
│   │   ├── database_helper.dart       # SQLite — 6 tables, schema v4, migrations
│   │   └── db_change_notifier.dart    # Riverpod reactive DB counter
│   ├── inference/
│   │   └── tflite_service.dart        # Model loading, inference, 13-class mapping
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
│   ├── dashboard_screen.dart         # Safety score + charts + skeleton loading
│   ├── analytics_screen.dart         # Trend charts + skeleton loading
│   ├── history_screen.dart           # Session list + video playback + filters
│   ├── settings_screen.dart          # App settings
│   ├── onboarding_screen.dart        # First-launch walkthrough
│   └── splash_screen.dart
├── widgets/
│   ├── exit.dart                     # Exit confirmation dialog
│   └── head_pose_indicator.dart      # Camera alignment visual overlay
├── utils/
│   └── responsive.dart              # Breakpoints + brand-specific scaling
└── main.dart                         # App shell + IndexedStack + landscape sidebar
```

### Local Database (SQLite — 6 tables, schema v4)
- `sessions` — drive sessions with timestamps, safety score, trip label
- `state_counts` — neutral / drowsy / distracted frame counts per session
- `alert_events` — alert type, level (1/2/3), timestamp
- `system_logs` — INFO / SUCCESS / WARNING log entries per session
- `alertness_snapshots` — 5-second alertness readings per session
- `video_clips` — saved alert clip paths, alert types, duration

---

## Getting Started

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

New to Flutter? The [official Flutter documentation](https://docs.flutter.dev/) offers tutorials, samples, and a full API reference. A guided first-app walkthrough is available at [docs.flutter.dev/get-started/codelab](https://docs.flutter.dev/get-started/codelab).

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

## Key Dependencies

| Package | Purpose |
|---------|---------|
| `flutter_riverpod` | State management |
| `sqflite` | Local SQLite database |
| `camera` | Camera feed + image stream |
| `tflite_flutter` | On-device TFLite inference |
| `google_mlkit_face_detection` | Face detection for head-pose |
| `flutter_foreground_task` | Foreground service + persistent notification |
| `fl_chart` | Line + bar charts |
| `shimmer` | Skeleton loading animations |
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

## Thesis Context

### DMS-HybridNet V3.1 Architecture

A dual-stream model designed for real-time inference on mid-range Android hardware. Two streams; zero cloud dependency.

#### Spatial Stream

- Input: single 224×224 RGB frame
- Backbone: MobileNetV3Large (3.2M params, ImageNet pretrained)
- Output: 256-dim spatial embedding

#### Temporal Stream

- Input: 30-frame rolling window × 25 geometric features
- Three Residual 1D-CNN blocks: 64 → 128 → 256 filters
- Output: 128-dim temporal embedding
- Why Residual 1D-CNN instead of LSTM: LSTM requires `SELECT_TF_OPS` in TFLite, blocking INT8 quantization. 1D-CNN is parallelizable, quantization-compatible, and ~1/5 the parameter count (~500K vs ~2.5M BiLSTM equivalent).

#### Asymmetric Gated Fusion

- Gate driven exclusively by the temporal stream: `gate = σ(Dense(t))`
- Prevents MobileNetV3 from suppressing drowsiness signals during ambiguous frames
- Gate layer adds only 258 parameters

#### Output Heads (3 parallel)

- Behavior: 13-class (primary, loss weight 1.0)
- Parent state: 3-class NATURAL / DISTRACTED / DROWSY (loss weight 0.3)
- Gaze zone: 8-class (loss weight 0.2)

---

### The 25-Feature Vector

| Group | Indices | Features |
|-------|---------|----------|
| Eye signals | 0–3 | EAR_L, EAR_R, EAR_avg, EAR_min |
| Mouth | 4 | MAR (yawn vs. talking disambiguation) |
| Head pose | 5–7 | Pitch, Yaw, Roll via PnP solver |
| Gaze | 8–11 | Iris tracking — gaze_L/R × gaze_L/R y |
| Body geometry | 12–17 | Wrist + shoulder positions, normalized by shoulder span |
| Occlusion flags | 18–19 | Hand-near-face, mouth-occluded binaries |
| Temporal statistics | 20–24 | ear_avg_mean, ear_avg_min, mar_max, mar_above_thresh, ear_trend (OLS slope) |

`ear_trend` (OLS slope) is the key drowsiness onset detector — a progressively negative slope means eyes are slowly closing, not blinking.

> **Known gap:** Body geometry features (indices 12–17) currently default to 0.0 in live inference — full body pose integration is the top engineering priority for V4.

---

### Training Datasets

| Dataset | Subjects | Frames | Notes |
|---------|----------|--------|-------|
| NTHU-DDD | 36+ | 18,000 | Near-IR, multiple capture modes |
| YawDD | 107 | 222,954 | Mirror-flipped (LHD correction applied) |
| SAM-DD | ~30 | 10,991 | RHD → coordinate-flipped to LHD |
| 3MDAD | 50 | 101,405 | 16 classes → mapped to 13 unified |
| **Total** | — | **353,350** | **13 unified classes** |

Subject-exclusive splits — no subject appears in more than one partition, eliminating the #1 source of inflated accuracy in prior work.

**Class imbalance:** 72× ratio between largest and smallest class. Fixed with Weighted Focal Loss (γ=2.0, weights capped at 15.0), giving rare classes up to 55× more gradient emphasis.

---

### Model Performance

| Metric | Value | Context |
|--------|-------|---------|
| 13-Class Overall Accuracy | 51.51% | 6.7× above 7.7% random baseline |
| Parent-Class Accuracy | 73.18% | 2.2× above 33% chance |
| DISTRACTED Recall | 98.5% | Near-ceiling |
| DISTRACTED F1 | 0.901 | Strongest performing group |
| DROWSY Recall | 30.4% | Primary limitation (data poverty, not architecture) |
| DROWSY F1 | 0.370 | |
| NATURAL Recall | 73.8% | Practical safe-state detection |
| talking_passenger F1 | 0.671 | 4.3× improvement over face-only V1 (0.156) |
| Top-3 Accuracy | ~93.0% | Correct class in top 3 for 93/100 sequences |
| Macro F1 | 0.4125 | |
| Weighted F1 | 0.4958 | |

**DROWSY recall root causes:** Only 2,025 DROWSY training sequences from 4 NTHU subjects; MAR features alias between yawning and animated talking; partial modality collapse in ambiguous frames. Fix for V4: UTA-RLDD integration (60 subjects, 477K frames) projected to deliver 2.4× subject count increase in DROWSY training data.

---

### On-Device Performance

- TFLite float32, 14.12 MB
- 5–15 ms per forward pass on mid-range Snapdragon
- Effective prediction rate: 6–7 FPS (every 5th camera frame)
- Privacy by design: no video transmitted, no cloud sync — compliant with the Philippine Data Privacy Act of 2012 (RA 10173)

---

## Authors

| Name | Role |
|------|------|
| Pia Katleya V. Macalanda | Machine Learning Engineer, Dataset Preparation, UI/UX Design, Researcher |
| Juliana R. Mancera | Mobile App Developer, Model Integration, Testing & Deployment, Researcher |

**Institution:** New Era University, College of Informatics and Computing Studies  
**Program:** Bachelor of Science in Computer Science  
**Year:** 2026

---

## License

This project was developed as an undergraduate thesis at New Era University. It is intended for academic and non-commercial research purposes only. Unauthorized reproduction, distribution, or commercial use of any part of this project — including the model architecture, source code, and documentation — is not permitted without prior written consent from the authors.
