# Bantay Drive — Thesis Defense Q&A

Likely panel questions grouped by topic, with prepared answers.

---

## 1. Camera Setup & Mounting

**Q: Why is the phone mounted at the side (35°) instead of front-facing?**

> Side-mount is more practical in real vehicles — dashboard space is occupied by instrument clusters and the steering wheel. The 35° yaw offset in the model compensates so that normal straight-ahead driving reads as ~0°. The trade-off is reduced drowsiness accuracy (EAR harder to read from the side), which is a documented limitation.

---

**Q: What if the user mounts the phone at a different angle?**

> The ±25° yaw gate gives headroom for roughly ±10° variation around the assumed 35° mount. Beyond that, detection degrades. This is a design constraint — the app assumes a consistent right-side mount, which is stated in the setup guide.

---

## 2. Model & Detection Logic

**Q: Why does your EAR formula look different from the standard 6-point formula?**

> The standard Soukupova & Čech (2016) EAR requires 6 eye landmarks. ML Kit exposes only 2 landmark points plus an eye-open probability. The formula `EAR = probability × 0.35 + 0.05` maps that 0–1 probability to an equivalent EAR scale (0.05 = closed → 0.40 = wide open), making it compatible with existing drowsiness literature thresholds.

---

**Q: Why three stages for distraction but only one for drowsiness?**

> Distraction signal strength varies widely by behavior — phone use hits 40–56% model confidence while mild radio-reaching hits only 15–22%. A single gate would either miss subtle distractions or flood with false positives. Drowsiness is more uniform across sub-classes (yawning, fatigue, microsleep), so one gate calibrated to the observed output range (18%) is sufficient.

---

**Q: How did you arrive at those specific threshold values?**

> Through logged session data. We recorded actual model output percentages during safe driving and during deliberate distracted/drowsy behavior, then set gates above the observed noise floor. For example, grooming noise peaks at ~27% from the side-mount angle, so the threshold was raised to 35% to sit above the noise while still catching real grooming at 40–97%.

---

**Q: Why is there a separate grooming dominance check?**

> At the 35° side-mount angle, glasses and hair partially occlude the face, creating a visual signature similar to a hand near the face — the same pattern the model associates with grooming. Real grooming dominates 60–100% with other classes below 10%. Noise grooming barely leads a crowded field. The check demotes grooming to neutral if the second-best class is within 20% of it.

---

## 3. Drowsiness vs. Distraction Detection

**Q: Why does distraction detect more readily than drowsiness?**

> Three reasons:
> 1. **Visual distinctiveness** — distracted behaviors (phone, looking away, grooming) produce large, unambiguous visual changes. Drowsiness is a gradual physiological state — a 10–20% EAR reduction over seconds — subtle even for human observers.
> 2. **Camera geometry** — at 35° side-mount, lateral head movements are clearly visible. Eye closure is harder to resolve from this angle; a front-facing camera is the ideal setup for EAR-based drowsiness.
> 3. **Signal strength** — distracted probability reaches 35–56% for clear behaviors; the drowsiness gate was deliberately kept low (18%) because the drowsy signal peaks lower. Weaker signal means more susceptibility to noise.
>
> This trade-off is well-documented in DMS literature — drowsiness detection consistently achieves lower accuracy than distraction detection in naturalistic settings, particularly with off-axis cameras.

---

## 4. Alert Levels

**Q: How are the 3 alert levels different from each other? Why 3?**

> - **Level 1** — early warning: banner notification + sound. Driver can self-correct.
> - **Level 2** — sustained warning: persistent banner, same sound. Behavior has continued.
> - **Level 3** — critical: full-screen red overlay with looping alarm. Requires manual dismissal.
>
> Three levels match real-world escalation: inform → warn → intervene. Too few levels would either alarm too early (distressing safe drivers) or too late (missing dangerous states).

---

**Q: Can alert levels go back down (downgrade)?**

> Level 1 and Level 2 clear automatically once the consecutive frame counter drops below the Level 1 threshold — meaning the driver has genuinely recovered for several frames in a row. Level 3 requires manual dismissal. This is intentional: a driver who reached microsleep severity should not have the critical alarm disappear on its own.

---

**Q: What is the detection latency — how quickly does the app respond?**

> At medium sensitivity: ~1.4 seconds from the first drowsy frame to a Level 1 alert (4 frames for model confirmation + 3 monitor frames × 200 ms each). Level 3 requires ~2.4 seconds of sustained drowsiness. This is within or faster than most reviewed DMS literature, which targets a 2–5 second response window.

---

## 5. Safety Score

**Q: How is the safety score computed?**

