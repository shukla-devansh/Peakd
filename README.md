# Peakd

A strength-training tracker for iPhone and Apple Watch. Log sets by hand or by voice, rest with a
Live Activity timer, and get the next session planned from your own history: progressive overload,
a fatigue estimate, and progress charts.

College project for CSE 4456 by Saksham Sharma and Devansh Shukla. The code name is **Cadence**:
that's what the Xcode project, targets and folders are called; the app people see is Peakd.

## Features

- **Workout logging:** routines, a fast set table, a "Previous" column, rest timer with a Live
  Activity, Dynamic Island and a notification when rest is over.
- **Voice logging:** say "45 kilos for 8 reps", "same weight 10 reps" or "add 2.5 kilos 8 reps".
  On-device speech (SpeechAnalyzer) and a deterministic parser; nothing is saved until you confirm.
- **Next session planning:** double-progression overload ("Try 42.5 kg"), a 0–100 fatigue estimate
  with the factors behind it, and a rule-based planner. On Apple Intelligence devices the
  explanation text is reworded on device; the numbers always come from the engines.
- **Progress:** volume charts with table views, a training calendar, a body map of the muscles you
  trained, sets by muscle group, personal records and CSV export.
- **Exercise detail:** records, top-set chart, "Next time" suggestion and history.
- **Share cards:** Story, Square and transparent Sticker images of a workout.

## Requirements

- A Mac with Apple silicon and **Xcode 26.3 or later**
- The **iOS 26** and **watchOS 26** simulator runtimes (Xcode → Settings → Components). The iPhone
  app embeds the Watch app, so every scheme needs the watchOS runtime.
- To run on a device: iOS 26 or later. A free Apple ID works; see below.

## Getting started

```bash
git clone <this repo>
cd <repo folder>
open Cadence.xcodeproj
```

Pick the **Cadence** scheme and an iPhone simulator (the app was built on an iPhone 17 Pro
simulator), then press Run. Tests: Product → Test (⌘U), or

```bash
xcodebuild test -project Cadence.xcodeproj -scheme Cadence \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:CadenceTests
```

## Running on your own iPhone

Signing settings live in `Config/`. Your own team and bundle prefix go in a file that is not
committed:

1. Copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig`.
2. Set `DEVELOPMENT_TEAM` to your Team ID (Xcode → Settings → Accounts, or the "OU" of your
   Apple Development certificate) and `BUNDLE_ID_PREFIX` to something unique, e.g. `com.yourname`.
3. With a free Apple ID (Personal Team), keep
   `CADENCE_APP_ENTITLEMENTS = Config/Cadence-Personal.entitlements`: free teams can't sign Time
   Sensitive Notifications. Rest alerts still arrive, just not as time-sensitive.
4. Plug in the iPhone, unlock it, pick it as the run destination and press Run. The first time,
   allow it in **Settings → General → VPN & Device Management** and turn on **Developer Mode**.

Free Apple IDs can have only **3 sideloaded apps** on a phone at once, and the install expires after
**7 days** (run it from Xcode again to renew).

## Renaming the app

The name people see (Home Screen, permission prompts, share cards, exports, Watch) is one setting:
`APP_DISPLAY_NAME` in `Config/Branding.xcconfig` (currently `Peakd`). Internal names stay "Cadence"
so saved data keeps working.

## Project layout

```
Shared/          Code compiled into the iPhone app, Watch app and widget: models, design tokens,
                 formatters, Live Activity attributes
Cadence/         iPhone app: App, DesignSystem components, Features (one folder per screen group),
                 Engine (overload, fatigue, planner, stats), Services (speech, health, rest timer…)
CadenceWatch/    watchOS app
CadenceWidgets/  Rest-timer Live Activity
CadenceTests/    Unit tests (Swift Testing)
Config/          Info.plist partials, entitlements, xcconfig files
design/screens/  Design boards (HTML) for every screen
docs/            Design spec, project guide, next steps, original synopsis
```

## Documentation

- [docs/PROJECT_GUIDE.md](docs/PROJECT_GUIDE.md): stack, architecture, data model, engine rules and
  build order
- [docs/DESIGN_SPEC.md](docs/DESIGN_SPEC.md): every screen, its states and navigation
- [docs/NEXT_STEPS.md](docs/NEXT_STEPS.md): where the project stands and what to build next
