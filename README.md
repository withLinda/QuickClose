# QuickClose

A quiet macOS menu-bar utility for clearing your workspace in one click.

## Behavior

- Click the menu-bar power icon to open the compact QuickClose panel.
- `Quit All Apps` sends a normal quit request to every listed app, giving each app a chance to save work.
- Turn on `Background apps` to include non-regular apps in the list and quit request.
- A short system `Glass`/`Pop` sound confirms the action when sounds are enabled.
- Settings includes launch-at-login, sound, and background-app visibility.

QuickClose intentionally uses `NSRunningApplication.terminate()` rather than force-killing processes. macOS may refuse a quit request or an app may remain open while it saves work.

## Build

```sh
xcodebuild -project QuickClose.xcodeproj -scheme QuickClose -configuration Debug build
xcodebuild -project QuickClose.xcodeproj -scheme QuickClose test
```

The project targets macOS 15 and uses SwiftUI, `MenuBarExtra`, native Settings, and Swift 6 strict concurrency.