> `Score = 100 − (total_penalty / duration_minutes × 10)`
>
> Alert penalties: L1 = 2 pts, L2 = 4 pts, L3 = 8 pts (doubling per level). Dividing by drive duration converts it to a rate so a longer drive is not unfairly penalized. The ×10 factor scales it so a typical session with a few minor alerts stays above 90.

---

**Q: Why are drowsy and distracted alerts penalized equally?**

> In the current version they are equal. A valid critique — drowsiness poses a statistically higher crash risk than momentary distraction. Applying a type-specific weight multiplier is identified as a future improvement.

---

**Q: How was the normalization factor of 10 chosen?**

> It was empirically set so that a moderate session (e.g., 2–3 Level 1 alerts in a 10-minute drive) produces a score in the 90–95 range, which felt representative of "mostly safe" driving during testing. A formal derivation from crash-risk literature would strengthen this — also identified as future work.

---

## 6. System Performance & Limitations

**Q: Does it work with glasses or face masks?**

> Glasses can partially occlude eye landmarks, reducing EAR reliability. Face masks affect MAR (yawn detection). These are known limitations — the system performs best with a clear view of the eyes and mouth, consistent with ML Kit's published requirements.

---

**Q: What happens if the driver's face is not detected?**

> The temporal buffer receives no new face feature data; the model continues running on stale buffer values. The head pose service reports `hasFace = false`, which disables the yaw-based distraction gate. A "face not detected" alert is identified as a future improvement.

---

**Q: Did you test on multiple drivers?**

> Testing was conducted on [N] subjects under [conditions — fill in your actual data]. Generalizability to diverse demographics — different facial structures, skin tones, age groups — is a future study direction. This is standard scope for embedded DMS prototypes at the undergraduate level.

---

**Q: Why only 5 FPS for inference? Is that fast enough?**

> TFLite inference takes ~50–100 ms per frame on mid-range Android hardware. Running at 200 ms intervals (5 FPS) keeps the CPU free for the camera preview and UI without thermal throttling. The 4-frame confirmation window at 5 FPS (0.8 s) is well within the safety-critical response requirement. Higher frame rates would increase battery drain without meaningfully improving detection, since drowsiness and distraction both evolve over seconds.

---

## 7. Architecture Choices

**Q: Why Flutter instead of a native Android app?**

> Flutter provides cross-platform reach (Android + iOS) from a single codebase, which maximizes potential deployment. TFLite and ML Kit both have stable Flutter plugins. The trade-off is slightly higher inference overhead versus native Java/Kotlin, mitigated by running inference asynchronously at 5 FPS.

---

**Q: Why use both TFLite and ML Kit? Why not one or the other?**

> TFLite runs our custom-trained behavior classification model (DMS-HybridNet V3) which outputs all 13 behavior classes. ML Kit provides well-maintained, production-grade face landmark detection (EAR, MAR, head pose) without needing to train a separate landmark model from scratch. Each handles what it is best at — separation of concerns.

---

**Q: Why SQLite for storage? Why not cloud sync?**

> The system is fully offline by design — no internet required during driving. SQLite is embedded, zero-configuration, and sufficient for per-device trip history. Cloud sync is a future extension; the local-first approach protects user privacy by default.

---

## 8. Specific Values Panel May Question

| Value | Where Used | Justification |
|---|---|---|
| 35° yaw offset | Side-mount compensation | Midpoint of 30–45° assumed mount range |
| 18% drowsy gate | Drowsiness detection | Observed real output range from sessions |
| 40% / 22% / 15% distracted gates | 3-stage detection | Calibrated from session 109 logged data |
| 35% grooming threshold | False positive suppression | Noise peaks ~27%, real signal peaks 40%+ |
| 4 frames to confirm drowsy | TFLite debounce | 800 ms minimum — reduces noise without delaying safety alert |
| 30-frame temporal buffer | Model input | ~6 s of history at 5 FPS; captures EAR trend slope |
| 5-second snapshot interval | Alertness logging | Balances storage use with time-series resolution |
| L1=2, L2=4, L3=8 penalty | Safety score | Doubling per level; empirically scaled |
| Normalization factor 10 | Safety score formula | Empirical — produces intuitive 0–100 scale from test sessions |

---

## 9. Strong Points to Emphasize

- All inference runs **on-device** — no latency from network, no privacy concerns
- Thresholds were **calibrated to real session data**, not guessed
- The **3-stage distraction** system accounts for the actual signal range from a side-mount angle — previous single-gate designs failed because the gates were unreachable
- Alert levels use **temporal accumulation** (consecutive frames), not instantaneous detection — this reduces false positives significantly
- The safety score is **rate-based** (per minute), not count-based — fair across different trip lengths

---

*Generated for Bantay Drive thesis defense preparation — New Era University 2026*
