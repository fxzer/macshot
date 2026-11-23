# macshot Architecture & Reference

> Read this document on demand when inspecting the full source file layout, UserDefaults persistence keys, or complete feature inventory.

## File Structure

```text
macshot/
├── main.swift                          # App entry point
├── AppDelegate.swift                   # App lifecycle, status bar, hotkey, capture orchestration
│
├── Model/
│   └── Annotation.swift                # Annotation data model + geometry / hit-testing
│
├── Capture/
│   ├── ScreenCaptureManager.swift      # Multi-screen capture via ScreenCaptureKit (async/await)
│   └── ScrollCaptureEngine.swift       # Scroll capture with SAD-based stitching
│
├── Store/
│   ├── BeautifyBackgroundStore.swift   # Custom beautify background persistence
│   ├── KeychainStore.swift             # Secrets / token persistence
│   ├── SaveDirectoryAccess.swift       # Security-scoped bookmark persistence
│   └── ScreenshotHistory.swift         # Local history in ~/Library/Application Support/
│
├── Processors/
│   ├── BackgroundRemovalProcessor.swift # Foreground subject extraction
│   ├── BeautifyRenderer.swift          # Gradient frame / background beautification
│   ├── ImageEffects.swift              # Core Image-based image effects
│   └── ImageEncoder.swift              # PNG/JPEG/HEIC/WebP encoding, clipboard copy, scaling
│
├── Services/
│   ├── AutoRedactor.swift              # PII regex detection + Vision OCR → redaction annotations
│   ├── BarcodeDetector.swift           # Async Vision barcode/QR scanning, badge drawing, hit-testing
│   ├── VisionOCR.swift                 # Vision text recognition request factory
│   └── HotkeyManager.swift             # Global keyboard shortcut (Carbon RegisterEventHotKey)
│
├── Upload/
│   ├── ImgbbUploader.swift             # imgbb image upload
│   ├── GoogleDriveUploader.swift       # Google Drive OAuth2 upload
│   └── S3Uploader.swift                # S3-compatible upload
│
├── UI/
│   ├── Overlay/
│   │   ├── Core/                       # OverlayView core type, protocols, lifecycle, base routing
│   │   ├── State/                      # OverlayAppearance/Render/Preview/Toolbar/Tool state containers
│   │   ├── Input/                      # Mouse, keyboard, cursor, hit-testing
│   │   ├── Selection/                  # Selection drag/resize/memory/aspect/window snapping
│   │   ├── Editing/                    # Annotation interaction, properties, undo, text editing
│   │   ├── Rendering/                  # Draw pipeline, output rendering, cache, previews, guides
│   │   │   └── Renderers/              # Annotation draw dispatch + tool-specific rendering
│   │   ├── Controls/                   # Toolbar, tool options, popovers, overlay control chrome
│   │   ├── Modes/                      # Zooming, color sampler, beautify, scroll capture, redaction
│   │   ├── Panels/                     # HUDs, overlays, preview panels, tooltip views
│   │   └── Window/                     # OverlayWindowController and delegate/share/window splits
│   │
│   ├── Editor/
│   │   ├── EditorView.swift            # OverlayView subclass: NSScrollView mode, no selection chrome
│   │   ├── DetachedEditorWindowController.swift  # Standalone editor window (resizable, titled)
│   │   ├── EditorTopBarView.swift      # NSView with crop, flip, zoom buttons
│   │   └── CenteringClipView.swift     # NSClipView subclass that centers document when smaller than clip
│   │
│   ├── Toolbar/
│   │   ├── ToolbarDefinitions.swift    # ToolbarButtonAction enum, ToolbarButton struct, ToolbarLayout constants
│   │   ├── ToolbarButtonView.swift     # NSView for a single toolbar button (hover, press, selection states)
│   │   ├── ToolbarStripView.swift      # NSView container for horizontal/vertical button rows
│   │   └── ToolOptionsRowView.swift    # NSView-based tool options bar (sliders, segments, text formatting)
│   │
│   ├── Tools/
│   │   ├── AnnotationToolHandler.swift # AnnotationToolHandler + AnnotationCanvas protocols, shared helpers
│   │   ├── PencilToolHandler.swift     # Freeform draw with Chaikin smoothing
│   │   ├── MarkerToolHandler.swift     # Highlighter (semi-transparent wide stroke)
│   │   ├── LineToolHandler.swift       # Straight line with 45° snap
│   │   ├── ArrowToolHandler.swift      # Arrow with styles (single, thick, double, open, tail)
│   │   ├── RectangleToolHandler.swift  # Rectangle with corner radius, fill style, line style
│   │   ├── FilledRectangleToolHandler.swift  # Opaque filled rectangle (redact)
│   │   ├── EllipseToolHandler.swift    # Ellipse with fill style
│   │   ├── PixelateToolHandler.swift   # Pixelate region
│   │   ├── BlurToolHandler.swift       # Gaussian blur region
│   │   ├── LoupeToolHandler.swift      # Click-to-place 2x magnifier
│   │   ├── MeasureToolHandler.swift    # Pixel ruler with 45° snap
│   │   ├── NumberToolHandler.swift     # Auto-incrementing numbered circle
│   │   ├── StampToolHandler.swift      # Emoji/image stamp + StampEmojis data
│   │   └── TextEditingController.swift # Text tool: NSTextView lifecycle, formatting, commit, cancel
│   │
│   ├── Popover/
│   │   ├── PopoverHelper.swift         # Static helper for showing/dismissing NSPopovers
│   │   ├── ColorPickerView.swift       # Custom color picker: swatches, HSB gradient, opacity, custom slots
│   │   ├── ListPickerView.swift        # Reusable list picker with checkmark selection
│   │   ├── EmojiPickerView.swift       # Emoji grid with category tabs
│   │   └── GradientPickerView.swift    # Beautify gradient style swatch grid
│   │
│   └── Windows/
│       ├── PinWindowController.swift          # Floating always-on-top pinned screenshot
│       ├── FloatingThumbnailController.swift  # Auto-dismiss thumbnail after capture
│       ├── SettingsWindowController.swift     # Settings: General, Capture, Behavior, Shortcuts, Tools, Uploads, About tabs
│       ├── OCRResultController.swift          # Text recognition results window with AI search
│       ├── HistoryOverlayController.swift     # Recent captures visual overlay panel
│       ├── UploadToastController.swift        # Upload progress/success toast
│       ├── CountdownView.swift                # Delay capture countdown display
│       └── PermissionOnboardingController.swift  # First-run permission guide
│
├── Info.plist
├── Assets.xcassets/
└── Base.lproj/Main.storyboard
```

