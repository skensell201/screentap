# ScreenTap — Design

**Date:** 2026-11-26
**Status:** agreed with the user (native Swift app, activation after both buttons are released,
clipboard plus sound, menu bar app with launch at login)

## 1. Goal

A macOS utility: pressing **both** main mouse buttons at the same time opens an area
selection mode; once the area is confirmed, the fragment goes straight into the clipboard.

The main scenario: the user never has to let go of the mouse and never has to leave the
application they are working in.

## 2. Requirements (from the user's answers)

| # | Requirement | Decision |
|---|---|---|
| R1 | Deliverable format | Native `.app` written in Swift / AppKit, no external dependencies |
| R2 | When the mode opens | After both buttons are released, not when the second one goes down |
| R3 | Result | Clipboard only plus a short sound, no files are written |
| R4 | Startup | Menu bar icon plus launch at login |
| R5 | Extras | Public repository, a proper README, an app icon |

## 3. Architecture

Five modules with one responsibility each:

```
ChordDetector ──► ChordStateMachine (pure logic, testable)
      │
      ▼
SelectionOverlay ──► ScreenCapturer ──► ClipboardWriter ──► FeedbackSound
```

### 3.1 `ChordStateMachine` (pure, no AppKit)

Input: `buttonDown(button, time)`, `buttonUp(button, time)`, `tick(now)`.
Output: a directive — `.pass`, `.swallow`, `.armChord`, `.repostBufferedDown`, `.chordCompleted`.

Rules for recognising the gesture:

* **Overlap** (primary): the second button goes down while the first one is still held, and no
  more than `window` (200 ms) has passed since the first press.
* **Sequence** (secondary): the first button was a quick click without pointer travel (more
  than 10 pt of movement counts as a drag and disables this mode) and the second button goes
  down within 200 ms of that click. This keeps fast text selection from firing the gesture.

The state is reset once all buttons are released.

### 3.2 `ChordDetector` (event source)

Two sources, selected dynamically:

1. **CGEventTap** (primary) — requires the "Accessibility" permission:
   * the left button is passed through immediately (no click latency anywhere in the system);
   * the right button is **always swallowed and buffered**; if no gesture follows, the event is
     re-injected through `CGEvent.post` with an updated timestamp, so the context menu opens
     about 200 ms later;
   * once the gesture is confirmed, the events of both buttons are swallowed and the context
     menu never appears;
   * re-injected events carry a magic `eventSourceUserData` value so that they are not
     processed by our own tap a second time.
2. **NSEvent global/local monitors** (fallback without Accessibility) — always available, but
   they cannot suppress anything.

Known trade-off: if the user starts the gesture **with the left button**, that button has
already reached the application under the cursor (a delivered event cannot be recalled), so a
single stray click may happen. A gesture that starts with the right button is clean. Delaying
every left click by 200 ms to avoid this would degrade the responsiveness of the whole system.

### 3.3 `SelectionOverlay`

One borderless window at level `.overlayWindow` that covers the union of all displays
(`collectionBehavior`: `.canJoinAllSpaces`, `.fullScreenAuxiliary`, `.stationary`).

* Dimming: the whole screen before the selection starts, and four rectangles around the
  selection while dragging (plain drawing, no blend modes).
* Crosshair, selection frame, corner handles, HUD with the live size.
* Controls: drag to select, `Enter`/`Space` to confirm, `Esc` to cancel.
* A click without dragging (less than 4 pt) selects the whole screen under the cursor, like
  the system screenshot tool does.
* After confirmation the window is hidden, the app waits ~120 ms so that the overlay does not
  end up in the frame, then captures and copies.

### 3.4 `ScreenCapturer`

Primary path: `SCScreenshotManager.captureImage(contentFilter:configuration:)` (macOS 14+).
The whole display is captured through `SCContentFilter(display:excludingWindows:)` and the
region is cropped afterwards in pixels. Capturing the full display first avoids the
coordinate-system mismatch between Cocoa (y up) and the bitmap (y down).

* The display is picked by the largest overlap with the selected region.
* The scale is computed as `image.width / screen.frame.width`, so Retina and external
  displays are handled the same way.
* Fallback: `CGWindowListCreateImage` (deprecated, but still functional on some systems).
* Requires the "Screen Recording" permission.

### 3.5 `ClipboardWriter`, `FeedbackSound`

PNG data goes into `NSPasteboard.general` (plus a TIFF representation, so that pasting works
in every application). A short system sound confirms the result.

### 3.6 `LaunchAgentController`

Launch at login is implemented through `~/Library/LaunchAgents/xyz.screentap.ScreenTap.plist`
plus `launchctl bootstrap`. It was chosen over `SMAppService.mainApp` because the latter
requires a stable signature and a fixed location in `/Applications`, while an ad-hoc signature
changes the TCC identity on every rebuild.

## 4. Permissions

| Permission | Why | Required |
|---|---|---|
| Screen Recording | Captures the image of the display | Yes — without it the app cannot work |
| Accessibility | `CGEventTap` — intercepting and suppressing mouse events | No, but without it the context menu appears |

The app checks both permissions at startup and on a timer, shows a warning in the menu bar
and opens the relevant System Settings page.

## 5. Failure modes

| Situation | Behaviour |
|---|---|
| No "Screen Recording" permission | The menu bar icon turns into a warning, the menu offers to open the settings, no screenshot is taken |
| No "Accessibility" permission | The fallback detector works, the menu warns about it |
| The capture returns an empty result | An error dialog is shown, the clipboard is left untouched |
| The region is smaller than 4×4 pt | The selection is cancelled silently |
| `Esc` during the selection | Cancelled, the clipboard is left untouched |

## 6. Build

* `swift build -c release` (SwiftPM) produces the binary.
* `Scripts/build.sh` assembles `ScreenTap.app`: `Info.plist`, `Resources/AppIcon.icns` and an
  ad-hoc signature (`codesign -s -`).
* A stable signature is possible: if `SCREENTAP_CODESIGN_IDENTITY` is set, that identity is
  used, and the TCC permission then survives rebuilding the app.

## 7. Testing

* `--selftest` runs the `ChordStateMachine` against synthetic event sequences: a correct
  gesture, the gesture with the buttons swapped, a plain click, a plain right click, a drag
  followed by a right click, and the state reset after a gesture.
* `--debug` logs mouse events and machine state to stdout.
* `--demo` runs the full cycle programmatically: overlay → selection → capture → clipboard,
  with the result written to a file for inspection.

## 8. Repository layout

```
ScreenTap/
├── README.md                 # proper README
├── LICENSE                   # MIT
├── Package.swift
├── Sources/ScreenTap/        # Swift sources
├── Scripts/build.sh          # builds the .app
├── Scripts/make-icon.sh      # generates the .icns from a PNG
├── Scripts/pad-icon.swift    # prepares the 1024x1024 icon canvas
├── Scripts/render-preview.swift # renders the selection mode illustration
├── Resources/AppIcon.icns    # app icon
└── docs/superpowers/specs/   # this spec
```
