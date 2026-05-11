# Bantay Drive — Changelog

**App name:** Bantay Drive
**Platform:** Android
**Last updated:** May 11, 2026

---

## What's in the App (Feature List)

A running summary of everything that has been built into Bantay Drive from start to current.

---

### Core Monitoring

- **Live AI driver monitoring** using the front camera with on-device inference (no internet required)
- **13 behavior classes** detected across three parent states: Natural, Drowsy, and Distracted
- **Frame-by-frame inference** with real-time detection overlays on the camera preview
- **Detection state badge** showing current state: NATURAL, DROWSY, or DISTRACTED
- **Alertness gauge, Drowsiness gauge, and Distraction gauge** (all 0–100%)
- **Head Pose Indicator** — color-coded ring (green / yellow / red / dashed) showing whether your face angle is within the ideal range for accurate detection
- **Head pose label** displayed alongside the indicator for clarity
- **Session timer** shown during active monitoring
- **System log** — scrollable live feed of inference events during a session
- **FPS-optimized monitor screen** — revised multiple times to reduce frame drops and prevent UI freezes from frame processing delays

---

### Alert System

- **Two-level alert system** with automatic escalation
  - Level 1: short audio chime + brief on-screen banner (~1 sec trigger at Normal sensitivity)
  - Level 2: louder looping alarm + persistent warning banner + video clip saved (~2 sec trigger at Normal sensitivity)
- **Three sensitivity modes** — Low, Normal, High — adjusting how many consecutive unsafe frames are needed before an alert fires
- **Alert cooldown** to prevent the same alert from repeating in rapid succession
- **Alert banner** showing the detected behavior type and level; dismissed by tapping or by resuming safe driving
- **Alert volume slider** (0–100%) that also adjusts the phone's media volume
- **Video clips saved on Level 2 alerts** — clips up to 10 seconds long

---

### Session Management

- **Start / Stop session** with a single tap on the Monitor screen
- **Foreground service notification** so monitoring continues if you switch apps; includes a Stop button in the notification shade
- **Auto-Start Recording** setting — monitoring begins automatically when the Monitor tab is opened
- **Session Summary modal** — slides up after stopping a session, showing duration, safety score, state breakdown, and alert count; can be disabled in Settings
- **Graceful session recovery** — if the app crashes or is killed, it attempts to save the interrupted session on next launch
- **Disk full handling** — the app gracefully manages storage-full scenarios during recording

---

### Picture-in-Picture (PiP) Mode

- **PiP button** in the Monitor screen app bar to shrink monitoring into a floating window
- AI monitoring loop, alerts, and audio all continue while in PiP
- Tap the floating window to return to full screen
- Requires Android 8.0+

---

### Home Dashboard

- **Safety score ring** (0–100%) with color-coded rating: Excellent / Good / Fair / Needs Improvement
- **Trend arrow** showing whether your score improved or declined compared to previous sessions
- **Score calculation** based on alert deductions per minute of driving (Level 1 = −2 pts, Level 2 = −5 pts)
- **Four quick-stat cards:** Total Drive Time, Alerts (24h), Safety Streak, Avg Alertness
- **Empty state placeholders** when no sessions have been recorded yet
- **Safety score history chart** — 30-day line chart with green / yellow / red score zones
- **Alertness sparkline** for the most recent session
- **Auto-refresh every 30 seconds** while the dashboard is visible
- **Skeleton loading screens** while data is being fetched

---

### Analytics

- **Drowsy vs. Distracted trend chart** — dual-line chart of daily alert counts
- **Hourly alert distribution chart** — bar chart identifying your highest-risk time windows
- **Safety score history chart** with a trend line
- **Alert type breakdown** — which specific behaviors triggered the most alerts
- **Time range filter** — 7 Days, 30 Days, or All Time
- **Responsive filter layout** — filters adapt cleanly to different screen sizes
- **Skeleton loading screens** while charts load

---

### History

- **Session Logs tab** — all completed sessions in reverse chronological order
  - Shows date, duration, safety score (color-coded badge), and Level 1 / Level 2 alert counts
  - Human-readable date formatting on all session entries
  - Filter by date range, detection type, alert level, or text search
  - Tap a session to open a detail sheet with alertness timeline, individual alert events, system log, and linked video clips
- **Video Logs tab** — all saved alert clips
  - Thumbnail, duration, alert type, date and time shown per clip
  - In-app video player
  - Export to Downloads folder
  - Delete individual clips

---

### Settings

| Setting | Details |
|---|---|
| **Alert Volume** | Slider 0–100%, default 85% |
| **Alert Sensitivity** | Low / Normal / High |
| **Auto-Start Recording** | Toggle, default Off |
| **Show Session Summary** | Toggle, default On |
| **Data Retention** | 7 days / 30 days (default) / 90 days / Forever |
| **Clear All Data** | Permanently wipes all sessions, alerts, logs, and clips (with confirmation) |
| **About** | App version, build number, developer credits |

---

### Onboarding

- **Four-page onboarding walkthrough** on first launch: Live Monitoring, Smart Analytics, Instant Alerts, Session History
- Shown only once; never repeated on subsequent launches

---

### Database & Storage

- **Local SQLite database** storing sessions, alerts, system logs, and state counts
- **Automatic data retention cleanup** on app launch based on the selected retention period
- **Video clips stored in app private storage** with export to Downloads folder on request
- **Screen auto-refresh** via state notifiers so History and Dashboard stay up to date without manual reload

---

### UI / UX

- **Bottom navigation bar** with five tabs: Home, Monitor, Analytics, History, Settings
- **Color-coded safety score badges** throughout the app
- **Portrait orientation** supported (standard use case)
- **Responsive layouts** on monitor and filter screens
- **Animations** on the Analytics screen
- **Clear Glasses Mode** (Settings) for improved eye detection when wearing glasses

---

*Bantay Drive — Keeping drivers safe with on-device AI.*
