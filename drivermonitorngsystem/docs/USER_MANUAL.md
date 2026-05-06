# Bantay Drive — User Manual

**App name:** Bantay Drive
**Version:** 1.0.0
**Platform:** Android
**Purpose:** Real-time AI-powered driver monitoring system for drowsiness and distraction detection

---

## Table of Contents

1. [Introduction](#1-introduction)
2. [Getting Started](#2-getting-started)
   - [First Launch & Onboarding](#21-first-launch--onboarding)
   - [App Navigation](#22-app-navigation)
3. [Home (Dashboard)](#3-home-dashboard)
   - [Safety Score](#31-safety-score)
   - [Quick Stats](#32-quick-stats)
   - [Safety Score History Chart](#33-safety-score-history-chart)
4. [Monitor](#4-monitor)
   - [Camera Setup](#41-camera-setup)
   - [Starting a Session](#42-starting-a-session)
   - [Live Monitoring Display](#43-live-monitoring-display)
   - [Alert System](#44-alert-system)
   - [Stopping a Session](#45-stopping-a-session)
   - [Session Summary](#46-session-summary)
   - [Picture-in-Picture (PiP) Mode](#47-picture-in-picture-pip-mode)
5. [Analytics](#5-analytics)
   - [Filter by Time Range](#51-filter-by-time-range)
   - [Charts and Insights](#52-charts-and-insights)
6. [History](#6-history)
   - [Session Logs](#61-session-logs)
   - [Video Logs](#62-video-logs)
7. [Settings](#7-settings)
   - [Alert Volume](#71-alert-volume)
   - [Alert Sensitivity](#72-alert-sensitivity)
   - [Auto-Start Recording](#73-auto-start-recording)
   - [Show Session Summary](#74-show-session-summary)
   - [Data Retention](#75-data-retention)
   - [Clear All Data](#76-clear-all-data)
   - [About](#77-about)
8. [Detection Behavior Classes](#8-detection-behavior-classes)
9. [Recommended Camera Placement](#9-recommended-camera-placement)
10. [Frequently Asked Questions](#10-frequently-asked-questions)
11. [Troubleshooting](#11-troubleshooting)

---

## 1. Introduction

**Bantay Drive** is a smartphone-based Driver Monitoring System (DMS) that uses your phone's front camera and an on-device AI model to watch for signs of drowsiness and distraction while you drive. It does not require an internet connection — all processing happens locally on your device.

**What it detects:**

| Category | Examples |
|---|---|
| Drowsiness | Microsleep, eye fatigue, heavy eyelids, yawning |
| Distraction | Phone use, texting, eating/drinking, grooming, radio tuning, smoking |

**What it does when it detects unsafe behavior:**

- Plays an audio alert to bring your attention back to the road
- Shows a visual warning banner on screen
- Records the event in your session history
- Saves a short video clip of the alert moment (Level 2 alerts)

---

## 2. Getting Started

### 2.1 First Launch & Onboarding

When you open Bantay Drive for the first time, you will see a brief onboarding walkthrough with four pages:

1. **Live Monitoring** — Explains the real-time AI camera detection feature
2. **Smart Analytics** — Shows how driving trends are tracked over time
3. **Instant Alerts** — Describes the audio and visual alert system
4. **Session History** — Shows how past drives and video clips are stored

Swipe left or tap **Next** to move through the pages. Tap **Get Started** on the last page to enter the app. You will not see this walkthrough again on subsequent launches.

### 2.2 App Navigation

Bantay Drive has five main sections accessible from the bottom navigation bar:

| Tab | Icon | Description |
|---|---|---|
| **Home** | House icon | Safety metrics dashboard |
| **Monitor** | Camera icon | Live driver monitoring |
| **Analytics** | Chart icon | Trends and insights |
| **History** | Clock icon | Past sessions and video clips |
| **Settings** | Gear icon | App configuration |

---

## 3. Home (Dashboard)

The **Home** tab gives you an at-a-glance overview of your driving safety performance. Data refreshes automatically every 30 seconds while you are on this screen.

### 3.1 Safety Score

A large circular ring at the top of the screen shows your **overall safety score** from 0 to 100%.

| Score range | Rating |
|---|---|
| 85 – 100% | Excellent |
| 70 – 84% | Good |
| 50 – 69% | Fair |
| Below 50% | Needs improvement |

An arrow indicator shows whether your score is trending up or down compared to your previous sessions.

**How the score is calculated:**
Each alert that fires during a session deducts points. Level 1 alerts deduct 2 points and Level 2 alerts deduct 5 points. The total deduction is divided by how long you drove (in minutes), then multiplied by 10. The result is subtracted from 100. A minimum drive time of 2 minutes is used to prevent very short test sessions from producing extreme scores.

### 3.2 Quick Stats

Four stat cards below the safety score ring show:

| Card | Description |
|---|---|
| **Total Drive Time** | Cumulative hours driven across all recorded sessions |
| **Alerts (24h)** | Number of alerts that fired in the last 24 hours |
| **Safety Streak** | Consecutive days where you completed a session with zero alerts |
| **Avg Alertness** | Your average alertness percentage across all sessions |

If you have not recorded any sessions yet, placeholder cards are shown encouraging you to start your first drive.

### 3.3 Safety Score History Chart

A line chart below the stats cards shows your daily safety scores for the last 30 days. Colored zones on the chart help you identify:
- **Green zone** — Safe scores (above 70%)
- **Yellow zone** — Fair scores (50–70%)
- **Red zone** — Poor scores (below 50%)

An alertness sparkline for your most recent session is shown beneath the main chart.

---

## 4. Monitor

The **Monitor** tab is the core feature of the app. This is where live AI-powered driver monitoring takes place.

### 4.1 Camera Setup

Before starting a session, position your phone so that:
- The **front camera faces your face** clearly
- Your **eyes are visible** in the frame
- The phone is mounted to the **right side of the steering column** at approximately a 30–45° angle (standard phone holder position)
- Your face is **not partially blocked** by the steering wheel or your hands

A **Head Pose Indicator** is displayed on the camera preview to help you align correctly:

| Indicator color | Meaning |
|---|---|
| **Green** | Head tilt is within the ideal range (< 30°) |
| **Yellow** | Head is moderately tilted (30–55°) — try to straighten up |
| **Red** | Head tilt is too extreme (> 55°) — monitoring accuracy will be reduced |
| **Dashed ring** | No face detected — reposition the camera |

The camera icon inside the gauge rotates to show your current head roll angle relative to the camera axis.

> **Tip:** If you wear glasses, enable **Clear Glasses Mode** in Settings for improved eye detection accuracy.

### 4.2 Starting a Session

Tap the **Start** button (circular button at the bottom of the camera preview) to begin a monitoring session.

When a session starts:
- A pulsing red dot appears in the top app bar indicating active recording
- The foreground service notification appears in your notification shade so monitoring continues if you switch apps
- Frame-by-frame AI analysis begins immediately

If **Auto-Start Recording** is enabled in Settings, monitoring begins automatically whenever you open the Monitor tab.

### 4.3 Live Monitoring Display

While a session is in progress, the Monitor screen shows:

| Element | Description |
|---|---|
| **Camera preview** | Live front-facing camera feed with detection overlays |
| **Head Pose Indicator** | Circular gauge showing head tilt alignment |
| **Detection state badge** | Current state label: NATURAL, DROWSY, or DISTRACTED |
| **Alertness gauge** | Circular meter (0–100%) showing current alertness level |
| **Drowsiness gauge** | Percentage likelihood of drowsy behavior |
| **Distraction gauge** | Percentage likelihood of distracted behavior |
| **System log** | Scrollable live feed of inference events and alerts |

### 4.4 Alert System

Bantay Drive uses a three-level alert system that escalates based on how long unsafe behavior continues.

#### Level 1 Alert
- **Trigger:** Unsafe behavior detected for approximately 1 second (5 consecutive frames at normal sensitivity)
- **Action:** A short audio chime plays and a banner notification appears briefly on screen
- **Purpose:** A gentle reminder to refocus on the road

#### Level 2 Alert
- **Trigger:** Unsafe behavior continues for approximately 2 seconds (10 consecutive frames at normal sensitivity)
- **Action:** A louder looping alarm plays, a persistent warning banner remains on screen, and a short video clip of the event is saved
- **Purpose:** A strong warning when the driver has not responded to the Level 1 alert

#### Alert Cooldown
After an alert fires, a brief cooldown period prevents the same alert from firing repeatedly in quick succession. If the unsafe behavior continues past the cooldown window, a new alert will trigger.

#### Alert Banner
The alert banner shows:
- The type of behavior detected (e.g., "Drowsy Detected" or "Distracted — Phone Use")
- The alert level (Level 1 or Level 2)

Tapping the banner or resuming safe driving dismisses it.

### 4.5 Stopping a Session

Tap the **Stop** button to end the monitoring session.

You can also stop a session from the **foreground service notification** in your notification shade by tapping the Stop button there.

When stopped:
- The session is saved to the database with its duration, safety score, and all recorded events
- The alert sound stops
- The foreground service notification is dismissed
- The Session Summary modal appears (if enabled in Settings)

### 4.6 Session Summary

After stopping a session, a summary sheet slides up from the bottom of the screen showing:

| Field | Description |
|---|---|
| **Duration** | Total time the session was active |
| **Safety Score** | Final computed safety score for this session |
| **State breakdown** | Time spent in Natural / Drowsy / Distracted states |
| **Alert count** | Number of Level 1 and Level 2 alerts that fired |

Tap **View History** to go directly to the session detail in the History tab, or dismiss the sheet to return to the Monitor screen.

You can turn off this modal in **Settings → Show Session Summary**.

### 4.7 Picture-in-Picture (PiP) Mode

Tap the **PiP button** (icon in the top-right of the Monitor screen app bar) to shrink the monitoring view into a small floating window.

In PiP mode:
- The AI monitoring loop continues running without interruption
- You can use other apps on your phone while monitoring is active
- Alerts will still fire and play audio through PiP

To return to full-screen monitoring, tap the floating PiP window.

> **Note:** PiP mode requires Android 8.0 (API 26) or higher.

---

## 5. Analytics

The **Analytics** tab shows detection trends and patterns across your driving history to help you understand when and how often unsafe driving behavior occurs.

### 5.1 Filter by Time Range

Three filter tabs at the top of the Analytics screen let you select the data range:

| Filter | Description |
|---|---|
| **7 Days** | Last 7 days of sessions |
| **30 Days** | Last 30 days of sessions |
| **All Time** | All recorded sessions |

Tap a filter to reload all charts for that period.

### 5.2 Charts and Insights

| Chart | Description |
|---|---|
| **Drowsy vs. Distracted trend** | Dual-line chart showing daily drowsy and distracted alert counts side by side |
| **Hourly alert distribution** | Bar chart showing which hour of the day your alerts are most frequent — helps identify high-risk time windows |
| **Safety score history** | Line chart of daily safety scores over the selected period with a trend line |
| **Alert type breakdown** | Segmented view of which specific behaviors triggered the most alerts (phone, grooming, drowsy, etc.) |

---

## 6. History

The **History** tab contains a complete record of all your past monitoring sessions and saved video clips. It has two sub-tabs.

### 6.1 Session Logs

The **Session Logs** tab lists all completed sessions in reverse chronological order (most recent first).

**Each session entry shows:**
- Date and time the session started
- Session duration
- Safety score with a color-coded badge
- Number of Level 1 and Level 2 alerts

**Filtering and search:**
Use the filter controls at the top to narrow results by:
- Date range
- Detection type (Drowsy / Distracted)
- Alert level (Level 1 / Level 2)
- Text search (by date, month, or year)

**Session Detail:**
Tap any session to open a detail sheet showing:
- Full duration, safety score, and state count breakdown
- Alertness timeline chart for that session
- List of every individual alert event with timestamp and type
- System log entries recorded during the session
- Any video clips saved during that session

### 6.2 Video Logs

The **Video Logs** tab lists all alert video clips saved by the app.

**Each clip entry shows:**
- Video thumbnail
- Clip duration
- Type of alert that triggered the recording (drowsy / distracted)
- Date and time of the alert

**Actions:**
- Tap a clip to play it in the in-app video player
- Tap the **Export** button to copy the clip to your device's Downloads folder so you can share or save it outside the app
- Tap the **Delete** button to permanently remove the clip from the device

---

## 7. Settings

The **Settings** tab lets you configure how Bantay Drive behaves.

### 7.1 Alert Volume

A slider that controls the volume of alert sounds (0–100%).

- Moving the slider also adjusts your phone's media volume
- At 0%, alert sounds are muted (not recommended while driving)
- Default: 85%

### 7.2 Alert Sensitivity

A segmented selector that controls how quickly the app triggers alerts.

| Sensitivity | Level 1 trigger | Level 2 trigger | Recommended for |
|---|---|---|---|
| **Low** | ~1.6 seconds | ~3.6 seconds | Casual use, testing |
| **Normal** (default) | ~1.0 second | ~2.0 seconds | Most drivers |
| **High** | ~0.6 seconds | ~1.2 seconds | Drivers prone to microsleep |

Higher sensitivity = fewer consecutive unsafe frames required before an alert fires, meaning faster but potentially more frequent alerts.

### 7.3 Auto-Start Recording

When enabled, Bantay Drive automatically starts a monitoring session whenever you open the Monitor tab.

- Default: Off
- Useful if you always start monitoring at the beginning of every drive without tapping Start manually

### 7.4 Show Session Summary

When enabled, a summary modal appears after you stop a session, showing your score, alert count, and state breakdown.

- Default: On
- Turn this off if you prefer to check results later in the History tab

### 7.5 Data Retention

Controls how long session data, alerts, and video clips are kept before being automatically deleted.

| Option | Description |
|---|---|
| **7 days** | Delete sessions older than 7 days on next app launch |
| **30 days** (default) | Delete sessions older than 30 days |
| **90 days** | Delete sessions older than 90 days |
| **Forever** | Never automatically delete data |

> **Note:** Deleted sessions cannot be recovered. If device storage is a concern, choose a shorter retention period.

### 7.6 Clear All Data

A destructive action that permanently deletes **all sessions, alerts, logs, and video clips** from your device.

A confirmation dialog will appear before data is erased. This action cannot be undone.

### 7.7 About

Shows the current app version and build number, and the developer credits.

---

## 8. Detection Behavior Classes

Bantay Drive classifies driver behavior into 13 specific classes grouped under three parent states.

### Natural (Safe)

| Class | Description |
|---|---|
| **Safe driving** | Driver is focused on the road with eyes forward |
| **Talking to passenger** | Driver is conversing while keeping eyes on the road |

### Drowsy

| Class | Description |
|---|---|
| **Drowsy — Yawning** | Driver is yawning with eyes open |
| **Drowsy — Yawning (occluded)** | Yawning with partial face occlusion (e.g., hand covering mouth) |
| **Drowsy — Fatigue** | Heavy eyelids, reduced eye opening, sluggish movements |
| **Drowsy — Microsleep** | Eyes closed for an involuntary brief sleep episode |

### Distracted

| Class | Description |
|---|---|
| **Texting** | Driver looking down at a phone while typing |
| **Phone use** | Driver holding phone to ear or looking at screen |
| **Radio / Controls** | Reaching for or operating dashboard controls |
| **Eating / Drinking** | Driver consuming food or beverage |
| **Body movement** | Reaching, turning around, or other large body movements |
| **Grooming** | Adjusting hair, makeup, or other grooming activity |
| **Smoking** | Driver holding or using a cigarette |

---

## 9. Recommended Camera Placement

Correct camera placement is critical for accurate detection. Follow these guidelines for best results.

### Ideal Position

```
       Steering Wheel
           [  O  ]
              |
         Driver Face
              |
    [Phone mounted to the right]
         ~30–45° angle
```

- Mount your phone in a car phone holder on the **right side of the steering column**
- Angle the phone so the front camera points toward your **face**, not the ceiling or dashboard
- The ideal mount angle is **30–45°** from vertical
- Your **eyes should be clearly visible** in the camera frame at all times

### Checklist

- [ ] Front camera faces your face
- [ ] Eyes are not blocked by the steering wheel
- [ ] Phone is secured firmly and will not shift while driving
- [ ] Camera is not pointed at the ceiling or dashboard
- [ ] Head Pose Indicator shows **green** before starting a session
- [ ] No strong backlight (sun directly behind your head) washing out the image

### Notes for Glasses Wearers

If you wear clear glasses, enable **Settings → Clear Glasses Mode** to adjust eye detection thresholds and reduce false drowsiness alerts caused by lens reflections.

---

## 10. Frequently Asked Questions

**Does the app require an internet connection?**
No. All AI inference runs entirely on your device. No data is uploaded to any server.

**Does the app drain my battery?**
Running the camera and AI model continuously does use significant battery. It is recommended to plug your phone into a car charger while using Bantay Drive on long drives.

**What is the minimum Android version required?**
Android 8.0 (API 26) or higher. Picture-in-Picture mode also requires Android 8.0+.

**Can I use the app while navigating with Google Maps?**
Yes. Start your monitoring session, then use the PiP button to minimize Bantay Drive into a floating window. Open Google Maps normally. Monitoring will continue running in the background.

**Why am I getting alerts even when I am not drowsy?**
Check your camera placement. If your head is frequently tilted (yellow or red on the Head Pose Indicator), the model may misinterpret the angle as a distraction behavior. Re-center the phone mount so the camera faces your face more directly.

**Where are video clips stored?**
Clips are saved in the app's private storage. Use the **Export** button in Video Logs to copy a clip to your Downloads folder if you want to access it outside the app.

**I stopped mid-session and the app crashed. Is my session data lost?**
Bantay Drive saves session state to the device persistently. If the app restarts after an unexpected shutdown, it attempts to gracefully close and save the interrupted session. Check History to see if the session was recorded.

**How do I reduce false alerts?**
- Increase the alert sensitivity to **Low** in Settings
- Ensure correct camera placement (green on Head Pose Indicator)
- Enable **Clear Glasses Mode** if you wear glasses
- Avoid strong backlighting behind your head (e.g., driving directly into a sunset)

---

## 11. Troubleshooting

| Issue | Possible cause | Solution |
|---|---|---|
| No face detected (dashed ring) | Camera not facing driver correctly | Adjust phone mount angle; ensure face is in frame |
| Frequent false drowsy alerts | Glasses lens reflection or extreme head tilt | Enable Clear Glasses Mode; re-center phone mount |
| App does not stay running in background | Battery optimization killing the app | Disable battery optimization for Bantay Drive in Android Settings → Battery → App battery usage |
| Alert sound not playing | Volume set to 0 or phone is on silent | Check Alert Volume in Settings; check phone ringer/media volume |
| Video clips not saving | Storage permission denied | Grant storage permission in Android Settings → Apps → Bantay Drive → Permissions |
| PiP mode not available | Android version below 8.0 | PiP requires Android 8.0+; update your Android version if possible |
| Session does not start automatically | Auto-Start disabled | Enable Auto-Start Recording in Settings |
| Analytics charts show no data | No sessions recorded yet | Complete at least one monitoring session to populate charts |
| App lags or drops frames | Device is too busy / low RAM | Close background apps before starting a session; restart the phone if needed |

---

*Bantay Drive — Keeping drivers safe with on-device AI.*
