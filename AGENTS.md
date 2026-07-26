# Wetools Code Constraints

## Global Naming Requirements

1. The project name is `Wetools`.
2. The app name is `Wetools`.
3. The scheme name is `Wetools`.
4. The default Xcode project is `Wetools.xcodeproj`.
5. If `Wetools.xcworkspace` exists, prefer the workspace over the project.
6. The app bundle is `Wetools.app`.
7. The local development install path is `/Applications/Wetools Dev.app`.
8. GitHub Release DMG files must use `Wetools-{version}.dmg`.
9. Bundle ID examples must use `com.yourname.Wetools` and include a TODO note to replace it with a real value.
10. Application Support data must be stored under `Wetools`.
11. README, scripts, GitHub Actions, and Release bodies must not mention any old project name.

## Code Quality Requirements

1. All core types must have clear responsibilities. Do not place broad application logic inside `AppDelegate`.
2. Separate UI, business logic, and persistence logic.
3. Use `ObservableObject` or `@Observable` to manage app state.
4. `AppSettings` must independently manage user configuration.
5. `ClipboardManager` must independently manage clipboard monitoring.
6. `ScreenshotManager` must independently manage the screenshot flow.
7. `ScreenRecordingManager` must independently manage the screen recording flow.
8. `PermissionManager` must independently manage permission checks.
9. `HotKeyManager` must independently manage global shortcuts.
10. The Store layer must independently handle JSON or file reads and writes.
11. All asynchronous operations must update UI state on the main thread.
12. Avoid strong reference cycles.
13. Add error handling for system APIs that can fail.

## Completion Report Requirements

After each implementation phase, list:

1. Added files.
2. Modified files.
3. How to run.
4. How to test.
5. Known limitations.
