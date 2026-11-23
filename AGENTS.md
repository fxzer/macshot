# macshot

Native macOS screenshot & annotation tool inspired by Flameshot. Built with Swift + AppKit. No Qt, no Electron.

## Project Setup

- **Language:** Swift 5.0
- **UI:** AppKit (all windows created in code, storyboard is minimal — just app entry + main menu)
- **Min Target:** macOS 12.3+ (Monterey)
- **Bundle ID:** com.fxzer.macshot.macshot
- **Sandbox:** Enabled (entitlements: network.client, files.user-selected.read-write, files.bookmarks.app-scope)
- **LSUIElement:** YES (menu bar only app, no dock icon — switches to `.regular` when editor windows are open)
- **Permissions:** Screen Recording (Info.plist has Privacy - Screen Capture Usage Description)
- **Xcode:** File system synchronized groups — just create .swift files in `macshot/` and Xcode picks them up automatically

## Architecture

Menu bar agent app. No main window. Global hotkey (Cmd+Shift+X) or menu bar click triggers screen capture → fullscreen overlay → selection → annotation → output.

> Need the full source directory tree, `UserDefaults` key inventory, or complete feature list? Read [docs/architecture.md](docs/architecture.md).

### Component Overview

#### AppDelegate — Entry Point & Orchestrator
- NSStatusItem in menu bar with "Capture Screen", "Recent Captures", "Preferences...", "Quit"
- Registers global hotkey via HotkeyManager
- On trigger: ScreenCaptureManager captures all screens → creates one OverlayWindowController per screen
- Implements `OverlayWindowControllerDelegate` — handles confirm, cancel, pin, OCR, scroll capture, upload, delay
- Manages: `overlayControllers[]`, `thumbnailControllers[]`, `pinControllers[]`, `ocrController`, `scrollCaptureController`

#### OverlayView — The Main Interaction Surface
The core canvas view. Handles selection state machine, annotation rendering, input routing, and toolbar positioning. Tool-specific creation/update/finish logic is delegated to `AnnotationToolHandler` implementations in `UI/Tools/`.

**State machine:** `idle` → `selecting` → `selected`

**Zoom system:** 0.1x–8x (min 1.0x in overlay, 0.1x in editor), scroll/pinch to zoom, pan while zoomed, clickable zoom label

**Toolbars:** Real NSView-based toolbar strips (`ToolbarStripView` + `ToolbarButtonView`) positioned by OverlayView. Tool-specific options in `ToolOptionsRowView` with real NSSlider/NSSegmentedControl/NSButton controls. Popovers use `NSPopover` via `PopoverHelper`.

**Editor mode (EditorView subclass):** `EditorView` is a subclass of `OverlayView` that overrides behavior via clean override points. Uses NSScrollView for zoom/pan/centering. The old `isDetached` flag is removed — use `isEditorMode` computed property instead.

**CRITICAL — Overlay vs Editor coordinate rules:**
- **Never use `bounds` for image-to-pixel mapping.** Always use `captureDrawRect` (returns `bounds` in overlay, `selectionRect` in editor).
- **Never use raw view-space points for annotation positions.** Always convert via `viewToCanvas()` first.
- **Never call `viewToCanvas()` on a point that's already in canvas space.** `startAnnotation(at:)` receives canvas-space points — don't double-convert inside it.
- **When positioning NSViews (e.g. NSTextView for text tool),** convert canvas coords back to view coords via `canvasToView()`.
- **`compositedImage()`** renders at `captureDrawRect.size`, not `bounds.size`.
- **`sourceImageBounds`** for pixelate/blur/loupe must be set to `captureDrawRect`, not `bounds`.
- **For Vision API region crops** (OCR, barcode, auto-redact), draw the screenshot at `captureDrawRect` size, not `bounds` size.
- **Cursor management** is fully imperative (no cursor rects) via `updateCursorForPoint()` + `mouseMoved`. Each window only sets cursors when the mouse is actually over it (prevents cross-window flicker on multi-monitor).

