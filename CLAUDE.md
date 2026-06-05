# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What is this app?

SceneManager is a macOS app that connects to a self-hosted [deCONZ](https://github.com/dresden-elektronik/deconz-rest-plugin) gateway and provides a native interface for managing Zigbee lighting Groups and Scenes. Its core strength is applying pre-defined light states (Presets) to many Lights and Scenes simultaneously without disturbing the current state of any lights — useful for replicating identical states across Groups.

The app targets a custom fork of the deCONZ REST API that adds support for Hue manufacturer-specific endpoints (dynamic scenes, partial scene attributes, the `0xfc03` cluster): <https://github.com/hanskroner/deconz-rest-plugin/tree/hue-dynamic-scenes>

---

## Project Targets

| Target | Type | Description |
|---|---|---|
| **SceneManager** | macOS App | The main app: all SwiftUI UI, view-models, preset management |
| **deCONZ** | Swift Framework (embedded) | Networking layer: `RESTClient`, `RESTModel`, all domain model types |
| **deCONZTests** | XCTest bundle | Live integration tests against a real deCONZ gateway |
| **ColorTests** | XCTest bundle | Color conversion unit tests (`@testable import SceneManager`) |
| **SceneConverter** | macOS App (stub) | Standalone file-conversion tool for Hue CLIP v2 scene format — incomplete, independent of `deCONZ.framework` |

### Target boundaries

- **Working on UI, view-models, or presets?** Focus on `SceneManager/`. Domain model types live in `deCONZ/`.
- **Working on networking or the deCONZ REST API layer?** Focus on `deCONZ/`. Changes here affect `SceneManager` and all test targets.
- **SceneConverter** is a stub and should not be modified unless it is specifically the focus of the task.

Key source locations:
- `SceneManager/` — views, per-window view-models (`Sidebar`, `Lights`, `Presets`, `WindowItem`), preset file management (`PresetsModel`), color math (`Colors.swift`), custom UI components (`Picker/`, `Views/`)
- `deCONZ/` — `RESTClient` (actor), `RESTModel` (singleton facade), domain models (`Light`, `Group`, `Scene`, `LightState`, `DynamicState`), raw REST structs (`RESTModels/`)
- `SceneConverter/` — independent stub app

---

## Platform & Tooling

- **Platform:** macOS only. Do not suggest iOS-only APIs.
- **Minimum deployment target:** SceneManager — macOS 26.0; deCONZ framework — macOS 15.0
- **Language:** Swift 6, strict concurrency enabled on all targets
- **UI framework:** SwiftUI throughout. Use AppKit only where SwiftUI has no equivalent (e.g. `NSTextView`, `NSSearchField` wrappers already exist in `Views/`).
- **Observation:** `@Observable` macro everywhere — do **not** use `@StateObject`, `@ObservedObject`, or `ObservableObject`.

---

## Build & Test Commands

```bash
# Build the main app
xcodebuild build -project SceneManager.xcodeproj -scheme SceneManager

# Run color unit tests (no gateway required)
xcodebuild test -project SceneManager.xcodeproj -scheme ColorTests

# Run deCONZ integration tests (requires a live gateway)
DECONZ_API_KEY=<key> DECONZ_API_URL=<url> \
  xcodebuild test -project SceneManager.xcodeproj -scheme deCONZTests
```

The `deCONZTests` and `deCONZGroupCRUD` / `deCONZSceneCRUD` suites hit a real gateway — they are not unit tests and will fail without valid `DECONZ_API_KEY` / `DECONZ_API_URL` environment variables.

---

## Architecture

### Layers

```
┌─────────────────────────────────────────────────────┐
│  SceneManager (app target)                          │
│  Views ←→ per-window @Observable view-models        │
│           (Sidebar, Lights, Presets, WindowItem)    │
│  PresetsModel (@MainActor singleton) ─ file system  │
└──────────────────┬──────────────────────────────────┘
                   │  @import deCONZ
┌──────────────────▼──────────────────────────────────┐
│  deCONZ (framework target)                          │
│  RESTModel (@MainActor singleton, Combine signals)  │
│  RESTClient (actor, URLSession)                     │
│  Domain models: Light, Group, Scene, LightState     │
└─────────────────────────────────────────────────────┘
```

### Data flow for user actions

```
View → inline Task or WindowItem method
     → RESTModel.shared method
     → RESTClient (actor) → URLSession → deCONZ REST API
                                ↓
              RESTModel.onDataRefreshed.send()   (Combine PassthroughSubject)
                                ↓
              WindowItem.modelRefreshedSubscription
                                ↓
              rebuilds Sidebar / Lights lists in-place
```

### RESTModel (`@MainActor @Observable final class`, singleton)

The in-memory cache for all domain state: `[Int: Light]`, `[Int: Group]`, `[Int: [Int: Scene]]`. All mutations are on the main actor. `refreshCache()` fetches lights, groups, and scenes in sequence, builds domain objects, then fires `onDataRefreshed` — `isReload: true` clears window selection, `isReload: false` rebuilds lists in-place.

### RESTClient (`actor`)

All HTTP I/O Methods are `async throws`. Response validation decodes `[APIResponseContext]` and throws `APIError.apiError` if any errors appear. Every call logs a `RESTActivityEntry` (request + response bodies + outcome) into `RESTActivity`.

**Important deCONZ API quirks handled here:**
- `getSceneAttributes` normalizes the separate `x`/`y` keys deCONZ returns for CIE xy into an `"xy"` array as required for writes.
- `modifyHueScene` uses the manufacturer-specific `/hue-scenes/` endpoint (for Signify/Philips devices), which allows brightness-only scenes. Paths for this endpoint must **not** have a trailing slash — a trailing slash causes HTTP 431.

### Per-window view-models (SceneManager app)

Four `@MainActor @Observable` classes are `@State` on `ContentView` and injected via `.environment()`:

| Class | Holds |
|---|---|
| `WindowItem` | `groupId`, `sceneId`, JSON editor text for both tabs, warnings, Combine subscription to `RESTModel` |
| `Sidebar` | `items: [SidebarItem]` tree (groups → scenes), selection, scroll target |
| `Lights` | `items: [LightItem]`, multi-selection `Set<UUID>` |
| `Presets` | deep copy of `PresetsModel`'s groups for this window, Combine subscription |

`FocusedValues` exposes `\.activeWindow: WindowItem?` so menu bar commands (`deCONZCommandMenu`, `LightsCommandMenu`) can reach the frontmost window's model.

### Presets persistence (`PresetsModel`, `@MainActor` singleton)

Reads/writes JSON files from the app's sandboxed `~/Documents` directory. Subdirectories → named `PresetItemGroup`s; root-level files → "custom" group. On first launch, bundled preset files are copied from the app bundle as defaults. `PresetsModel.onPresetsUpdated` (Combine) notifies each window's `Presets` view-model to rebuild.

Each preset JSON has a top-level `"name"`, optional `"image"`, and either a `"state"` object (`PresetState`: single light state) or a `"dynamics"` object (`PresetDynamics`: color palette + speed).

### Domain models (`deCONZ` framework)

`Light`, `Group`, `Scene`, `LightState`, `DynamicState` are `@Observable final class`. UUIDs are derived deterministically via UUID v5 (SHA-1 of a namespace string + numeric id) — the same light/group always gets the same UUID across sessions, so SwiftUI selection state survives cache reloads without persisting IDs.

---

## Conventions

### Concurrency

- `RESTClient` is an `actor`; `RESTModel` and `PresetsModel` are `@MainActor`. Views use `Task { }` for fire-and-forget async calls.
- Do **not** introduce Combine for new work — existing Combine is confined to the `RESTModel → WindowItem` and `PresetsModel → Presets` bridges. All other reactivity uses `@Observable`.
- Do **not** use `DispatchQueue` or `OperationQueue` for new work.

### SwiftUI

- View state lives in the four per-window view-models or in local `@State` — no separate per-view view-model classes.
- Use `.task(id:)` rather than `.onAppear` for async work that should re-run when an input changes.
- `@SceneStorage` for per-window persistent UI state (e.g. inspector open/closed). `@AppStorage` for global preferences.
- Inline renaming (groups, scenes, presets) uses the shadow-name pattern: `isRenaming = true` saves the current name to `_shadowName`; `restoreName()` reverts on cancel.
- Custom `UTType` for drag-and-drop: `"com.hanskroner.scenemanager.preset-item"`. `PresetItem` conforms to `Transferable` via `CodableRepresentation`.

### Settings (UserDefaults)

- `@AppStorage("deconz_url")` — gateway URL
- `@AppStorage("deconz_key")` — API key
- Both are read by `RESTModel.reconnect()` to re-initialize `RESTClient`.

### Testing

- New tests use Swift Testing (`import Testing`, `@Test`, `#expect`, `#require`).
- `deCONZTests` suites are live integration tests — not mocked. Run them only against a real gateway.

---

## Things to Avoid

- Do not add third-party dependencies without discussion.
- Do not use `@StateObject`, `@ObservedObject`, or `ObservableObject` — the project uses the `@Observable` macro throughout.
- Do not hardcode the gateway URL or API key; they always come from `UserDefaults` via `@AppStorage`.
- Do not store images persistently — all artwork is in-memory only (light product images from `Assets.xcassets`; color picker rendering is computed on the fly).
- Do not conflate `SceneConverter` with `SceneManager` when scoping changes — they share no code.
- Do not add a trailing slash to `/hue-scenes/` endpoint paths — it triggers HTTP 431 from the deCONZ gateway.
