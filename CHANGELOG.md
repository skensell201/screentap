# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] — 2026-11-27

First public release.

### Added

- Menu bar app that captures a selected screen area when both main mouse buttons are
  pressed at the same time, and copies the result to the clipboard.
- Full-screen selection overlay with dimming, a selection frame with corner handles, a
  live size readout, `Enter` to confirm, `Esc` to cancel, and a click without dragging
  to select the whole screen under the cursor.
- Gesture recognition as a pure state machine (`ChordStateMachine`) that recognises
  both the overlapping press and the two-quick-clicks variant, and ignores drags.
- `CGEventTap` based detection that swallows the mouse events, so the context menu of
  the application under the cursor never appears. Falls back to `NSEvent` monitors when
  the Accessibility permission is missing.
- Capture via `SCScreenshotManager.captureImage(in:)` with a `ScreenCaptureKit` crop path
  and a `CGWindowListCreateImage` fallback, always in the native resolution of the
  display.
- Permission handling: the app asks macOS for the screen recording and accessibility
  permissions itself, restarts as soon as a permission arrives, and shows a warning
  triangle in the menu bar while a permission is missing.
- Menu bar items for launching at login, requesting the permissions, opening the privacy
  settings, restarting the app and quitting.
- Sound feedback on a successful capture.
- `--selftest`, `--demo`, `--debug` and `--coord-test` command line modes.
- Public repository with a CI workflow that builds the app and runs the state machine
  tests on macOS.

[1.0.0]: https://github.com/skensell201/screentap/releases/tag/v1.0.0
