# Bantay Drive — App Code Description

**App name:** Bantay Drive  
**Package:** `com.example.smartalertdrive`  
**Version:** 1.0.0+1  
**Framework:** Flutter (Dart SDK ≥3.3.0)  
**Platform:** Android  

---

## Table of Contents

1. [Overview](#1-overview)
2. [Architecture](#2-architecture)
3. [Entry Point — `main.dart`](#3-entry-point--maindart)
4. [Screens](#4-screens)
   - [Splash Screen](#41-splash-screen)
   - [Onboarding Screen](#42-onboarding-screen)
   - [Dashboard Screen](#43-dashboard-screen)
   - [Monitor Screen](#44-monitor-screen)
   - [Analytics Screen](#45-analytics-screen)
   - [History Screen](#46-history-screen)
   - [Settings Screen](#47-settings-screen)
5. [Core — Inference](#5-core--inference)
   - [TFLite Service](#51-tflite-service)
   - [Head Pose Service](#52-head-pose-service)
6. [Core — Services](#6-core--services)
   - [Foreground Notification Service](#61-foreground-notification-service)
   - [PiP Service](#62-pip-service)
   - [Video Clip Service](#63-video-clip-service)
7. [Core — Data](#7-core--data)
   - [Database Helper](#71-database-helper)
   - [Session State](#72-session-state)
   - [Preferences Helper](#73-preferences-helper)
8. [Core — Providers](#8-core--providers)
9. [Widgets](#9-widgets)
   - [Head Pose Indicator](#91-head-pose-indicator)
   - [Exit Dialog](#92-exit-dialog)
10. [Utilities — Responsive Layout](#10-utilities--responsive-layout)
11. [Assets & Model](#11-assets--model)
12. [Key Dependencies](#12-key-dependencies)

---

## 1. Overview

Bantay Drive is a real-time driver monitoring system (DMS) that uses the smartphone's front camera to detect drowsiness and distraction while driving. It runs an on-device AI model to classify the driver's behavior every 150 ms, triggers audio alerts when unsafe behavior is detected, records the session data locally, and provides analytics and history views after each drive.

**Core features:**
- Live AI inference classifying 13 driver behavior classes (safe, drowsy subtypes, distracted subtypes)
- Three-stage alert system with Level 1 and Level 2 escalating alerts
- Foreground service that keeps monitoring active when the app is backgrounded
- Picture-in-Picture (PiP) mode for using the phone while monitoring continues
- Session recording with safety score calculation
- Video clip capture on alert events
- SQLite-backed analytics (daily trends, hourly distribution, safety score history)
- Responsive layout scaling for all Android phone sizes and OEM brands

---

## 2. Architecture

```
lib/
├── main.dart                          ← App entry, root navigation shell
├── core/
│   ├── providers.dart                 ← Global Riverpod state providers
│   ├── session_state.dart             ← Persistent active-session identity
│   ├── preference/
│   │   └── preference_helper.dart     ← User settings (SharedPreferences)
│   ├── database/
│   │   ├── database_helper.dart       ← SQLite CRUD for all app data
│   │   └── db_change_notifier.dart    ← Notifier to refresh UI on DB writes
│   ├── inference/
│   │   └── tflite_service.dart        ← AI model runner (DMS-HybridNet V3)
│   └── services/
│       ├── head_pose_service.dart     ← ML Kit face/pose extraction
│       ├── notifications.dart         ← Android foreground service
│       ├── pip_service.dart           ← Picture-in-Picture bridge
│       └── video_clip_service.dart    ← Alert video file management
├── screens/
│   ├── splash_screen.dart
│   ├── onboarding_screen.dart
│   ├── dashboard_screen.dart
│   ├── monitor_screen.dart
│   ├── analytics_screen.dart
│   ├── history_screen.dart
│   └── settings_screen.dart
├── widgets/
│   ├── head_pose_indicator.dart
│   └── exit.dart
└── utils/
    └── responsive.dart
```

**State management:** Riverpod (flutter_riverpod ^3.3.1)  
**Persistence:** SQLite via sqflite, user preferences via shared_preferences  
**Navigation:** Bottom navigation bar with 5 tabs inside a persistent `MainShell` widget

---

## 3. Entry Point — `main.dart`

**File:** `lib/main.dart`

### What it does
Bootstraps the entire application. Runs device detection, initializes the database and foreground service port, resolves first-launch logic (onboarding), and renders the root navigation shell.

### Key components

| Component | Type | Description |
|---|---|---|
| `main()` | async function | Binds Flutter, reads device info, sets responsive brand factor, initializes DB and notifications, registers isolate receive port for background-to-foreground communication, then calls `runApp()` |
| `BantayDriveApp` | StatelessWidget | Wraps the app in `ProviderScope` and configures `MaterialApp` with the dark theme (primary `#00D4FF`, background `#080E1A`) |
| `EntryPoint` | StatefulWidget | Decides whether to show splash → onboarding → main shell based on `PreferencesHelper.getOnboardingSeen()`. Manages fade transitions between these states |
| `MainShell` | ConsumerWidget | Hosts the `IndexedStack` of all 5 tabs, the app bar (with live recording dot), the bottom nav bar, and the PiP-aware monitor screen persistence |
| `_BottomNav` | StatelessWidget | Animated bottom navigation with a pill highlight that slides behind the active icon |
| `_ExitWrapper` | ConsumerWidget | Wraps the shell with `PopScope` so the back button shows the exit confirmation dialog |
| `navIndexProvider` | NotifierProvider | Tracks which of the 5 tabs is active |
| `deviceNameProvider` | FutureProvider | Reads the device model name from `DeviceInfoPlugin` for display in the Monitor screen app bar |

### Theme
- Background: `#080E1A` (deep navy)
- Primary accent: `#00D4FF` (cyan)
- Card color: `#0D1B2A`
- Font: System default with responsive scaling

---

## 4. Screens

### 4.1 Splash Screen

**File:** `lib/screens/splash_screen.dart`

Animated brand screen shown at startup while the app loads the AI model, initializes the database, and resolves app configuration.

**Behavior:**
- Plays a sequenced animation: background grid → logo scale-in → wordmark fade → tagline slide → loading bar fill
- Reads the app version from `package_info_plus` and displays it at the bottom
- Calls `onComplete` callback once the animation and loading delay finish, transitioning to onboarding or main shell

**Visual elements:**
- `_GridPainter`: CustomPainter drawing a subtle dot-grid background pattern
- Animated logo with scale + opacity
- "BANTAY DRIVE" wordmark with letter-spacing animation
- "Your AI-Powered Co-Driver" tagline
- Linear loading progress bar

---

### 4.2 Onboarding Screen

**File:** `lib/screens/onboarding_screen.dart`

A 4-page introductory walkthrough shown once on first launch. Each page explains a key feature of the app with an icon, title, and description.

**Pages:**
1. **Live Monitoring** — Introduces the AI camera monitoring feature
2. **Smart Analytics** — Explains the trend and history charts
3. **Instant Alerts** — Describes the audio alert system
4. **Session History** — Shows how past drives and videos are stored

**Behavior:**
- `PageController` with swipe navigation and dot indicator
- Each page animates its icon and text with scale + fade
- "Get Started" button on the last page calls `PreferencesHelper.setOnboardingSeen(true)` and triggers `onComplete`
- `hasBeenSeen()` / `markSeen()` static helpers allow `EntryPoint` to skip onboarding on subsequent launches

---

### 4.3 Dashboard Screen

**File:** `lib/screens/dashboard_screen.dart`

The **Home tab** (tab index 0). Displays an at-a-glance summary of the driver's safety performance.

**Sections:**

| Section | Description |
|---|---|
| Safety Score ring | Large circular gauge showing the overall rolling safety score (0–100%) |
| Quick stats grid | Four stat cards: Total Drive Time, Total Alerts, Safety Streak (days), Average Alertness |
| 30-day safety chart | Line chart (fl_chart) of daily safety scores over the past 30 days with color zones (green/yellow/red) |
| Alertness sparkline | Small sparkline showing alertness trend for the most recent session |

**Data source:** `dashboardProvider` FutureProvider queries `DatabaseHelper.getDashboardSummary()` which aggregates all session data.

**Auto-refresh:** A `Timer.periodic` set to 30 seconds re-fires the provider so the dashboard updates while a session is in progress in the background.

**Loading state:** Uses `shimmer` skeleton cards while data is being fetched.

---

### 4.4 Monitor Screen

**File:** `lib/screens/monitor_screen.dart`

The **Monitor tab** (tab index 1). This is the primary functional screen — it handles the entire live monitoring loop.

#### Camera and Inference Loop

1. A `CameraController` is initialized targeting the front camera at 720p/30fps.
2. `HeadPoseService` runs Google ML Kit face detection on each frame to extract EAR (Eye Aspect Ratio), MAR (Mouth Aspect Ratio), pitch, yaw, and roll angles.
3. The extracted pose data is fed to `TfliteService.updateFaceData()`.
4. `TfliteService.runInference()` processes each frame through the DMS-HybridNet V3 model, producing an `InferenceResult` with state classification.
5. The result updates Riverpod providers (`driverStateProvider`, `alertnessPctProvider`, etc.) which the UI reads reactively.

#### Alert System

| Alert level | Trigger condition | Action |
|---|---|---|
| Level 1 | 5 consecutive distracted/drowsy frames | Short audio chime, banner notification |
| Level 2 | 10 consecutive distracted/drowsy frames | Louder looping alarm, persistent banner, video clip saved |

- Audio is played via `audioplayers` with volume controlled by `volume_controller`.
- Alert volume respects the user's setting from `PreferencesHelper`.
- Alert cooldown prevents alert spam — a minimum gap is enforced between consecutive alerts of the same type.

#### Session Lifecycle

- **Start:** Creates a new session record in SQLite (`DatabaseHelper.insertSession()`), initializes counters, starts the foreground service via `BantayDriveService.startService()`.
- **During:** State counts (neutral/drowsy/distracted frame counts) are periodically written to the DB. Alert events are inserted on each alert trigger. System log entries are saved.
- **Stop:** Ends the session in SQLite with duration and computed safety score. Shows the session summary modal bottom sheet. Stops the foreground service.

#### Safety Score Computation (`_computeSafetyScore`)

```
safetyScore = 100 − (totalPenalty / durationMin) × 10
```

- Level 1 alert penalty: 2 points
- Level 2 alert penalty: 5 points
- `durationMin` is floored at 2.0 minutes to prevent short test sessions from scoring 0%
- Result is clamped to [0, 100]

#### UI Layout (Portrait)

- **Top:** App bar with device name, recording indicator dot, PiP button
- **Camera area:** Live camera preview with overlaid `HeadPoseIndicator`, detection state badge, alert banner, and Stop/Start button
- **Metrics sidebar:** Three circular gauges for Alertness %, Drowsiness %, and Distraction %
- **System log:** Scrollable live log of inference results and alert events

#### PiP Mode

When the user taps the PiP button:
- `PipService.enterPip()` sends a method channel call to the native Android layer
- The Flutter app enters a small floating window
- The monitoring loop continues uninterrupted
- On PiP exit, the screen restores its full layout

#### Session Summary Modal

Shown after stopping a session. Displays:
- Session duration
- Safety score with color-coded rating label
- State breakdown (neutral / drowsy / distracted time)
- Alert count by level
- "View History" shortcut

---

### 4.5 Analytics Screen

**File:** `lib/screens/analytics_screen.dart`

The **Analytics tab** (tab index 2). Provides trend charts and breakdowns across multiple time ranges.

**Filter tabs:** 7 Days · 30 Days · All Time

**Charts included:**

| Chart | Description |
|---|---|
| Drowsy vs Distracted trend | Dual-line chart showing daily drowsy and distracted alert counts |
| Hourly alert distribution | Bar chart showing at which hour of the day alerts are most frequent |
| Safety score history | Line chart of daily safety scores with trend line |
| Alert type breakdown | Segmented view of alert types (phone, body, grooming, drowsy, etc.) |

**Data source:** `analyticsDataProvider` FutureProvider.family(filterPeriod) → `DatabaseHelper.getAnalyticsSummary()`.

**State:** `analyticsFilterProvider` NotifierProvider holds the selected time range and triggers data reload when changed.

---

### 4.6 History Screen

**File:** `lib/screens/history_screen.dart`

The **History tab** (tab index 3). Two sub-tabs: **Session Logs** and **Video Logs**.

#### Session Logs tab

- Lists all completed sessions in reverse chronological order
- Each entry shows: date/time, duration, safety score with color badge, alert counts
- **Filters:** Date range picker, detection type (drowsy/distracted), alert level (Level 1/Level 2), text search
- Tapping a session expands its detail view with per-category breakdown

#### Video Logs tab

- Lists all saved alert video clips
- Each entry shows: thumbnail, clip duration, alert type, timestamp
- Tapping a clip opens an in-app video player (`video_player`)
- Clips can be exported to the device Downloads folder via `VideoClipService.exportToDownloads()`
- Clips can be deleted individually

**Data sources:** `DatabaseHelper.getAllSessions()` and `DatabaseHelper.getAllVideoClips()`

---

### 4.7 Settings Screen

**File:** `lib/screens/settings_screen.dart`

The **Settings tab** (tab index 4). Allows the user to configure app behavior.

**Settings sections:**

| Setting | Type | Description |
|---|---|---|
| Alert Volume | Slider (0–100%) | Controls the audio alert volume; adjusts system media volume via `volume_controller` |
| Alert Sensitivity | Segmented (Low / Normal / High) | Adjusts frame-count thresholds for Level 1 and Level 2 alert triggers |
| Auto-Start Recording | Toggle | Automatically starts a session when the app is opened |
| Show Session Summary | Toggle | Controls whether the summary modal appears after stopping |
| Data Retention | Segmented (7d / 30d / 90d / Forever) | Sessions older than the chosen period are deleted on app launch |
| Clear Data | Destructive button | Wipes all sessions, alerts, logs, and video clips from the device |
| About section | Info | Shows app version, build number, and developer credits |

Settings are read/written via `PreferencesHelper` and persist across app restarts.

---

## 5. Core — Inference

### 5.1 TFLite Service

**File:** `lib/core/inference/tflite_service.dart`

Singleton that manages the TensorFlow Lite model lifecycle and runs inference on every camera frame.

#### Model

- **File:** `assets/model/dms_hybridnet_v3_float32.tflite`
- **Architecture:** DMS-HybridNet V3 — dual-input (spatial + temporal), three-output
- **Inputs:**
  - Spatial: 224×224 RGB normalized image ([-1, 1])
  - Temporal: 30-frame sequence of 25 features per frame (EAR, MAR, pitch, yaw, roll + window statistics)
- **Outputs:**
  - Behavior probabilities: 13 classes
  - Parent class: 3 classes (NATURAL, DISTRACTED, DROWSY)
  - Gaze zone: 8 zones (ROAD, LAP, LEFT, LEFT_MIRROR, RIGHT, RIGHT_MIRROR, STEERING, NOT_VALID)

#### 13 Behavior Classes

| Index | Class | Parent |
|---|---|---|
| 0 | safe_driving | NATURAL |
| 1 | talking_passenger | NATURAL |
| 2 | distracted_texting | DISTRACTED |
| 3 | distracted_phone | DISTRACTED |
| 4 | distracted_radio | DISTRACTED |
| 5 | distracted_drinking | DISTRACTED |
| 6 | distracted_body | DISTRACTED |
| 7 | distracted_grooming | DISTRACTED |
| 8 | distracted_smoking | DISTRACTED |
| 9 | drowsy_yawning | DROWSY |
| 10 | drowsy_yawning_occluded | DROWSY |
| 11 | drowsy_fatigue | DROWSY |
| 12 | drowsy_microsleep | DROWSY |

#### Camera Mount Geometry

The app is designed for a **right-side mount at 30–45°** (phone placed in a car holder to the right of the driver). A `kSideMountYawOffset = 35.0°` is subtracted from the raw yaw angle so the model receives ~0° when the driver looks straight ahead at the road.

#### Detection Logic

**Drowsy detection:**
- Gate: `drowsyPct ≥ 15%` AND best drowsy class meets its per-class minimum threshold
- Confirmation: 3 consecutive qualifying frames (~0.6 s)

**Distracted detection — Three-Stage:**

| Stage | distPct gate | bestClass gate | Frames required | Parent required |
|---|---|---|---|---|
| 1 — High | ≥ 40% | ≥ 25% | 6 (~1.2 s) | No |
| 2 — Mod | ≥ 22% | ≥ 12% | 12 (~2.4 s) | Yes |
| 3 — Low | ≥ 15% | ≥ 8% | 22 (~4.4 s) | Yes + off-road |

**Cross-class demotion:** If `distracted_body` (catch-all class 6) wins with < 72% confidence, the service checks if a more specific distracted class is close behind and promotes it.

**Grooming false-positive suppression:** If `distracted_grooming` wins with < 55% confidence and a competing class is within 20% of it, grooming is demoted to avoid false positives from the side-mount viewing angle.

**Subclass stability:** A rolling 3-frame score accumulator determines the dominant distracted subclass label, preventing rapid oscillation between classes.

**Stage persistence:** The service tracks `_peakDistStage` — the highest stage reached during the current distraction run — so that a single neutral frame doesn't reset the threshold gate to the slowest (22-frame) stage.

#### Inference Pipeline

1. Frame arrives as `CameraImage` (YUV420)
2. `compute()` isolate converts YUV → RGB, resizes to 224×224 via bilinear interpolation, normalizes to [-1, 1], and extracts pose features
3. Temporal buffer is updated (FIFO sliding window of 30 frames)
4. `IsolateInterpreter.runForMultipleInputs()` runs the model in a background isolate (does not block the UI thread)
5. Raw outputs are softmax-normalized if needed
6. `_buildResult()` applies all classification logic and returns an `InferenceResult`

Inference is rate-limited to a minimum gap of **150 ms** between calls.

---

### 5.2 Head Pose Service

**File:** `lib/core/services/head_pose_service.dart`

Singleton that extracts face landmarks and head pose from each camera frame using Google ML Kit Face Detection.

**Extracted values:**

| Value | Description | Range |
|---|---|---|
| EAR left/right | Eye Aspect Ratio — derived from ML Kit's open probability | 0.05 (closed) – 0.40 (wide open) |
| MAR | Mouth Aspect Ratio — vertical mouth opening / horizontal width | 0.0 (closed) – 1.2+ (wide yawn) |
| Pitch | Head tilt up/down (Euler X) | degrees |
| Yaw | Head turn left/right (Euler Y) | degrees |
| Roll | Head tilt sideways (Euler Z) | degrees |

**EAR mapping:** `prob × 0.35 + 0.05` — converts ML Kit's `leftEyeOpenProbability` (0–1) to a physiologically-plausible EAR range.

**Smoothing:**
- EAR: exponential moving average α=0.4 (~195 ms time constant) — slower to avoid transient flicker
- MAR: α=0.5 (~144 ms time constant) — slightly faster since yawn onset is important to catch early

The smoothed values are passed to `TfliteService.updateFaceData()` before each inference call so the temporal feature buffer contains real physiological signals rather than raw noisy sensor readings.

---

## 6. Core — Services

### 6.1 Foreground Notification Service

**File:** `lib/core/services/notifications.dart`

Manages the Android foreground service that keeps monitoring alive when the app is backgrounded or the screen is locked.

**Key behaviors:**
- `BantayDriveService.startService()` — launches the foreground task with a persistent notification showing the current driver state
- `BantayDriveService.updateState(state)` — updates the notification text (e.g., "Monitoring Active — Drowsy Detected") with a 2-second throttle to prevent Android from dropping button tap events due to rapid rebinds
- `BantayDriveService.stopService()` — tears down the foreground task
- `BantayDriveTaskHandler` — handles the "Stop" button in the notification by sending a message through `FlutterForegroundTask.sendDataToMain()`, which `MonitorScreen` receives via `_onReceiveTaskData()`

The foreground service ensures the camera inference loop continues even when the user switches to another app or the screen turns off.

---

### 6.2 PiP Service

**File:** `lib/core/services/pip_service.dart`

Bridges Flutter and the native Android PiP (Picture-in-Picture) API via platform channels.

**Methods:**
- `PipService.setRecording(bool)` — tells the native side whether recording is active (affects PiP aspect ratio and controls)
- `PipService.enterPip()` — invokes the native method to enter PiP mode
- `PipService.exitPip()` — invokes the native method to exit PiP mode
- `PipService.pipEventStream` — exposes an EventChannel stream of PiP lifecycle events (entered, exited) so `MonitorScreen` can update its layout

A cached stream reference (`_cachedStream`) is held to avoid the EventChannel being garbage-collected when the widget rebuilds during a PiP transition, which would otherwise drop events.

---

### 6.3 Video Clip Service

**File:** `lib/core/services/video_clip_service.dart`

Static utility class for managing video clip files generated when a Level 2 alert fires.

**Methods:**
- `saveClip(bytes, sessionId, alertType)` — writes the clip to `getApplicationDocumentsDirectory()/alert_clips/` with a timestamped filename and inserts a record into the database
- `deleteFile(path)` — removes the clip file from storage
- `exportToDownloads(path)` — copies the clip to the device's public Downloads folder so the user can access it outside the app
- `clipExists(path)` — checks whether a clip file is still present on disk

---

## 7. Core — Data

### 7.1 Database Helper

**File:** `lib/core/database/database_helper.dart`

Singleton SQLite database manager. All local session data, alerts, logs, and video clips are stored here.

#### Database Tables

| Table | Purpose |
|---|---|
| `sessions` | One row per drive session: start/end time, duration, safety score, state counts |
| `state_counts` | Per-session cumulative frame counts for neutral, drowsy, and distracted states |
| `alert_events` | Each alert that fired: session ID, type (drowsy/distracted), level (1/2), subclass, timestamp |
| `system_logs` | Timestamped inference log entries displayed in the Monitor screen's live log |
| `alertness_snapshots` | Periodic alertness percentage samples used for the sparkline chart |
| `video_clips` | File path, duration, alert type, and session reference for each saved clip |

#### Key Methods

**Sessions:**
- `insertSession()` — creates a new session row, returns the session ID
- `endSession(id, score, duration)` — writes the final score and duration on session stop
- `getAllSessions()` — returns all sessions ordered by start time descending
- `getSessionById(id)` — single session lookup

**Alerts:**
- `insertAlertEvent()` — called every time an alert fires
- `getAlertsBySession(sessionId)` — all alerts for a given session
- `getDailyAlertTrends(days)` — grouped daily alert counts for charts
- `getHourlyAlertDistribution()` — alert counts by hour of day (0–23)

**Analytics:**
- `getDashboardSummary()` — aggregated stats for the Dashboard screen (total drive time, total alerts, streak, avg alertness)
- `getAnalyticsSummary(period)` — full dataset for the Analytics screen filtered by time period
- `getDailySafetyScores(days)` — per-day safety scores for the history chart

**Maintenance:**
- `deleteSessionsOlderThan(days)` — enforces the data retention policy set in Settings
- `clearAllData()` — wipes all tables (triggered by "Clear Data" in Settings)

---

### 7.2 Session State

**File:** `lib/core/session_state.dart`

Static class that persists the currently active session identity in `SharedPreferences` so it survives the brief Flutter isolate restarts that some OEM devices (Xiaomi, Samsung) perform during foreground service transitions.

**Methods:**
- `ActiveSession.start(sessionId, startTime)` — writes session ID and start timestamp to SharedPreferences
- `ActiveSession.clear()` — clears the stored session identity after the session ends
- `ActiveSession.restoreIfNeeded()` — called on app boot; if a session ID is found in prefs (app was killed mid-session), it attempts to gracefully close that session in the database

**Properties:** `ActiveSession.sessionId`, `ActiveSession.startTime`, `ActiveSession.isActive`

---

### 7.3 Preferences Helper

**File:** `lib/core/preference/preference_helper.dart`

Singleton that wraps all `SharedPreferences` read/write operations for user-configurable settings.

| Preference key | Type | Default | Description |
|---|---|---|---|
| `alert_volume` | double | 0.85 | Alert audio volume (0.0–1.0) |
| `alert_sensitivity` | String | `'normal'` | Detection sensitivity: `'low'`, `'normal'`, `'high'` |
| `auto_start` | bool | false | Start recording automatically on app open |
| `show_session_summary` | bool | true | Show summary modal after stopping |
| `retention_period` | String | `'30d'` | Data retention: `'7d'`, `'30d'`, `'90d'`, `'forever'` |
| `clear_glasses` | bool | false | Adjusted EAR thresholds for glasses wearers |
| `onboarding_seen` | bool | false | Whether the onboarding walkthrough has been completed |
| `camera_guide_seen` | bool | false | Whether the camera placement guide has been dismissed |

**Sensitivity → threshold mapping** (used by `MonitorScreen`):
- Low: Level 1 at 8 frames, Level 2 at 18 frames
- Normal: Level 1 at 5 frames, Level 2 at 10 frames
- High: Level 1 at 3 frames, Level 2 at 6 frames

---

## 8. Core — Providers

**File:** `lib/core/providers.dart`

Centralized Riverpod provider definitions for global, reactive UI state shared between the Monitor screen and other tabs.

| Provider | Type | Description |
|---|---|---|
| `driverStateProvider` | StateNotifierProvider\<String\> | Current driver state: `'neutral'`, `'drowsy'`, `'distracted'` |
| `alertnessPctProvider` | StateNotifierProvider\<double\> | Alertness percentage (0–100) from the model's neutral probability |
| `drowsinessPctProvider` | StateNotifierProvider\<double\> | Drowsiness percentage (0–100) |
| `distractionPctProvider` | StateNotifierProvider\<double\> | Distraction percentage (0–100) |
| `isRecordingProvider` | StateNotifierProvider\<bool\> | Whether a monitoring session is currently active |
| `showAlertBannerProvider` | StateNotifierProvider\<bool\> | Whether the alert banner overlay is visible |
| `alertBannerTypeProvider` | StateNotifierProvider\<String?\> | Type of alert shown in the banner (e.g., `'drowsy'`, `'distracted'`) |
| `isInPipProvider` | StateNotifierProvider\<bool\> | Whether the app is currently in PiP mode |
| `activeSubclassProvider` | StateNotifierProvider\<String\> | Current behavior subclass label (e.g., `'distracted_phone'`) |
| `activeSubclassIndexProvider` | StateNotifierProvider\<int\> | Numeric index of the active subclass (0–12) |
| `navIndexProvider` | NotifierProvider\<int\> | Active bottom navigation tab index (0–4) |
| `deviceNameProvider` | FutureProvider\<String\> | Device model name from DeviceInfoPlugin |
| `dbChangeCounterProvider` | NotifierProvider\<int\> | Incremented whenever the DB is written; triggers reactive UI refreshes |

---

## 9. Widgets

### 9.1 Head Pose Indicator

**File:** `lib/widgets/head_pose_indicator.dart`

A circular custom-painted widget overlaid on the camera preview that provides real-time visual feedback on camera/head alignment.

**Visual elements:**
- Colored arc zones (green: tilt < 30°, yellow: 30–55°, red: > 55°) indicating how far the head is tilted relative to the camera axis
- A wiper-style camera icon that rotates with the head's roll angle
- A person silhouette in the center
- A dashed outer ring
- A text label: "Aligned", "Tilted", or "No Face" depending on detection status

**Parameters:**
- `roll` — head roll angle in degrees (from `HeadPoseService`)
- `hasFace` — whether a face is currently detected
- `size` — diameter of the indicator widget

---

### 9.2 Exit Dialog

**File:** `lib/widgets/exit.dart`

An `AlertDialog` shown when the user presses the Android back button from the main shell. Prevents accidental app exit.

**Buttons:**
- **Stay** — dismisses the dialog, user remains in the app
- **Exit** — calls `SystemNavigator.pop()` to close the app

If a recording session is active when the back button is pressed, the dialog includes a warning that the session will be ended.

---

## 10. Utilities — Responsive Layout

**File:** `lib/utils/responsive.dart`

A device-aware scaling system that ensures the UI renders consistently across all Android phone sizes and OEM brands.

**Design base:** 390 dp × 844 dp (Pixel 6 mid-range reference)

**Phone size tiers:**

| Tier | Width | Example devices |
|---|---|---|
| Compact | < 360 dp | Galaxy A03, budget phones |
| Small | 360–379 dp | Redmi Note series |
| Medium | 380–409 dp | Pixel 6, Galaxy A54 |
| Large | 410–429 dp | Pixel 7 Pro |
| XLarge | ≥ 430 dp | Galaxy S23 Ultra |

**Brand-aware scale multipliers:**

| Brand | Multiplier | Reason |
|---|---|---|
| Samsung | 0.92× | One UI inflates default text and UI chrome |
| Xiaomi / Oppo / Vivo | 0.97× | MIUI/ColorOS render slightly larger than stock |
| Pixel / Other | 1.00× | No adjustment needed |

**Scale functions (all use the same unified factor):**
- `context.sp(14)` — font size scaled from base
- `context.rp(16)` — horizontal padding/spacing
- `context.rs(12)` — vertical spacing (height-driven)
- `context.ri(20)` — icon size
- `context.wp(0.05)` — 5% of screen width
- `context.hp(0.10)` — 10% of screen height
- `context.forTier(base: 14.0, compact: 11.0, large: 16.0)` — pick different value per phone tier

The unified scale factor is clamped to [0.82, 1.20] to prevent extreme sizes on very small or very large phones.

---

## 11. Assets & Model

```
assets/
├── model/
│   └── dms_hybridnet_v3_float32.tflite   ← AI model (float32, dual-input)
├── norm_params.json                        ← Feature normalization mean/scale values
└── sounds/
    ├── alert_level1.mp3                    ← Short chime for Level 1 alerts
    └── alert_level2.mp3                    ← Looping alarm for Level 2 alerts
```

**norm_params.json** — Contains the `mean` and `scale` arrays (one value per temporal feature dimension) used to z-score normalize the temporal input before feeding it to the model. These were computed from the training dataset.

---

## 12. Key Dependencies

| Package | Version | Purpose |
|---|---|---|
| `flutter_riverpod` | ^3.3.1 | State management |
| `camera` | ^0.12.0+1 | Camera preview and frame streaming |
| `tflite_flutter` | ^0.12.1 | On-device TFLite inference |
| `google_mlkit_face_detection` | ^0.13.2 | Face landmark detection for EAR/MAR/pose |
| `sqflite` | ^2.3.0 | Local SQLite database |
| `shared_preferences` | ^2.3.0 | Persistent user settings |
| `flutter_foreground_task` | ^9.2.2 | Android foreground service |
| `fl_chart` | ^1.2.0 | Line, bar, and pie charts |
| `audioplayers` | ^6.0.0 | Alert sound playback |
| `volume_controller` | ^3.4.4 | System volume control |
| `video_player` | ^2.9.2 | Playback of saved alert clips |
| `shimmer` | ^3.0.0 | Loading skeleton animations |
| `permission_handler` | ^12.0.1 | Runtime permission requests |
| `device_info_plus` | ^13.0.0 | Device model/brand detection |
| `package_info_plus` | ^10.0.0 | App version/build number |
| `path_provider` | ^2.1.2 | App storage directory paths |
| `sensors_plus` | ^7.0.0 | Accelerometer (motion context) |
| `url_launcher` | ^6.3.0 | Open external URLs from Settings |
