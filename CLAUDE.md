# Cadence — AI Workout Tracker (iOS + watchOS)

College project (CSE 4456, Saksham Sharma & Devansh Shukla). Build a native iOS app with an Apple Watch companion that logs strength workouts manually or by voice, then uses workout history to suggest the next session, progressive overload and a fatigue estimate.

The design is final. Build what the design shows; don't redesign it.

## Read first
1. `docs/DESIGN_SPEC.md` — every screen, its states, navigation and behaviour. This is the source of truth.
2. `design/screens/*.dc.html` — the exact visual reference for each screen (HTML with inline styles). Read the markup for spacing, sizes, copy and colours. Ignore the `<script>`/`sc-for` mechanics; the arrays inside `renderVals()` are sample data.
3. `Shared/DesignSystem/Theme.swift` — design tokens. Use them; never put raw hex values in views.
4. `docs/synopsis.pdf` — the original academic spec (features §3.1–3.8).
5. `docs/NEXT_STEPS.md` — current status (phases 1–10 done; phase 11 sign-in skipped for now). Start here.

## Stack (decided)
- Xcode 26.3+ (built and tested on 26.3), Swift 6 (strict concurrency), SwiftUI only, no UIKit unless unavoidable.
- **Deployment target: iOS 26.0 / watchOS 26.0.** It's needed for SpeechAnalyzer and the Foundation Models framework.
- Persistence: SwiftData (`@Model`), with a shared App Group container so the Watch and widgets can read it.
- State: `@Observable` view models, `@MainActor` where they touch UI.
- Charts: Swift Charts. Every chart gets an accessibility label and a "View as table" fallback (see ProgressTable).
- Voice: `Speech` → `SpeechAnalyzer` + `SpeechTranscriber` (on-device). Parse text into a set with a deterministic parser (`VoiceSetParser`), not an LLM.
- AI: `FoundationModels` (`LanguageModelSession`, `@Generable` structs) for next-session planning and the explanation text. **It must work without it:** Foundation Models needs an Apple Intelligence device. When `SystemLanguageModel.default.availability != .available`, fall back to the rule-based planner and template text.
- Progressive overload and the fatigue score are **deterministic Swift code**, not LLM output. The LLM may only explain or rank; numbers come from the engine.
- HealthKit: heart rate, active energy, save `HKWorkout`. Read and write only what's listed.
- Watch: watchOS app + `WatchConnectivity` (send set logs and timer state both ways); `HKWorkoutSession` on the Watch for live heart rate.
- Rest timer: `ActivityKit` Live Activity + Dynamic Island, and a time-sensitive `UNUserNotification` at zero.
- No third-party packages unless a phase below says so. No backend, no accounts (sign-in is planned as a final phase 11; see docs/NEXT_STEPS.md).

## Architecture
```
Shared/                   Compiled into the iOS app, Watch app AND widget (one synchronized folder, 3 targets)
  DesignSystem/           Theme.swift (tokens)
  Models/                 SwiftData models, enums, CadenceStore (container)
  Formatting/             WeightFormatter (all weight display/parsing)
  LiveActivity/           RestTimerAttributes (#if os(iOS))
  AppGroup.swift
Cadence/                  iOS app target
  App/                    CadenceApp, RootView (TabView), AppState
  DesignSystem/           Components/*.swift (iOS only)
  Features/
    Onboarding/ Home/ Workout/ ActiveWorkout/ Voice/ Rest/
    Summary/ Plan/ Fatigue/ Progress/ History/ Exercises/ Profile/
  Engine/                 OverloadEngine, FatigueEngine, Planner (rule-based), AIPlanner (FoundationModels)
  Services/               SpeechService, HealthService, WatchSyncService, RestTimerService, NotificationService
  Resources/              ExerciseLibrary.json (seed ~120 exercises)
CadenceWatch/             watchOS app (3 screens on the Watch board)
CadenceWidgets/           Live Activity for the rest timer
CadenceTests/             Engine + parser unit tests (Swift Testing)
Config/                   Info.plist partials + entitlements (referenced by build settings)
```

