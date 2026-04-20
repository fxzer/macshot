<p align="center">
  <img src="assets/logo.svg" alt="macshot logo" width="200"/>
</p>

<p align="center">
  <b>Free, open-source screenshot & screen recording tool for macOS.</b><br>
  Native Swift + AppKit. No Electron. No bloat.
</p>

<p align="center">
  <a href="https://github.com/fxzer/macshot/releases/latest">Download</a> · <a href="https://github.com/fxzer/macshot/blob/main/CHANGELOG.md">Changelog</a> · <a href="https://github.com/fxzer/macshot/blob/main/PRIVACY.md">Privacy</a>
  <br>
  <a href="README.zh-CN.md">简体中文</a>
</p>

<p align="center">
  <img src="assets/preview.png" alt="macshot demo" width="700"/>
</p>

---

### Why macshot?

- **Capture & annotate in one flow** — select a region, draw arrows/text/shapes/blur, copy to clipboard. One hotkey, zero friction.
- **Screen recording with built-in editor** — record any area or full screen as MP4/GIF with system audio + microphone. Audio merge dialog with per-track volume control. Trim and export without leaving the app.
- **Scroll capture** — select a region and scroll. macshot stitches it into one seamless tall (or wide) image automatically.
- **Upload anywhere** — one-click upload to Google Drive, imgbb, or any S3-compatible service (Cloudflare R2, AWS S3, MinIO, etc.). Link copied to clipboard instantly.
- **Lightweight & native** — ~8 MB memory at idle. Lives in your menu bar. Built with Swift and AppKit, not a web browser in disguise.
- **2 languages** — English, 中文 (简体). Auto-detects your system language.

---

## Install

**Homebrew:**
```bash
brew install fxzer/macshot/macshot
```

