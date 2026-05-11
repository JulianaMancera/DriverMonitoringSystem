# Use Cases — Bantay Drive: Driver Monitoring System

---

## Actors

| Actor | Role |
|---|---|
| **Driver** | Primary user — interacts with the app directly via touch |
| **System** | Automated background processes (inference engine, alert logic, data logging) |
| **Android OS** | Platform services (notifications, foreground service, scoped storage) |

---

## Summary Map

```
Driver ──→ UC-01: First Launch & Onboarding   (first install only)
        ──→ UC-02: View Dashboard
        ──→ UC-03: Start Monitoring Session
                      └──→ [System] UC-04: Detect & Escalate Alert
                                        └──→ [System] UC-06: Record Alert Video Clip
        ──→ UC-05: Monitor via Picture-in-Picture  (extends UC-03)
        ──→ UC-07: Stop Monitoring Session
        ──→ UC-08: View Session History & Video Clips
        ──→ UC-09: View Analytics
        ──→ UC-10: Configure Settings
```

---

## UC-01: First Launch & Onboarding

**Actor:** Driver  
**Trigger:** Driver opens the app for the very first time after installation.

### Preconditions
- App is installed on an Android device.
- Onboarding has not yet been completed (flag not set in `shared_preferences`).

### Main Flow
1. Driver launches the app.
2. System checks `shared_preferences` for the onboarding-seen flag.
3. Flag is not set → System displays the Onboarding screen.
4. Onboarding presents 4 pages in sequence:
   - Page 1 — Live Monitoring
   - Page 2 — Drive Analytics
   - Page 3 — Instant Alerts
   - Page 4 — Trip History
5. Driver taps **Next** to advance through each page.
6. On the final page, driver taps **Get Started**.
7. System writes the onboarding-seen flag to `shared_preferences`.
8. App navigates to the Dashboard screen.

### Postconditions
- Onboarding-seen flag is stored persistently.
- Driver is on the Dashboard screen.
- Onboarding will not be shown again on future launches.

### Alternative Flows

**A1 — Driver skips onboarding:**
- At any page before the last, driver taps **Skip**.
- Steps 5–6 are bypassed.
- System writes the onboarding-seen flag and navigates to Dashboard.

**A2 — App already onboarded:**
- At step 3, flag is already set.
- Onboarding screen is not shown.
- App navigates directly to Dashboard (or Monitor if Auto-Start is enabled).

---

## UC-02: View Dashboard

**Actor:** Driver  
**Trigger:** Driver opens the app after onboarding, or taps the Dashboard tab in the bottom navigation.

### Preconditions
- Onboarding has been completed.
- App is in the foreground.

### Main Flow
1. Driver opens the app or taps the Dashboard tab.
2. System queries the local SQLite database and loads:
   - Total drive time accumulated over the last 30 days.
   - Total alert count from the last 24 hours.
   - Current safety streak (days since last critical alert).
   - Average alertness score over the last 7 days.
   - Average safety score over the last 30 days.
   - Snapshots from the most recent sessions.
   - Daily safety score values for the past 30 days (chart data).
3. Dashboard renders a safety score trend chart and summary stat cards.
4. Driver reviews the summary at a glance.
5. Driver navigates to another section via the bottom navigation bar.

### Postconditions
- No data is written; this is a read-only view.
- Driver has an overview of recent driving performance.

### Alternative Flows

**A1 — No session data exists yet:**
- Database queries return zero or empty results.
- Dashboard displays zero/placeholder values and an empty chart.
- A prompt is shown encouraging the driver to start their first session.

**A2 — Data is loading (shimmer state):**
- While queries are pending, shimmer skeleton placeholders are shown in place of stats and the chart.
- Skeletons are replaced by real data once queries complete.

---

## UC-03: Start Monitoring Session

**Actor:** Driver, System, Android OS  
**Trigger:** Driver taps the **Start** button on the Monitor screen.

### Preconditions
- App is in the foreground on the Monitor screen.
- No monitoring session is currently active.
- Device has a functioning rear-facing camera.

### Main Flow
1. Driver taps **Start**.
2. System checks if camera permission has been granted.
3. Camera permission is granted → System initializes the camera feed (front-facing/driver-facing, portrait-locked).
4. Android OS starts a foreground service and displays a persistent status-bar notification.
5. System creates a new session record in the SQLite `sessions` table.
6. System begins the inference loop (every 200 ms):
   a. Camera frame is captured and passed to ML Kit Face Detection.
   b. ML Kit extracts face landmarks: Eye Aspect Ratio (EAR), Mouth Aspect Ratio (MAR), yaw, pitch, and roll angles.
   c. Features are normalized using mean/scale values from `norm_params.json`.
   d. Normalized feature vector is passed to the DMS-HybridNet V3 TFLite model.
   e. Model outputs class probabilities for 13 behavior sub-classes grouped into three parent classes: NATURAL, DISTRACTED, DROWSY.
   f. System evaluates outputs against calibrated per-stage thresholds.