**Drawing pipeline in `draw(_:)`:**
1. Background: screenshot image (full-screen in overlay, centered in editor via NSScrollView)
2. Dark overlay mask (except inside selection) — skipped in editor
3. Selection rectangle with 8 resize handles — skipped in editor
4. Annotations rendered with cached composite when not actively drawing
5. Toolbars positioned (real NSView subviews, not drawn inline)
6. Zoom label (fades out)
7. Scroll capture HUD overlays

#### Tool Handler Architecture
Each annotation tool's creation logic (start/update/finish) is extracted into an `AnnotationToolHandler` implementation. OverlayView dispatches through `toolHandlers[currentTool]` in `startAnnotation`, `updateAnnotation`, `finishAnnotation`.

**`AnnotationCanvas` protocol** — the interface tool handlers use to access OverlayView state (colors, stroke width, annotations, undo stack, snap guides, etc.) without coupling to the full class.

**`TextEditingCanvas` protocol** — additional interface for `TextEditingController` to access coordinate transforms and commit annotations.

Tools not extracted (handled directly in OverlayView): `select` (annotation interaction system), `colorSampler` (touches private color state), `crop` (editor-only image manipulation), `text` start/click detection (but all formatting/commit/cancel logic is in `TextEditingController`).

#### Annotation — Data Model + Drawing
Class (not struct) with `clone()` for safe copying. Lives in `Model/Annotation.swift`.

**Tools (`AnnotationTool` enum, 18 cases):** `pencil`, `line`, `arrow`, `rectangle`, `filledRectangle`, `ellipse`, `marker`, `text`, `number`, `stamp`, `pixelate`, `blur`, `measure`, `loupe`, `select`, `crop`, `colorSampler` (and video editor variants). Each annotation draws itself via `draw(in:)`, with `hitTest(point:threshold:)`, `move(dx:dy:)`, `isMovable`, `boundingRect`, `drawSelectionHighlight()`.

#### DetachedEditorWindowController — Standalone Editor
- Opens from overlay ("Open in Editor Window" button) or from thumbnail/pin "Edit" action
- Creates: NSScrollView → CenteringClipView → EditorView (documentView)
- Container view holds scroll view + EditorTopBarView
- `chromeParentView` set BEFORE `applySelection` so toolbars go in container (not document view)
- Static `activeControllers[]` array keeps instances alive; switches activation policy to `.regular` when open, `.accessory` when all closed

### Protocols

```text
OverlayWindowControllerDelegate  — OverlayWindowController → AppDelegate
OverlayViewDelegate              — OverlayView → OverlayWindowController / DetachedEditorWindowController
PinWindowControllerDelegate      — PinWindowController → AppDelegate
AnnotationToolHandler            — Tool creation/update/finish lifecycle
AnnotationCanvas                 — OverlayView state interface for tool handlers
TextEditingCanvas                — Coordinate transforms + annotation storage for TextEditingController
```

### Undo/Redo

`UndoEntry` enum: `.added(Annotation)`, `.deleted(Annotation, Int)`, `.imageTransform(...)`. Stacks: `undoStack` / `redoStack`. Batch undo via `groupID` (e.g. auto-redact creates multiple annotations with same groupID, all undone together).

### Coordinate Systems
- **Overlay:** View coordinates = screen frame, bottom-left origin (AppKit)
- **Editor:** EditorView inside NSScrollView — `isInsideScrollView` makes all transforms identity. NSScrollView handles zoom/pan/centering.
- **ScreenCaptureKit:** Top-left origin, needs conversion from AppKit bottom-left for scroll capture crop rects
- **Annotation coords:** Always relative to the overlay/editor view — shifted when transferring between overlay and editor

### Threading Model
- **Capture:** Async/await TaskGroup for concurrent multi-display capture
- **Scroll capture:** Background throttle/settlement timers, serialized captureAndStitch
- **OCR:** VNImageRequestHandler on background thread, results to main
- **Upload:** URLSession background task
- **UI:** All drawing, state changes, and user interaction on main thread

## Coding Conventions

