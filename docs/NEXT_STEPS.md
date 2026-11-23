# Next steps

The app is called **Peakd**; the code name in Xcode is Cadence.

Where the project stands, how to pick it up on another Mac, and what is left to build.

## 1. Set up a new Mac

1. Install **Xcode 26.3 or later**. If your iPhone runs a newer iOS than your Xcode supports, update
   Xcode first; otherwise installs fail with "The developer disk image could not be mounted"
   (that error also appears when the phone is simply locked).
2. Xcode → Settings → Components: install the **iOS 26** and **watchOS 26** simulators.
3. Clone the repo and open `Cadence.xcodeproj`.
4. For your iPhone, create `Config/Local.xcconfig` from `Config/Local.xcconfig.example`
   (team ID, unique bundle prefix, personal entitlements on a free Apple ID). See the README.
5. Run the tests (⌘U). All 161 should pass.

Simulator data and the iPhone's data stay on those devices; nothing syncs (there's no account yet).

## 2. Where things stand

| Phase | What | State |
|---|---|---|
| 1 | Project skeleton, design system, models, exercise library | Done |
| 2 | Onboarding, Profile | Done |
| 3 | Routines, active workout, history, summary | Done |
| 4 | Rest timer, notification, Live Activity | Done |
| 5 | Overload, fatigue and planner engines | Done |
| 6 | Voice set logging | Done |
| 7 | On-device AI wording with rule-based fallback | Done |
| 8 | Progress, exercise detail, records, CSV, share cards, training calendar, body map | Done |
| 9 | HealthKit + Apple Watch | **Next** |
| 10 | Polish | To do |
| 11 | Sign-in | To do, last |

Also done: per-developer signing (`Config/Local.xcconfig`), one-setting app name
(`Config/Branding.xcconfig`), and workouts that are left open for 12 hours end themselves.

### Still to check on a real iPhone

These can't be tested in the simulator:

- **Voice logging:** say "45 kilos for 8 reps", "same weight 10 reps", "add 2.5 kilos 8 reps",
  "45 kilos" (should ask for reps). Play music at the same time: it should keep playing. The first
  use may download the speech model.
- **AI wording:** turn on Apple Intelligence, log 3 workouts, open Home → Edit plan. The "Why this
  plan" text should change from the template after a moment. Any number in it must match the
  exercise list.
- **Rest timer on the Lock Screen:** Live Activity, Dynamic Island, and the alert when rest ends.
- **Share:** share a Story to Instagram, put a Sticker on a photo.

## 3. Phase 9: HealthKit + Apple Watch

Goal (from the project guide): heart rate and energy in summaries, workouts saved to Apple Health,
resting heart rate in the fatigue score, and a 3-screen Watch app that logs sets and shows rest.

Already in place:

- `Cadence/Services/HealthService.swift`: authorization, with the read types (heart rate,
  resting heart rate, active energy) and share type (workouts).
- `Cadence/Services/WatchSyncService.swift`: `WCSession` activation and paired/installed state.
- `CadenceWatch/`: an empty Watch app target.
- `Workout` already has `avgHR`, `maxHR` and `activeEnergy`; the Summary shows heart-rate tiles when
  they're set.
- `FatigueEngine.report(..., restingHeartRate:)` already scores resting heart rate against a
  14-day baseline. It just isn't fed data yet.

To build:

1. **Save workouts to Health.** On Finish, build an `HKWorkout` (strength training) with
   `HKWorkoutBuilder` from the workout's start and end, and save it.
2. **Heart rate and energy for summaries.** Query heart-rate samples between start and end (average,
   max) and active energy (sum); store them on `Workout`; the Summary tiles appear by themselves.
3. **Resting heart rate.** Query the last 28 days of resting heart rate and pass it to
   `FatigueEngine.report` (see `CoachSnapshot` in `Cadence/Engine/TrainingHistory.swift`).
4. **Watch app** (design: `design/screens/Watch.dc.html`, 3 screens): current exercise and set
   with weight/reps and a Done button; the rest countdown; live heart rate. Run an
   `HKWorkoutSession` on the Watch for live heart rate.
5. **Sync with `WatchConnectivity`.** iPhone → Watch: current exercise, next set, rest end time.
   Watch → iPhone: a completed set (logged with source `watch`), skip rest. Use
   `sendMessage` when reachable and `transferUserInfo` otherwise.
6. **Live heart rate on Active and Summary** from the Watch.
7. Give the Watch target the HealthKit capability (an entitlements file like
   `Config/Cadence.entitlements`, referenced from the target's build settings).

Testing notes: the simulator has no real heart rate, so add sample data in the simulator's Health
app or test on a real Watch. Pair a Watch simulator with the iPhone simulator in Xcode → Window →
Devices and Simulators. HealthKit works on a free Apple ID.

## 4. Phase 10: Polish

- VoiceOver pass: use each board's `aria-label`s as the labels (see `docs/DESIGN_SPEC.md`).
- Dynamic Type: check every screen at the largest accessibility size (AX3).
- Empty and error states on every list; speech or Health unavailable.
- App icon.
- Reduce Motion respected everywhere (most animations already check it).

## 5. Phase 11: Sign-in (do this last)

The app has no accounts today: all data lives on the device. Options:

- **Sign in with Apple + iCloud (CloudKit) sync.** No server to run, and data follows the user to a
  new phone. Both capabilities need a **paid Apple Developer account** ($99/year); they can't be
  signed with a free Personal Team.
- **A custom backend** (for example Firebase Auth + Firestore). Works with any account type but adds
  a third-party package, a server bill, and privacy work.

Decide which one first. For a college project, Sign in with Apple + CloudKit is the cleanest if the
team has a paid account.

## 6. Handy facts

- App name: `APP_DISPLAY_NAME` in `Config/Branding.xcconfig` (now `Peakd`).
- Your signing: `Config/Local.xcconfig` (never committed).
- A free Apple ID allows 3 sideloaded apps on a phone, and installs expire after 7 days.
- The AI wording needs Apple Intelligence. The simulator uses the Mac's, so turn it on in the Mac's
  System Settings to see it in the simulator.
- Engine rules and the data model: `docs/PROJECT_GUIDE.md`.