7. Real-time alertness indicator and detection labels update on screen.
8. Session is in progress; driver may interact with UC-04, UC-05, or UC-07.

### Postconditions
- A live session record exists in the database.
- The foreground service is running; monitoring continues even if the app is backgrounded.
- Camera feed and inference loop are active.

### Alternative Flows

**A1 — Camera permission not yet granted:**
- At step 2, permission is not granted.
- System shows a permission rationale dialog explaining why camera access is needed.
- Driver grants permission → flow continues from step 3.
- Driver denies permission → Start is aborted; a message is shown asking the driver to grant permission in device settings.

**A2 — No face detected in frame:**
- At step 6b, ML Kit finds no face in the frame.
- Inference is skipped for that cycle.
- System logs a "no face" event and displays a positioning guide overlay.
- Loop resumes on the next cycle.

**A3 — Auto-Start enabled (see UC-10):**
- Driver does not tap Start manually.
- System automatically triggers step 1 when the Monitor screen is first opened.

---

## UC-04: Detect and Escalate Alert

**Actor:** System, Android OS  
**Trigger:** Sustained drowsiness or distraction signal detected during an active session (extends UC-03).

### Preconditions
- A monitoring session is active (UC-03 is in progress).
- Detection confidence has exceeded the threshold for the required number of consecutive frames.

### Main Flow
1. System evaluates the current rolling detection buffer against three-stage thresholds:

   **Stage 1 — Level 1 Advisory Alert:**
   - distPct ≥ 40%, bestClass ≥ 25%, sustained for 6 consecutive frames.
   - No parent class confirmation required.
   - → Soft audio tone plays (L1 sound asset).
   - → Amber visual indicator is shown on the Monitor screen.
   - → Foreground service notification is updated to reflect alert state.

   **Stage 2 — Level 2 Warning Alert:**
   - distPct ≥ 22%, bestClass ≥ 12%, sustained for 12 consecutive frames.
   - Parent class confirmation (DISTRACTED or DROWSY) required.
   - → Moderate audio alert plays (L1/L2 sound asset).
   - → Orange visual indicator replaces the amber one.
   - → Alert event is logged to the SQLite `alert_events` table with timestamp, class, and confidence.
   - → Video clip recording is triggered (UC-06).

   **Stage 3 — Level 3 Critical Alert:**
   - distPct ≥ 15%, bestClass ≥ 8%, sustained for 22 consecutive frames.
   - Parent class + off-road gaze confirmation required.
   - → Loud critical audio alert plays (L3 sound asset).
   - → Red full-screen critical alert overlay is shown.
   - → Foreground service notification escalates to critical priority.
   - → Video clip recording is triggered (UC-06).
   - → Alert event saved to SQLite with full metadata.

2. System continues monitoring; alert level persists until driver behavior returns to normal.
3. When consecutive normal frames exceed the recovery threshold:
   - → Alert level resets to none.
   - → Audio stops.
   - → Visual indicators clear.
   - → Recovery event is logged.

### Postconditions
- Alert event records exist in the `alert_events` table.
- For Level 3 alerts, a video clip record exists in the `video_clips` table.
- Session state counts (`state_counts` table) are updated.

### Alternative Flows

**A1 — Alert fires but driver immediately recovers:**
- Behavior returns to NATURAL before escalating to the next level.
- System resets the frame counter without escalating.
- A low-severity log entry is written but no formal alert event is created.

**A2 — Level 3 alert fires but video recording fails:**
- Storage is full or write permission is unavailable.
- Alert event is still logged; clip path in the database is null.
- Driver is not shown an error during the critical alert overlay to avoid distraction.

**A3 — False positive suppressed (GroomingFP filter):**
- Grooming-class confidence is too close to second-best class confidence (noise).
- System suppresses the detection; no alert is raised.
- In debug builds, a suppression log entry is written.

---

## UC-05: Monitor via Picture-in-Picture (PiP)

**Actor:** Driver, Android OS  
**Trigger:** Driver taps the **PiP** button during an active monitoring session (extends UC-03).

### Preconditions
- A monitoring session is active.
- The Android device supports PiP mode (API 26+).