### Project notes
- The Xcode project uses synchronized folders: add files on disk and they join the folder's target(s). Code needed by the Watch or widget goes in `Shared/`.
- Bundle IDs and the App Group all derive from the `BUNDLE_ID_PREFIX` build setting (project level). For a device, set your Team and change that one setting.
- The progress screen type is `ProgressOverviewView` (not `ProgressView`, which would shadow SwiftUI's).
- Building any scheme needs the watchOS simulator runtime installed (the iOS app embeds the Watch app).
- Deleting SwiftData models: a child view holding a model redraws on its own after the delete and traps when it reads it (`isDeleted` is false again after save). Pass plain values to child views where you can; otherwise check `model.isGone` (in CadenceStore.swift) before reading.
- SwiftData autosave can lag by seconds: call `context.save()` after user edits.

## Data model (SwiftData)
- `UserProfile`: goal, experience, daysPerWeek, equipment [String], unit (kg/lb), defaultRestSeconds, toggles (restAlerts, voiceLogging, aiSuggestions)
- `Exercise`: name, primaryMuscle, secondaryMuscles, equipment, trackingType (weightReps/repsOnly/time), defaultRestSeconds, isCustom, aliases [String] (voice matching)
- `Routine` → ordered `RoutineItem` (exercise, targetSets, repRangeLow/High, restSeconds, order)
- `Workout`: start, end, routineName, notes, avgHR, maxHR, activeEnergy → `WorkoutExercise` (order) → `SetLog` (index, weight, reps, isCompleted, completedAt, source: manual/voice/watch, rpe?)
- `PersonalRecord`: exercise, kind (heaviest/bestSet/est1RM), value, date
- Store weights in kg internally; convert at display.

## Engine rules (implement exactly, unit-test each)
- **Est. 1RM:** Epley, `w × (1 + reps/30)`.
- **Volume:** Σ weight × reps of completed sets.
- **Progressive overload (double progression):** if every working set last session hit the top of the rep range, suggest +2.5 kg (barbell/machine) or +1 kg per dumbbell, otherwise the same weight and aim for +1 rep. If 2 sessions in a row miss the bottom of the range, suggest −5 to 10%. Only the engine produces numbers; the UI shows the reason ("Hit 10 reps on every set").
- **Fatigue score 0–100** (a fitness estimate, not medical): weighted blend of acute:chronic load ratio (7-day vs 28-day volume), sessions in the last 7 days vs the user's plan, % of sets below target reps, days since the last rest day, and resting HR vs a 14-day baseline when HealthKit has it. Bands: Low 0–39, Moderate 40–69, High 70–100. Show "Not enough data" until 3 workouts. Expose each factor's contribution (Fatigue screen "What is driving it").
- **Planner:** pick the routine or muscle groups least recently trained, filtered by available equipment; apply overload per exercise; at High fatigue cut one set per exercise and offer a rest day.

## Voice grammar (VoiceSetParser)
Must handle: "45 kilos for 8 reps", "45 for 8", "forty five kg eight reps", "same weight 10 reps", "add 2.5 kilos 8 reps", "8 reps" (weight from the current row), "bodyweight 12", lb variants. Number words → digits, including "and a half" and "point five". If reps or weight are missing, show the VoiceRetry state (ask only for the missing field). Never auto-save: the user confirms (Voice screen → Save set). 30+ unit tests.

## Design rules that are easy to get wrong
- Dark only: `.preferredColorScheme(.dark)` at the root.
- Main navigation is a native `TabView` (Home, Workout, Exercises, Progress, Profile). The boards draw a custom bar for mockup purposes; use the system one, which gets the iOS 26+ Liquid Glass styling.
- Touch targets ≥ 44 × 44 pt. Every swipe action also has a visible button. Reorder uses Move up / Move down buttons (RoutineEditor), not drag only.
- Status = colour + icon or word, never colour alone (done set = green + check, PR = gold + trophy, fatigue = colour + "Moderate").
- Dynamic Type everywhere (`Font.cad*` tokens); test at AX3. Numbers use `.monospacedDigit()`.
- Motion 150–300 ms ease-out; check `@Environment(\.accessibilityReduceMotion)`.
- Fatigue screen always shows the "not medical advice" footnote.
- Copy is in the boards. Reuse it verbatim.

## Build order (one phase per session; commit after each; run in the simulator)
1. **Skeleton:** Xcode project (iOS + watchOS + widget targets, App Group), Theme, all Components with `#Preview`s, TabView shell, SwiftData models, exercise seed JSON.
2. **Onboarding + Profile:** screens 11–14 and 23, persisting `UserProfile`.
3. **Logging core:** Start, RoutineEditor, Active workout, AddExercise, CustomExercise, Summary, History, with manual set logging end to end.
4. **Rest timer:** RestTimerService, RestTimer screen, notification, Live Activity (LockScreen board).
5. **Engines:** Overload, Fatigue, rule-based Planner + tests. Wire into Active ("Try 42.5 kg"), NextSession, Fatigue, Home cards.
6. **Voice:** SpeechService (SpeechAnalyzer), VoiceSetParser + tests, Voice and VoiceRetry sheets.
7. **AI layer:** AIPlanner on FoundationModels with `@Generable` output, falling back to the rule-based planner. Wording only, no invented numbers.
8. **Progress + Exercise detail:** Swift Charts, PRs, data table fallback, CSV export.
9. **HealthKit + Watch:** HealthService, watchOS app (3 screens), WatchConnectivity sync, live HR on Active and Summary.
10. **Polish:** accessibility pass (VoiceOver labels from the boards' aria-labels), Dynamic Type, empty states, error states, app icon.

At the end of each phase, list what the user should test manually on the simulator and on a device.

## Skills
Install the UI UX Pro Max skill for UI review passes:
```
/plugin marketplace add nextlevelbuilder/ui-ux-pro-max-skill
/plugin install ui-ux-pro-max@ui-ux-pro-max-skill
```
Use it with `--stack swiftui` when building or reviewing screens. The design tokens in this repo override any palette it suggests.
