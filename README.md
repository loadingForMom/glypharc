# GlyphArc

GlyphArc is a native macOS writing assistant that reacts to selected text and shows a lightweight floating control near the selection. It is designed for fast text actions without breaking the user's flow while writing, editing, or reading in other apps.

The app uses macOS Accessibility APIs to track the current text selection, display an overlay near it, and send selected text to an AI pipeline for writing-related actions.

## What it does

- Detects selected text across macOS apps.
- Shows a floating overlay near the selection.
- Keeps the overlay responsive while the page or document scrolls.
- Uses a native Swift/macOS interface.
- Integrates with an AI client for text transformation workflows.

## First version

This first public version includes a major cleanup and modernization pass:

- Renamed the project to GlyphArc.
- Migrated state handling from Combine to Swift Observation.
- Updated the project for Swift 6.
- Improved overlay movement during scrolling and selection changes.
- Moved expensive Accessibility polling away from the UI path.
- Added safer concurrency boundaries around selection monitoring and AI work.
- Added cancellation for active AI work during panic wipe/reset flows.

## Requirements

- macOS
- Xcode with Swift 6 support
- Accessibility permission enabled for the app