### Main Flow
1. Driver taps the PiP button on the Monitor screen.
2. App transitions to a floating mini-window overlay via Android PiP mode.
3. Camera feed continues rendering inside the PiP window.
4. Monitoring, inference loop, and alert logic continue uninterrupted.
5. Driver uses other apps or the home screen while monitoring remains active.
6. Driver taps the PiP window to return to the full Monitor screen.
7. Full Monitor screen is restored with the current session state intact.

### Postconditions
- Session remains active and uninterrupted through the PiP transition.
- All alert events and logs generated during PiP are saved normally.

### Alternative Flows

**A1 — Device does not support PiP:**
- PiP button is hidden or disabled.
- Driver cannot enter PiP mode; this flow does not apply.

**A2 — Driver dismisses the PiP window:**
- Driver swipes away the PiP window.
- App process moves to background but the foreground service keeps monitoring active.
- Session can be resumed by reopening the app.

---

## UC-06: Record Alert Video Clip

**Actor:** System  
**Trigger:** A Level 2 or Level 3 alert is raised during an active session (triggered by UC-04).

### Preconditions

- A Level 2 or Level 3 alert has been confirmed.
- Camera feed is active and writable.
- App-private storage is available.

### Main Flow
1. System captures a video segment from the camera buffer surrounding the alert event (pre-alert and post-alert window).
2. System encodes and saves the clip as an `.mp4` file to app-private storage.
3. System writes a record to the SQLite `video_clips` table:
   - Clip file path.
   - Duration in seconds.
   - Linked alert event ID and session ID.
   - Timestamp.
4. Clip becomes available for playback in the History screen (UC-08).

### Postconditions
- Video file exists in app-private storage.
- A corresponding record in `video_clips` is linked to the triggering alert event.

### Alternative Flows

**A1 — Storage write fails:**
- System logs the failure to the `system_logs` table.
- No clip record is written to `video_clips`.
- The alert event record is unaffected.

---

## UC-07: Stop Monitoring Session

**Actor:** Driver, System  
**Trigger:** Driver taps the **Stop** button on the Monitor screen, or exits PiP mode and stops the session.

### Preconditions
- A monitoring session is currently active.

### Main Flow
1. Driver taps **Stop**.
2. System halts the inference loop.
3. Camera feed is released.
4. Android OS stops the foreground service and removes the status-bar notification.
5. System finalizes the session record in SQLite:
   - Calculates and stores the safety score (penalized per alert per minute, with a 2-minute duration floor).
   - Records total session duration.
   - Saves final alert counts and alertness snapshots.
6. If "Show Session Summary" is enabled in Settings:
   - Summary dialog is displayed: total duration, safety score, alert level breakdown.
   - Driver taps **Done** or **View Details** to dismiss.
7. Monitor screen returns to idle (Start button visible).

### Postconditions
- Session record is complete and finalized in SQLite.
- Foreground service is stopped.
- Camera and inference resources are released.

### Alternative Flows

**A1 — Show Session Summary is disabled:**
- Step 6 is skipped.
- Monitor screen returns to idle immediately after session data is saved.

**A2 — Session is very short (< 2 minutes):**
- Safety score is calculated using a 2-minute floor to prevent inflated per-minute penalty rates.
- Session is still saved normally; a short-session indicator may appear in History.

---

## UC-08: View Session History & Video Clips

**Actor:** Driver  
**Trigger:** Driver taps **History** in the bottom navigation.

### Preconditions
- At least one session has been completed.
- App is in the foreground.

### Main Flow

**Sessions Tab:**
1. Driver taps the History tab.
2. System loads the list of past sessions from SQLite, sorted by most recent.
3. Each row displays: date, session duration, safety score, and total alert count.
4. Driver scrolls through the session list.
5. Driver taps a session row:
   - Session detail expands: alert timeline, per-class detection counts, alertness trend.
6. Driver applies filters:
   - **Date filter:** date-range picker to narrow sessions to a specific period.
   - **Alert-type filter:** filter by drowsiness alerts, distraction alerts, or all.
   - **Alert-level filter:** filter by minimum alert level (Level 1, Level 2, or any).
   - **Text search:** free-text field searches sessions by date string.
   - Filtered results update dynamically.
7. Driver taps **Clear** (visible only when filters are active) to reset all filters.

**Videos Tab:**
8. Driver switches to the Videos tab.
9. System loads the list of saved alert video clips from SQLite.
10. Each row displays: clip date/time, linked alert type, duration.
11. Driver may apply the same date and alert-type filters.
12. Driver taps a clip to select it (multi-select mode):
    - Tapping additional clips adds them to the selection.
    - A bottom action bar appears showing selected count and a **Download** button.
    - Driver taps **Download** → all selected clips are exported to the device's Downloads folder in one batch.
    - Export is locked (button disabled) while a batch download is already in progress.
    - Driver taps **Cancel** in the action bar to clear the selection.
