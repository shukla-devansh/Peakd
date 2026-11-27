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
5. Run the tests (⌘U). All 167 should pass.

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
| 9 | HealthKit + Apple Watch | Done |
| 10 | Polish | Done (Dynamic Type at AX3 skipped) |
| 11 | Sign-in | Skipped for now |

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

## 3. Phase 9: HealthKit + Apple Watch (done)

- **Health:** finished workouts are saved as Traditional Strength Training; the Summary gets
  average and peak heart rate and active energy (from Health, or the Watch's live samples);
  resting heart rate (last 28 days) feeds the fatigue score.
- **Watch app** (`CadenceWatch/`): Live workout (timer, heart rate, current set, Log set),
  Edit set (Digital Crown for weight and reps, Save set) and Rest (ring, next set, +15, Skip,
  haptic tap at zero). It mirrors the iPhone's workout; the iPhone stays in charge.
- **Sync** (`Shared/Watch/WatchMessages.swift`, `WatchSyncService`, `WatchConnector`): the iPhone
  sends the workout state as application context; the Watch sends logged sets (source `watch`),
  rest controls and heart rate. The Watch runs an `HKWorkoutSession` for live heart rate and
  discards its own workout, so only the iPhone's is saved to Health.
- **Live heart rate** shows next to the timer on the active workout.
- **Voice on the Watch:** the mic button next to Log set opens watchOS Dictation (apps can't use
  the speech framework on watchOS). The text goes through the same `VoiceSetParser` as the iPhone
  (now in `Shared/Voice/`), then opens Edit set prefilled; anything missing is marked "Needed" and
  set with the Crown. Nothing is saved until Save set. Hidden when Voice logging is off in Profile.

Still to check on real hardware: live heart rate and calories (the simulator has none), the
haptic at the end of rest, the workout appearing in the Health app after Finish, and Watch
dictation (say "45 kilos for 8", then "50 kilos" to see the Needed state).

To test in the simulator: pair an Apple Watch Series 11 (46 mm) simulator with the iPhone
simulator (Xcode → Window → Devices and Simulators), run the iPhone app, start a workout, and
open the Watch app.

## 4. Phase 10: Polish (done)

- App icon (iPhone default, dark and tinted, and Watch), drawn in code by `tools/make_icon.swift`.
- VoiceOver: the boards' group labels are in place ("Recent exercises", "All exercises",
  "Quick start" and the rest).
- Empty states on every list, Health and speech "unavailable" states.
- **Skipped on purpose:** the largest text sizes (AX1–AX3). At those sizes the side-by-side
  cards on Home and the set table on the active workout overflow. Fix later by stacking them
  vertically when `dynamicTypeSize.isAccessibilitySize` is true.

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