- Pure AppKit, no SwiftUI except `BeautifyRenderer` which uses SwiftUI `MeshGradient` + `ImageRenderer` for mesh gradient rendering (macOS 15+ only, guarded with `@available`)
- **Use proper AppKit components:** NSPopover for popovers, NSView subclasses for toolbar buttons and strips, NSSlider/NSSegmentedControl/NSButton for controls, NSScrollView for editor zoom/pan, NSTextView for text editing. Avoid reimplementing standard UI components with manual `draw()` + coordinate hit-testing.
- **Strict concurrency:** CI builds with Xcode 16+ and `-Owholemodule` which enforces strict Swift concurrency. Any code using `@MainActor`-isolated SwiftUI APIs (e.g. `ImageRenderer`) must itself be `@MainActor`. Always mark classes/functions that touch SwiftUI rendering with `@MainActor`. Calling `@MainActor`-isolated methods (e.g. on AppDelegate) from non-`@MainActor` classes requires `MainActor.assumeIsolated { }`. **Local Debug builds do NOT catch these errors.** Before tagging a release, always verify with a Release build: `xcodebuild -scheme macshot -configuration Release build 2>&1 | grep "error:"`
- **Tool handler pattern:** New annotation tools should implement `AnnotationToolHandler` protocol in `UI/Tools/`, not add switch cases to OverlayView. The handler's `start`/`update`/`finish` methods use `AnnotationCanvas` to access shared state.
- Apple frameworks: ScreenCaptureKit, Vision, CoreImage, AVFoundation + Swift-WebP for WebP encoding
- SF Symbols for toolbar icons
- Minimal allocations during mouse tracking (reuse paths, avoid per-mouseMoved object creation)
- `[weak self]` in all closures to avoid retain cycles
- Tear down overlay windows and images promptly after capture
- UserDefaults for all preferences (no Core Data, no plist files)
- Annotation is a class (reference type) for mutation during drag/resize — use `clone()` for safe copies. **When adding new properties to Annotation, update three places:** the property declaration, `clone()`, and `CodableAnnotation` in `AnnotationCodable.swift` (`toCodable` + `fromCodable`). The compiler won't catch missing fields — annotations will silently lose data on clone or history reload.
- `autoreleasepool` for overlay teardown to prevent memory spikes
- Extension files (`OverlayView+Feature.swift`) for self-contained feature code that accesses OverlayView state but is logically separate (scroll capture HUD, window snapping, popovers)
- **Light/dark mode:** The toolbar and popovers always use a dark background regardless of system appearance. `ToolOptionsRowView` and `PopoverHelper` force `NSAppearance(named: .darkAqua)` so system controls render with light text. Never use system-adaptive colors (`.labelColor`, `.secondaryLabelColor`) for text in toolbar/popover contexts without verifying contrast against the dark background. Always test new toolbar UI elements in both light and dark system appearance.
- **Focus management:** macshot is an `LSUIElement` (menu bar app) that temporarily shows windows. All focus return is handled by `AppDelegate.returnFocusIfNeeded()` — one centralized method. Rules:
  - `previousApp` is captured in `startCapture()` before the overlay steals focus. Cleared after single use.
  - `returnFocusIfNeeded()` checks for visible titled windows, switches to `.accessory` policy, activates `previousApp`. Falls back to `NSApp.hide(nil)` when `previousApp` is nil (editor/OCR/preferences close).
  - `dismissOverlays(refocusPreviousApp: true)` (default) calls `returnFocusIfNeeded()`. Pass `false` only when macshot creates floating panels immediately after (pin, upload toast).
  - **Critical pattern for pin/upload/OCR-window paths:** `returnFocusIfNeeded()` uses `NSApp.hide(nil)` as fallback, which hides ALL windows — including floating panels with `hidesOnDeactivate = false`. So any overlay dismiss that creates a floating panel afterward MUST: (1) save `previousApp` locally, (2) `dismissOverlays(refocusPreviousApp: false)`, (3) create the panel, (4) manually `app.activate(options: .activateIgnoringOtherApps)` on the saved app. See `overlayDidRequestPin` and `overlayDidRequestUpload` for the pattern.
  - Every window close (editor, video editor, OCR, preferences) calls `returnFocusIfNeeded()` — never inline `setActivationPolicy`/`activate` directly.
  - All floating panels (thumbnails, pins, upload toasts, HUD, overlays) must set `hidesOnDeactivate = false` so they survive app deactivation. Pin windows must use `orderFrontRegardless()` instead of `makeKeyAndOrderFront` to avoid activating macshot.
  - `NSApp.activate(options: .activateIgnoringOtherApps)` is the only reliable way to switch focus to another app — plain `activate()` and `NSApp.deactivate()` do not reliably transfer focus on macOS 26.
  - `NSApp.hide(nil)` reliably transfers focus (activates next app in line) but hides ALL windows — only safe as last resort when no floating panels are expected.