## Persistence (UserDefaults)

- Drawing: `currentStrokeWidth`, `numberStrokeWidth`, `markerStrokeWidth`
- Hotkey: `hotkeyKeyCode`, `hotkeyModifiers`
- Output: `saveDirectory`, `autoCopyToClipboard`, `playCopySound`
- Selection: `lastSelectionRect`, `lastSelectionScreenFrame`, `rememberLastSelection`
- Thumbnails: `showFloatingThumbnail`, `thumbnailStacking`, `thumbnailAutoDismissSeconds`
- Image: `imageFormat` (png/jpeg/heic/webp), `imageQuality` (0.0–1.0), `downscaleRetina` (bool), `embedColorProfile` (bool)
- History: `historySize`
- Tools: `enabledTools`, `knownToolRawValues`
- Features: `imgbbAPIKey`, `beautifyEnabled`, `beautifyStyleIndex`, `beautifyMode`, `beautifyPadding`, `beautifyCornerRadius`, `beautifyShadowRadius`, `pencilSmoothEnabled`, `loupeSize`
- Styles: `currentLineStyle`, `currentArrowStyle`, `currentRectFillStyle`, `currentRectCornerRadius`
- Upload: `uploadProvider` (imgbb/gdrive), `googleDriveRefreshToken`, `uploadConfirmEnabled`

## Features

### Core
- Multi-screen capture (one overlay per screen, concurrent ScreenCaptureKit calls)
- Rubber-band selection with 8-point resize handles
- Full-screen capture (single click without drag)
- Remember last selection rectangle

### Annotation Tools (17)
Pencil, Line, Arrow, Rectangle, Filled Rectangle, Ellipse, Marker/Highlighter, Text (rich formatting), Number (auto-incrementing), Stamp/Emoji, Pixelate, Blur, Measure (pixel ruler), Loupe (2x magnifier), Select & Edit, Crop (editor only), Color Sampler

- **Line styles:** Solid, dashed, dotted
- **Arrow styles:** Single, thick, double, open, tail
- **Annotation rotation:** Rotate shapes via handle, Shift to snap to 90°
- **Bend control points:** Draggable cubic bezier curve on lines and arrows
- **Stamp tool:** Place emoji or custom images, load from file

### Output Actions
Copy to clipboard, Save to file (PNG/JPEG/HEIC/WebP), Pin (floating always-on-top), OCR (Chinese + English, auto-detected), Upload to imgbb or Google Drive (OAuth2), Remove background (VNGenerateForegroundInstanceMaskRequest), Open in editor, Beautify (30 gradient styles including 7 mesh gradients on macOS 15+), Flip horizontal/vertical

### Advanced
- **Editor Window:** Standalone resizable window for post-capture editing, full annotation tools, zoom 0.1x–8x via NSScrollView
- **Scroll Capture:** Automatic scroll detection + stitching via SAD matching
- **Auto-Redact:** Right-click filled rect → regex patterns (emails, phones, SSN, credit cards, IPs, AWS keys, bearer tokens)
- **Barcode/QR Detection:** Live Vision detection with decoded payload, open/copy actions
- **Floating Thumbnail:** Stackable, draggable, auto-dismiss, quick actions
- **Screenshot History:** Local storage with thumbnails, "Recent Captures" menu, visual history overlay panel
- **Delay Capture:** Configurable countdown (3s, 5s, 10s)
- **Color Opacity:** Adjustable per annotation via custom color picker
- **Smooth Pencil Strokes:** Toggle in settings
- **Zoom:** 0.1x–8x, scroll/pinch, pan, clickable label to edit percentage
- **Permission Onboarding:** First-run guide for granting Screen Recording permission
