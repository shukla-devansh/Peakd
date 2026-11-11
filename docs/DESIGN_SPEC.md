# Cadence — Design Spec (screen inventory)

Visual source: `design/screens/<Board>.dc.html` (390 × 844 pt iPhone frames; Watch board 198 × 242 pt screens).

## Navigation map
```
Launch → (no profile) Onboarding → Equipment → Permissions → HomeEmpty
       → (profile)    Home

TabView: Home | Workout(Start) | Exercises | Progress | Profile

Home ─ Start workout → Active
     ─ Edit plan → NextSession / RoutineEditor
     ─ Fatigue card → Fatigue
     ─ See all → History → row → Summary (read-only for past workouts)
     ─ avatar → Profile
Start ─ Start empty / routine card → Active
      ─ Suggested → NextSession
      ─ New / routine ⋯ → RoutineEditor → Add exercise → AddExercise sheet
Active ─ Minimize → Home (workout keeps running; show a mini bar above the TabView)
       ─ Rest time → RestTimer (full sheet)
       ─ Mic → Voice sheet → Save | incomplete → VoiceRetry
       ─ Add exercise → AddExercise sheet → New → CustomExercise
       ─ Finish → Summary → Plan next session → NextSession → Start this workout → Active
Progress ─ View as table → ProgressTable
Exercises ─ row → ExerciseDetail; + → CustomExercise
```

## Screens

| # | Board file | SwiftUI view | Synopsis § | Must-have states |
|---|---|---|---|---|
| 00 | Main | (tokens → Theme.swift) | — | — |
| W | Watch | `WatchLiveView`, `WatchEditSetView`, `WatchRestView` | 3.7 | live, edit set (Digital Crown), rest; haptic at rest end |
| 01 | Home | `HomeView` | 3.3, 3.5 | suggested workout card, fatigue ring, week dots, recent list; workout-in-progress mini bar |
| 14 | HomeEmpty | `HomeView` (empty) | — | starter plan, fatigue "Not enough data" (0/3), empty recent |
| 02 | Start | `StartWorkoutView` | 3.1 | quick start, AI suggestion row, routines grid |
| 15 | RoutineEditor | `RoutineEditorView` | 3.1 | name field, ordered list with Move up/down/Remove, add exercise, delete routine (confirm) |
| 03 | Active | `ActiveWorkoutView` | 3.1, 3.4, 3.8 | rest bar, exercise card with set table (done / active / pending rows), AI overload chip, Add set, next exercise, bottom bar (mic, Add exercise, Cancel → confirm) |
| 16 | AddExercise | `AddExerciseSheet` | 3.3 | search, "Suggested next" with reasons, multi-select, CTA disabled at 0 |
| 17 | RestTimer | `RestTimerView` | 3.8 | ring countdown, ±15 s, Skip, Up next card, per-exercise rest, sound/haptic toggle |
| 18 | LockScreen | Live Activity + notification | 3.8 | Dynamic Island compact/expanded, lock-screen activity, "Rest over" notification |
| 04 | Voice | `VoiceLogSheet` | 3.2 | listening waveform, transcript, parsed weight/reps/set tiles (tap to edit), delta vs last time, Retry, Save |
| 19 | VoiceRetry | `VoiceLogSheet` (partial) | 3.2 | missing field flagged (warning colour + icon + "Needed"), quick-pick reps, Say again, Save disabled until complete |
| 05 | Summary | `WorkoutSummaryView` | 3.6 | 6 stat tiles (HR/energy only with Watch/Health, otherwise hide), PR card, volume by exercise bars |
| 06 | NextSession | `NextSessionView` | 3.3, 3.4 | "Why this plan" text, exercise list with weight + tag (+2.5 kg / Same), Save routine, Start |
| 07 | Fatigue | `FatigueView` | 3.5 | score ring + band, factor list with status chips, 14-day line, suggestion + action, medical disclaimer |
| 08 | Progress | `ProgressView` | 3.6 | range segmented control, 3 tiles, weekly volume line chart, sets by muscle bars |
| 20 | ProgressTable | `ProgressTableView` | 3.6 | accessible tables mirroring both charts, Export CSV |
| 21 | History | `HistoryView` | 3.1 | routine filter chips, month sections with totals, PR badges, row ⋯ menu (Delete, Repeat workout) |
| 09 | Exercises | `ExerciseLibraryView` | — | search, muscle filter chips, recent, A–Z |
| 10 | ExerciseDetail | `ExerciseDetailView` | 3.4 | records tiles, top-set chart, "Next time" overload card, history |
| 22 | CustomExercise | `CustomExerciseView` | — | name (also used as a voice alias), muscle, tracking type, equipment, secondary muscles, rest, notes |
| 11 | Onboarding | `OnboardingGoalView` | 3.3 | goal radio cards, experience segmented control, days/week |
| 12 | Equipment | `OnboardingEquipmentView` | 3.3 | equipment checkboxes, unit kg/lb, default rest stepper (30 s–5 min, 15 s steps) |
| 13 | Permissions | `OnboardingPermissionsView` | 3.2, 3.7, 3.8 | Mic+Speech, Health, Notifications, Watch; each optional, "On" state after grant |
| 23 | Profile | `ProfileView` | 3.8 | grouped Form: training, rest timer, voice and AI toggles, Apple Health and Watch, export, delete all (confirm) |

## Behaviour specs
- **Set row states:** done = success tint background + green check; active = elevated bg + accent border; pending = transparent with grey outline box. Tapping the check completes the set, starts the rest timer, light haptic.
- **Previous column:** last session's same set index ("40 × 10"); "–" if none.
- **Rest timer:** starts on set completion with the exercise's rest (falls back to the profile default). It survives backgrounding: use an end `Date`, not a counting Timer. At zero: notification (if allowed) + haptic + Watch tap; the Live Activity flips to "Rest over".
- **Minimised workout:** the workout continues; show a mini bar ("Push day · 42:18 · Rest 1:12") above the TabView that reopens Active.
- **Cancel workout:** confirmation dialog; destructive.
- **AI chips** (sparkle icon, accent tint) mark every suggestion. The user can always edit before accepting.
- **Records:** detect on set save (heaviest, best set by est. 1RM, est. 1RM); gold trophy chip; show them in Summary.
- **Units:** all display goes through one formatter; kg ↔ lb uses 2.20462, rounded to 0.5 lb / 0.25 kg.
- **Empty and error states:** every list has an empty state like HomeEmpty's dashed card. Speech unavailable → hide the mic and show "Voice logging needs microphone access" in Profile. Foundation Models unavailable → hide nothing; use the rule-based text.

## Accessibility
Every board's `aria-label`s are the VoiceOver labels to use (`.accessibilityLabel`). Charts: `.accessibilityChartDescriptor` or a summary label like on the boards. Group stat tiles with `.accessibilityElement(children: .combine)`.
