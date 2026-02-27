# CODEBUDDY.md

This file provides guidance to CodeBuddy Code when working with code in this repository.

## Project Overview

**Porthole** is an iOS app built with Swift/SwiftUI that helps reduce phone addiction by displaying ambient information in Picture-in-Picture (PiP) floating windows. The app renders various content types (time, timers, camera feed, cat companion) as real-time video streams in PiP windows, allowing users to stay aware of time and surroundings while using other apps.

**Key Architecture**:
- **Protocol-Oriented Design**: `PiPContentProvider` protocol unifies content providers
- **UIView-to-Video Conversion**: `ViewToVideoStreamConverter` renders UIViews to AVSampleBufferDisplayLayer
- **Centralized Management**: `PiPManager` handles PiP lifecycle and user controls
- **Data Persistence**: SwiftData models (`DisplaySession`, `CardInstance`) track usage locally
- **Background Execution**: VoIP mode enables continuous camera streaming in PiP

## Development Commands

### Building and Running
```bash
# Build for simulator
xcodebuild -scheme Porthole -destination 'platform=iOS Simulator,name=iPhone 16' build

# Clean build
xcodebuild -scheme Porthole clean

# Run tests
xcodebuild -scheme Porthole -destination 'platform=iOS Simulator,name=iPhone 16' test
```

### Testing
- **Unit Tests**: `PortholeTests` target uses XCTest
- **UI Tests**: `PortholeUITests` target uses XCTest
- Tests are run through Xcode; no external test runners

## Codebase Structure

```
Porthole/                          # iOS Xcode project
├── Porthole.xcodeproj/            # Xcode project file
├── Porthole/                      # Main app source
│   ├── PortholeApp.swift          @main entry with SwiftData container
│   ├── ContentView.swift          # Root view (HomeView)
│   ├── Providers/                 # PiP content providers
│   ├── Services/                  # Core services (PiPManager, ViewToVideoStreamConverter, etc.)
│   ├── Models/                    # SwiftData models
│   ├── Views/                     # UI components
│   └── Protocols/                 # PiPContentProvider protocol
├── PortholeTests/                 # Unit tests
└── PortholeUITests/               # UI tests
```

## Key Technical Constraints

1. **Background Execution**: Requires VoIP background mode (`UIBackgroundModes` includes "voip") for camera streaming
2. **Performance**: Real-time UI-to-video conversion is resource-intensive; use dynamic frame rates
3. **Privacy**: All data stored locally; camera feeds never uploaded
4. **iOS Minimum**: 15.0+ (PiP API requirement)
5. **Dependencies**: No external packages; uses built-in iOS frameworks only

## Development Guidelines

### Code References
- Use `file.ts:42` format for code locations

## Common Paths

- **iOS Source**: `/Users/zyy/develop/Guxi11/juezhi/Porthole/Porthole/`
