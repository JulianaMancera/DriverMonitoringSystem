<!-- # Alert Video Clip Feature
**Bantay Drive — Driver Monitoring System**

---

## Overview

The Alert Video Clip feature automatically records the driver's camera feed during a monitoring session and saves a video clip **only when a drowsiness or distraction alert is triggered**. Safe drives (no alerts) produce zero saved videos, keeping device storage clean.

---

## How It Works — Full Flow

```
Driver taps [Record]
        │
        ▼
Session starts + video recording begins (saved to temporary storage)
        │
        ▼
AI monitors driver in real time (inference continues normally)
        │
        ├── No alerts fired the entire session
        │         │
        │         ▼
        │   Driver taps [Stop]
        │   Temp video is DELETED automatically
        │   Session saved as "Safe Drive" — no video entry
        │
        └── Alert triggered (Drowsiness or Distraction — any level)
                  │
                  ▼
            Alert type is recorded internally
                  │
                  ▼
            Driver taps [Stop]
            Video clip is SAVED to app storage
            Clip is linked to the session in the database
                  │
                  ▼
            Clip appears in History → Video Logs tab
```

---

## Where Videos Are Stored

| Stage | Location |
|---|---|
| During session (temp) | Device temp directory (`/data/data/.../cache/`) |
| After session with alerts (saved) | App documents directory (`/data/data/.../files/alert_clips/`) |
| After user downloads | Device Downloads folder (`/storage/emulated/0/Download/`) |

Videos in the app documents directory are **private to the app**. The user must explicitly tap "Download" to export a copy to the public Downloads folder.

---

## History Screen — Two Tabs

The History screen is split into two tabs:

### Tab 1 — Session Logs
The existing session history view. Shows all completed drive sessions with:
- Date and time
- Session duration
- Alert count badge ("Safe" or "X alerts")
- Filter chips: All / This Week / This Month / With Alerts / Safe Drives
- Tap a session to open the detailed bottom sheet (state breakdown, alert events, system log)

### Tab 2 — Video Logs
Shows only sessions that produced an alert video. Each card displays:
- Alert type label — **Drowsiness Alert**, **Distraction Alert**, or **Drowsy + Distracted**
- Time the clip was created
- Session number reference
- Clip duration (if available)

**Interactions on Video Logs:**
- **Tap** a clip → opens the in-app video player
- **Long press** or **tap the checkbox** → selects the clip for download
- **Swipe left** → prompts to delete the clip
- Select one or more clips → **Download** button appears at the bottom
- Tap **Download** → clips are copied to the device's Downloads folder

---

## In-App Video Player

Opening a clip shows a full-screen dialog with:
- Video playback (auto-plays on open)
- Tap the video to pause / resume
- Scrubable progress bar at the bottom
- Close button in the top-right corner

---

## Download Behavior

- Selecting clips and tapping **Download** copies each selected video to `/storage/emulated/0/Download/` (the standard Android Downloads folder).
- A snackbar confirms how many videos were saved, or shows an error if storage access failed.
- The original clip inside the app is **not deleted** after download — the user must swipe-to-delete manually if they want to remove it.
- Videos are **not downloaded automatically** at any point; the driver always chooses which clips to keep.

---

## Clip Naming Convention

Saved clips are named:
```
clip_<sessionId>_<timestamp>.mp4
```
Example: `clip_42_1714210800000.mp4`

Downloaded clips keep the same filename so they are easy to trace back to a session.

---

## Storage Cleanup

- When the user taps **Clear All History** in Settings, all video files are deleted from disk alongside the database rows.
- When the user sets a data retention period (e.g. "keep last 30 days"), clips from expired sessions are deleted automatically.
- Individual clips can be deleted by swiping left on a card in the Video Logs tab.

---

## Technical Notes (for developers)

| Component | File |
|---|---|
| File save / delete / export logic | `lib/core/services/video_clip_service.dart` |
| Database table (`video_clips`) + CRUD | `lib/core/database/database_helper.dart` |
| Recording start / stop in session | `lib/screens/monitor_screen.dart` |
| Video Logs UI + player | `lib/screens/history_screen.dart` |

### Recording approach
The `camera` plugin's `startVideoRecording()` is called alongside the existing `startImageStream()` (used for AI inference). On Android with the CameraX backend, these run as concurrent use cases — the live preview and AI model are **not interrupted** when recording starts or stops.

If `startVideoRecording()` fails on a device (e.g., unsupported hardware), the app catches the error silently and continues monitoring without video. The session, alert events, and all other data are still saved normally.

### Alert threshold for saving
Any alert level (L1, L2, or L3) marks the session as "has alerts," which causes the clip to be saved. A session with zero alerts is treated as a safe drive and the temp file is discarded on stop.

---

## User-Facing Summary (for User Manual draft)

> **Alert Videos** are short recordings that Bantay Drive saves automatically whenever it detects drowsiness or distraction during a trip.
>
> - If you drove safely with no alerts, **no video is saved** and nothing is stored.
> - If an alert was triggered, a video clip is saved and visible under **History → Video Logs**.
> - You can **watch** any saved clip directly in the app by tapping it.
> - To **download** a clip to your phone's Downloads folder, tap and hold (or tick the checkbox), then tap the **Download** button.
> - To **delete** a clip, swipe it to the left and confirm.
> - Videos are stored privately on your device and are never uploaded anywhere. -->
