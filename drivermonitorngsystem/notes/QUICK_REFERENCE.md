<!-- # Quick Reference: Detection Threshold Changes

## What Changed?

| Aspect | Before | After | Why |
|--------|--------|-------|-----|
| **Distraction % Gate** | 65% | 70% | Reduce false positives from talking/head movement |
| **Per-Class Thresholds** | Scattered (was 30-75%) | Unified in `_kBehaviorClassThresholds` | Dataset-backed, cleaner code |
| **Body/Reaching (Class 6)** | Always uses direct score | Demoted if specific class nearby | Prevent catch-all false positives |
| **Drowsy Logic** | Unchanged | Unchanged + better thresholds | Already accurate, now with dataset justification |

---

## Key Threshold Values (%)

### Drowsy (Classes 9-12)
- **9 - Yawning**: 25% (MAR spike indicator)
- **10 - Yawning Occluded**: 30% (harder to detect)
- **11 - Fatigue/Head Droop**: 20% (gradual EAR trend)
- **12 - Microsleep**: 35% (PERCLOS 80%+, most critical)

### Distracted (Classes 2-8)
- **2 - Texting**: 50% (down/left gaze)
- **3 - Phone Call**: 35% (phone at ear)
- **4 - Radio**: 45% (quick right glance)
- **5 - Drinking**: 35% (hand-near-face)
- **6 - Body/Reach**: 70% (catch-all, highest)
- **7 - Grooming**: 55% (hand-to-face rapid)
- **8 - Smoking**: 30% (mouth + hand pattern)

### Neutral (Classes 0-1)
- **0 - Safe Driving**: No threshold (neutral)
- **1 - Talking**: 40% (used for neutral classification)

---

## Testing: 3-Phase Approach

### Phase 1: Drowsy (Accurate Before, Still Accurate Now)
```
Action: Yawn naturally 3-5 times
Expected: Detected within 3-5 frames
Debug Log: raw=drowsy → out=drowsy (after 3 frames)
```

### Phase 2: False Positives (MAIN FIX)
```
Action: Talk to passenger with head turns
Expected: NO distraction alert
Debug Log: distPct=60-65% but below 70% gate → neutral
```

### Phase 3: Real Distraction (Should Work Well)
```
Action: Pretend to text (look down/left, hand up)
Expected: Detects within 1 second (16 frames @ 15fps)
Debug Log: distracted=16/16 → outputs distracted
```

---

## Debug Log Cheat Sheet

```
[Debounce] drowsy=0/3 distracted=5/16 raw=neutral → out=neutral 
yaw=35.2 compensated=5.2 lookingAtRoad=true distPct=68.5 drowsyPct=2.1
```

- `drowsy=0/3` = 0 out of 3 frames needed for confirmation
- `distracted=5/16` = 5 out of 16 frames detected (not confirmed)
- `raw=neutral → out=neutral` = Raw state is neutral, final output is neutral
- `yaw=35.2` = Face yaw angle (±35° is side-looking)
- `compensated=5.2` = Yaw after -30° offset correction
- `lookingAtRoad=true` = Driver is in "safe" forward-looking zone
- `distPct=68.5 drowsyPct=2.1` = Class percentages (key insight!)

---

## Tuning: If Too Strict or Too Lenient

### Too Many False Positives (over-detecting distraction):
1. Raise `distractedPct >= 70.0` → try 72% or 75%
2. Raise specific class in `_kBehaviorClassThresholds` (e.g., class 2: 50% → 55%)
3. Raise `_kDistractedThreshold` (16 → 18 frames)

### Missing Real Distraction (under-detecting):
1. Lower `distractedPct >= 70.0` → try 68% or 65%
2. Lower specific class thresholds (e.g., class 3: 35% → 30%)
3. Lower `_kDistractedThreshold` (16 → 14 frames)

### Missing Real Drowsiness (rare, but check):
1. Lower `drowsyPct >= 40.0` → try 35%
2. Lower drowsy class thresholds (class 11: 20% → 18%)
3. Lower `_kDrowsyThreshold` (3 → 2 frames)

---

## Files Modified

- **`tflite_service.dart`**: Core detection logic updated
- **`DETECTION_THRESHOLDS.md`**: Full documentation (dataset source, reasoning)
- **`TESTING_GUIDE.md`**: How to test and what to expect
- **`QUICK_REFERENCE.md`**: This file

---

## Code Location (tflite_service.dart)

### New Constants
```dart
const Map<int, double> _kBehaviorClassThresholds = { ... }  // Line ~78
const int _kDistractedThreshold = 16;                       // Unchanged, still 16
const int _kDrowsyThreshold = 3;                            // Unchanged, still 3
```

### Updated Method
```dart
InferenceResult _buildResult(...)  // Line ~525, completely updated logic
```

---

## Next Steps

1. **Build & test** locally: `flutter run --release`
2. **Run 3-phase tests** from TESTING_GUIDE.md
3. **Monitor debug logs** for the metrics
4. **Collect 10+ test sessions** and track accuracy
5. **Adjust thresholds** based on real-world performance

---

## Contact Points for Adjustment

If you need to tweak:

**Drowsy Detection**: Lines 557-566 in `_buildResult()`
```dart
if (drowsyPct >= 40.0 && bestDrowsyScore >= 20.0 && ...)
```

**Distracted Detection**: Lines 567-582 in `_buildResult()`
```dart
else if (distractedPct >= 70.0 &&  // ← Main gate, change here
    bestDistScore >= effectiveDistClassThreshold && ...)
```

**Per-Class Minimums**: Lines ~78-92 in constants
```dart
const Map<int, double> _kBehaviorClassThresholds = { ... }
```

---

## Questions?

Refer to:
- **`DETECTION_THRESHOLDS.md`** — Dataset source & detailed reasoning
- **`TESTING_GUIDE.md`** — Specific test procedures & troubleshooting
- **Debug logs** — Real-time percentages during testing

The thresholds are **100% dataset-backed** from:
- MRL Eye, YawDD, UTA-RLDD (drowsy)
- State Farm (distracted) -->