## Build & Run

### ⚠️ 打包铁律（MANDATORY）

**任何代码改动后，安装/更新本机 `/Applications/MacShot.app` 必须且只能跑仓库根目录的 `./build.sh`。绝对禁止绕过它**：

- ❌ 禁止直接 `xcodebuild` 裸跑（会用默认 DerivedData 产生新的 app 副本并注册进 LaunchServices，Finder/Raycast「打开方式」里会多出好几个 MacShot——已为此踩过坑）
- ❌ 禁止 `ditto`/`cp` 手动拷贝 .app 到 /Applications（会丢自签名和 entitlements，屏幕录制权限失效）
- ✅ 唯一正确方式：`cd /Users/fxj/m/macshot && ./build.sh`（停止旧版 → 构建 → 自签名 → rsync 安装 → 注销多余 LS 注册 → 启动）

`build.sh` 自己会做签名（自签名证书 + entitlements）、LaunchServices 清理（按 bundle id 注销除 `/Applications/MacShot.app` 外的所有注册）和启动。裸 `xcodebuild` 只允许用来**验证编译**（看报错），不得用于安装；如确需产物，必须加 `-derivedDataPath /Users/fxj/m/macshot/DerivedData`。

### 日常运行

- Open `macshot.xcodeproj` in Xcode
- Build & Run (Cmd+R)
- Grant Screen Recording permission when prompted
- App appears as icon in menu bar (no dock icon)
- Click menu bar icon → "Capture Screen" or use global hotkey (default: Cmd+Shift+X)

## Releasing

### Workflow: `.github/workflows/build-release.yml`

CI now uses a simple zip-based release flow that does **not** require Apple signing, notarization, Sparkle, or Homebrew secrets:

- **Push to `dev`** → automatic rolling pre-release (`dev-latest`) with a zipped `MacShot.app`.
- **Tag push** (`v*.*.*` or `v*.*.*-beta.*`) or manual `workflow_dispatch` with a tag → tagged GitHub Release with a zipped `MacShot.app`.

Because the builds are unsigned, users may need to right-click the app and choose **Open** on first launch to bypass Gatekeeper.

### Stable release

1. **Add a CHANGELOG.md entry** for the new version — CI extracts it for GitHub Release notes.
2. **Tag and push:** `git tag v3.8.0 && git push origin main --tags`
3. CI builds `MacShot.app`, zips it, and publishes it to GitHub Releases.

### Beta release

1. **Add a CHANGELOG.md entry** (e.g. `## [3.8.0-beta.3] - 2026-04-06`).
2. **Tag with `-beta.N` suffix:** `git tag v3.8.0-beta.3 && git push origin v3.8.0-beta.3`
3. CI marks the GitHub Release as **pre-release** and uploads the zip artifact.

### Manual trigger (fallback)

If tag push doesn't trigger CI (e.g. after rapid tag create/delete), use:
```bash
gh workflow run build-release.yml --ref main -f tag=v3.8.0-beta.3
```
This dispatches from main and reads the tag from the input parameter. The tag must already exist on the remote. If you leave `tag` empty when dispatching manually, the workflow builds the selected ref as that branch's rolling `*-latest` pre-release instead.

### Notes

- `MARKETING_VERSION` in `project.pbxproj` is only used for local dev builds. CI always overrides it.
- Never rapidly create/delete tags — GitHub throttles tag push events and may suppress triggers for 15-30 minutes.
- The workflow was renamed from `release.yml` to `build-release.yml`.
- **RTK token filter:** Prefix common `git` / `gh` / file-inspection commands with `rtk` (e.g. `rtk git status`, `rtk git diff`, `rtk git commit`; keep `./build.sh` and `xcodebuild` direct).