13. Driver taps a clip row (not in multi-select) to open the in-app video player:
    - Driver can pause, seek, and dismiss.
14. Driver deletes a clip by tapping the delete button on the clip card, or by swiping the card:
    - A confirmation dialog is shown before permanent deletion.

### Postconditions
- No data is written; this is a read-only view.
- Driver has reviewed past session performance and/or alert footage.

### Alternative Flows

**A1 — No sessions exist:**
- Sessions tab displays an empty state message.
- Videos tab displays an empty state message.

**A2 — No clips match active filter:**
- Videos tab shows a filtered-empty state.
- Driver clears filters to see all clips.

**A3 — Video file is missing from storage:**

- Clip records are validated on load; any entry whose file no longer exists on device is automatically hidden from the list.
- The database record is retained but the clip does not appear in the UI.

**A4 — Export fails during batch download:**

- System surfaces a specific error message depending on the cause: disk full, permission denied, or file not found.
- Successfully exported clips in the same batch are unaffected; only the failed clip is reported.

---

## UC-09: View Analytics

**Actor:** Driver  
**Trigger:** Driver taps **Analytics** in the bottom navigation.

### Preconditions
- App is in the foreground.

### Main Flow
1. Driver taps the Analytics tab.
2. System queries SQLite for aggregated data:
   - Safety score trend over the selected time range.
   - Alert frequency breakdown (drowsiness vs. distraction counts per day).
   - Average alertness level over time.
   - Daily drive time totals.
3. Analytics screen renders:
   - A line/bar chart of safety scores over time.
   - An alert frequency breakdown chart.
   - Aggregate stat cards (totals and averages).
4. Driver adjusts the time range filter: **7 days**, **30 days**, or **All**.
   - Charts and stat cards update to reflect the selected range.
5. Driver taps a data point on a chart:
   - Drill-down view shows per-session detail for that day.

### Postconditions
- No data is written; this is a read-only view.
- Driver understands long-term driving behavior trends.

### Alternative Flows

**A1 — Insufficient data for selected range:**
- Chart renders with only available data points.
- If no data exists, an empty state is shown with a prompt to drive more sessions.

---

## UC-10: Configure Settings

**Actor:** Driver  
**Trigger:** Driver taps **Settings** in the bottom navigation.

### Preconditions
- App is in the foreground.
- No restriction on when settings can be accessed (accessible during and between sessions).

### Main Flow

**Alert Settings:**
1. Driver adjusts the **Alert Volume** slider:
   - System calls `VolumeController` to set the device media volume immediately.
   - Value is saved to `shared_preferences`.
2. Driver selects **Alert Sensitivity**: Low, Medium, or High:
   - Controls the number of consecutive detection frames required before an alert fires.
   - Value is saved to `shared_preferences`.

**Monitoring Settings:**
3. Driver toggles **Auto-Start Recording**:
   - When on, monitoring begins automatically as soon as the Monitor screen is opened.
   - Value is saved to `shared_preferences`.
4. Driver toggles **Show Session Summary**:
   - When on, a summary dialog is shown after each session ends (see UC-07 step 6).
   - Value is saved to `shared_preferences`.

**Data & Privacy:**
5. Driver selects **Session Retention**: 7 days, 30 days, or Forever:
   - System immediately deletes any sessions in SQLite older than the selected threshold.
   - Value is saved to `shared_preferences`; auto-deletion runs on subsequent app opens.
6. Driver taps **Clear All History**:
   - Confirmation dialog is shown: "This will permanently delete ALL session data."
   - Driver confirms → System calls `DatabaseHelper.clearAllData()`:
     - All rows in sessions, alert_events, state_counts, system_logs, alertness_snapshots, and video_clips are deleted.
   - Success snackbar is shown.

**About:**
7. Driver views app version, institution name, and authors list.
8. Driver taps an author name → browser opens to that author's GitHub profile.

### Postconditions
- All preference changes are persisted to `shared_preferences` immediately.
- Retention-triggered deletions are reflected in the History and Analytics screens.

### Alternative Flows

**A1 — Driver cancels Clear All History:**
- Driver taps **Cancel** in the confirmation dialog.
- No data is deleted; settings screen remains unchanged.

**A2 — Volume slider adjusted while session is active:**
- Volume change is applied in real-time; subsequent alerts will play at the new volume.
- There is no conflict with an active session.

**A3 — GitHub link fails to open:**
- Device has no browser installed or no internet connection.
- `canLaunchUrl` returns false; link tap is silently ignored.

---

*Document covers all 10 use cases for Bantay Drive v1.0.0.*
*Institution: New Era University*