**Manual:** Download the latest `.dmg` from [Releases](https://github.com/fxzer/macshot/releases), open it, drag to `/Applications`.

---

## Quick Start

1. Launch macshot — it appears in your menu bar
2. Press `Cmd+Shift+X` to capture
3. Drag to select, annotate with the toolbar, press `Cmd+C` to copy
4. Press `Esc` to cancel

---

<details>
<summary><b>All Features</b></summary>

### Capture
- **Instant capture** — global hotkey freezes your screen, select any region
- **Window snap** — hover over a window and click to capture it exactly; `Tab` toggles snap, `F` for full screen
- **Scroll capture** — auto-detects vertical or horizontal scrolling, stitches with Apple Vision, live preview panel beside the capture region
- **Capture delay** — 3/5/10/30 second countdown before capture, set via menu bar. Escape to cancel.
- **Multi-monitor** — captures all screens simultaneously; drag a selection across screens for a stitched image
- **Quick save** — `Cmd+Shift+S` to select and save/copy instantly without annotation. Enter key also saves/copies based on preference.
- **Quick OCR** — `Cmd+Shift+T` to select and extract text instantly

### Annotation Tools
- **Arrow** — 5 styles: single, thick/banner, double, open, tail; flip direction toggle; right-click to add anchor points for complex curves
- **Shapes** — rectangle and ellipse with 3 fill modes (stroke, stroke+fill, fill), corner radius slider
- **Text** — rich formatting (bold/italic/underline/strikethrough), resizable text box, left/center/right alignment, background fill & outline colors, click to re-edit
- **Pencil & Marker** — freeform drawing with optional smoothing; smart marker mode snaps to text lines via OCR
- **Numbered markers** — auto-incrementing (1/I/A/a formats), with optional pointer cone
- **Stamp / Emoji** — 21 quick emojis, 100+ in categorized picker, or load any image
- **Censor (Pixelate / Blur / Solid / Erase)** — unified redaction tool with 4 modes: pixelate, Gaussian blur, solid color fill, or smart erase that samples surrounding colors for invisible content removal. Auto-redact PII (emails, phones, credit cards, SSNs, API keys), auto-detect faces and people, or draw in "Text Only" mode to censor just the text in a region
- **Measure** — pixel ruler with px/pt toggle; hold `1` or `2` for auto-measure
- **Loupe** — 2x magnifier
- **Color sampler** — eyedropper to pick any color; right-click to copy hex; auto-saves to custom palette slots
- **Space to reposition** — hold Space while drawing to move the shape without changing its size
- **Rotation** — rotate shapes via handle, Shift for 90° snaps
- **Click-to-select** — click any annotation to select it, then edit properties (stroke, style, fill), drag to move, resize via handles, rotate, or delete — all without switching tools

### Screen Recording
- **MP4 (H.264)** up to 120fps or **GIF** (5/10/15fps)
- **System audio capture** — toggle on/off, excludes macshot's own sounds
- **Microphone recording** — record voice narration alongside screen capture (permission requested on first use)
- **Mouse click highlights** — visual ripple on clicks during recording
- **Selection border** — visible capture region outline during recording
- **Menu bar stop button** — stop recording from the menu bar icon (appears even if icon is hidden)
- **Quick settings popover** — change format, FPS, and post-recording action on the fly without opening Preferences
- **Video editor** — trim timeline, mute/strip audio, play/pause, save (with Save As), upload, reveal in Finder

### Output & Upload
- **Formats** — PNG, JPEG, HEIC, WebP with quality slider
- **Google Drive** — sign in once, uploads to a private "macshot" folder
- **imgbb** — anonymous image hosting with shareable links
- **S3-compatible** — upload to Cloudflare R2, AWS S3, MinIO, DigitalOcean Spaces, Backblaze B2, etc.
- **Retina downscale** — optional 1x export for smaller files
- **sRGB color profile** — optional embedding for cross-display consistency

### Editor Window
- Standalone resizable window with full annotation tools, beautify preview
- **Add Capture** — capture additional screen regions and compose them into a single image, drag to reposition
- Crop (with rule-of-thirds grid), flip H/V, zoom 0.1x–8x
- Top bar with pixel dimensions, zoom dropdown (presets, fit canvas, zoom in/out)

### Beautify
- macOS window frame with traffic lights, shadow, and gradient background
- 30 gradient styles including 7 mesh gradients (macOS 15+), adjustable padding/corner radius/shadow

### Image Effects (Adjust)
- Non-destructive CIFilter adjustments: Brightness, Contrast, Saturation, Sharpness
- 8 presets: Noir, Mono, Sepia, Chrome, Fade, Instant, Vivid
- Works independently or combined with Beautify
- Live preview in the overlay

### Other
- **OCR** — extract text with Apple Vision (auto-detects all languages on macOS 13+), auto-copy to clipboard, translate to 30+ languages, Google AI Search
- **Invert colors** — one-click color inversion, apply twice to revert
- **Background removal** — Apple Vision foreground mask (macOS 14+)
- **Pin to screen** — floating always-on-top window
- **Floating thumbnail** — auto-dismiss preview with Copy/Save/Pin/Edit/Upload
- **Screenshot history with editable annotations** — menu bar submenu + drop-down history panel (`Cmd+Shift+H`). Re-open any capture in the editor with live annotations preserved — edit, then press Done to save back. Drag-and-drop, Quick Look, and right-click actions
- **QR & barcode detection** — inline Open/Copy actions
- **Snap alignment guides** — annotations snap to midlines and edges
- **Auto-updates** via Sparkle
- **~8 MB memory** at idle

---

<details>
<summary><b>Enhanced Features (fxzer fork)</b></summary>

This fork includes numerous enhancements and custom features developed by fxzer. Below is a comprehensive summary of all customizations.

### UI/UX Improvements

**Toolbar & Panel Reorganization**
- 🎨 **Dual-container toolbar layout** — restructured toolbar with improved visual hierarchy
- **Beautify Picker redesign** — dedicated Beautify UI component with optimized gradient swatch grid alignment
- **Editor top bar** — enhanced editor window with pixel dimensions, zoom dropdown, crop/flip buttons
- **Popover alignment** — improved alignment logic for popovers, toolbars, and UI elements

**Hint & Feedback System**
- 💡 **Unified hint system** — synchronized overlay hints and error messages across multi-monitor setups
- **Enhanced feedback animations** — improved save feedback, color copy hints, and status indicators
- **Menu bar positioning** — fixed status bar menu position to avoid overlap in high-DPI scenarios

**Upload History UI**
- 📷 **SwiftUI Grid layout** — upload history redesigned with SwiftUI Grid and thumbnail support
- **Simplified settings** — removed complex tab switcher, unified upload settings layout
- **5-column grid** — optimized spacing and interaction for upload history

### Feature Enhancements

**Capture Tools**
- 📐 **Selection size snapping** — snap to specific aspect ratios (16:9, 4:3, 1:1, etc.) or pixel dimensions (50/100px steps)
- 🔒 **Aspect ratio lock** — lock selection to 1:1, 3:4, or 9:16 during drawing; press `R` to rotate
- **Image effects in overlay** — enable image effect tools directly in screenshot overlay
- **Auto-scaling aspect-fit** — detached editor now supports automatic aspect-fit scaling

**Color & Pin Window**
- 🎨 **Enhanced color sampler** — magnifier view with pixel-level precision, color gamut display (Display P3/sRGB/Adobe RGB)
- 🖼️ **Color fidelity separation** — accurate color representation across different displays for pin windows
- **Improved pin positioning** — better auto-pin positioning after copy operations

**OCR & Translation**
- 🌐 **Youdao translation integration** — added and set as default translation engine
- **Responsive OCR window** — improved OCR window responsiveness and settings

**Filename & Output**
- 📅 **Customizable filename format** — configure timestamp format (year/month/day/hour/minute/second) for automatic file naming
- **Unified upload filename** — consistent filename format between uploads and local saves

**Interaction Improvements**
- 🖱️ **Scroll wheel tool sizing** — adjust stroke width or tool size by scrolling over tool buttons (no need to click first)
- **Undo/Redo disabled states** — visual feedback for unavailable undo/redo actions

### Internationalization & Optimization

**Language Simplification**
- 🌍 **2 languages only** — reduced from 40 languages to English and Simplified Chinese (简体) for lighter app size
- **Removed knownRegions** — cleaned up .pbxproj by removing unused language regions

**Resource Optimization**
- 🗜️ **WebP conversion** — permission images converted from PNG to WebP for smaller size
- **Faster overlay appearance** — deferred image conversion for improved responsiveness

### Performance & Stability

**Rendering Performance**
- ⚡ **PNG encoding for share** — optimized share button performance using PNG encoding
- **Deferred image conversion** — delays overlay appearance conversion for faster startup

**Data Reliability**
- 🔐 **UserDefaults fallback** — added fallback for Keychain data storage failures
- **Improved Google Drive stability** — better login status refresh and error handling

**Experimental Features (Rolled Back)**
- Attempted weak reference collections for controller memory management
- Image caching and screenshot pooling (rolled back for further refinement)
- Drawing throttling and performance monitoring tools (rolled back)

</details>

</details>

<details>
<summary><b>Keyboard Shortcuts</b></summary>

**Global hotkeys** (configurable in Preferences)

| Shortcut | Action |
|---|---|
| `Cmd+Shift+X` | Capture Area |
| `Cmd+Shift+F` | Capture Full Screen |
| `Cmd+Shift+S` | Quick Capture (instant save) |
| `Cmd+Shift+T` | Capture OCR (instant text extraction) |
| `Cmd+Shift+R` | Record Area |
| `Cmd+Shift+H` | Show History Panel |

**General** (during capture)

| Shortcut | Action |
|---|---|
| `Enter` | Confirm (save or copy based on preference) |
| `Cmd+C` | Copy to clipboard |
| `Cmd+S` | Save to file |
| `Cmd+Z` / `Cmd+Shift+Z` | Undo / Redo |
| `Cmd+0` | Reset zoom to 1x |
| `Esc` | Cancel / close popover |
| `Delete` | Remove selected annotation |
| `Tab` | Toggle window snap mode |
| `F` | Capture full screen (snap mode) |
| `Shift` (while drawing) | Constrain to straight lines / perfect shapes |
| `Space` (while drawing) | Reposition shape without changing size |
| `Right-click` on line/arrow | Add anchor point for multi-point curves |

**Tool shortcuts** (active after selecting a region — customizable in Preferences > Shortcuts)

| Key | Tool |
|---|---|
| `A` | Arrow |
| `L` | Line |
| `P` | Pencil |
| `M` | Marker |
| `R` | Rectangle |
| `O` | Ellipse |
| `T` | Text |
| `N` | Number |
| `B` | Censor (Pixelate/Blur) |
| `I` | Color Sampler |
| `G` | Stamp / Emoji |
| `S` | Select & Edit |
| `E` | Open in Editor |

</details>

---

## Permissions

macshot requires **Screen Recording** permission. macOS will prompt you on first capture.

---

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=fxzer/macshot&type=Date)](https://star-history.com/#fxzer/macshot&Date)

## Requirements

macOS 12.3 (Monterey) or later.

## License

[GPLv3](LICENSE)
