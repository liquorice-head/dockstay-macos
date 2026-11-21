# DockStay

- Keep the product to one native SwiftUI menu: a blocking toggle, live blocking status, display selection, live Accessibility permission status with a settings action, a Launch at Login toggle, Check for Updates, and Quit. No onboarding, dashboard, account, or paywall. Network functionality is limited to user-initiated Sparkle update checks and signed update downloads.
- Use documented public Apple APIs. Do not inject into Dock, load private frameworks, restart Dock, or change the user's system preferences.
- The user requested direct permission navigation: the Accessibility action may use the System Settings URL as a best-effort deep link, with the native permission prompt and the Settings app as fallbacks. Never grant permission automatically.
- Keep event processing on the main run loop, constant and short. Never subscribe to keyboard events. Never write files or query preferences inside the event callback.
- Use Quartz coordinates throughout pointer geometry. Preserve passages between adjacent monitors and fail open when the saved display is absent.
- Persist the display UUID rather than a transient CGDirectDisplayID or list index.
- Request Accessibility only after the user selects a display while blocking is enabled, enables blocking for a saved display, or explicitly opens permission settings. Disabled blocking must cancel pointer placement and event interception, including after sleep or reconnection. Keep the selected display and disabled state across launches.
- Run `swift test`, `bash scripts/build.sh`, and `git diff --check` before delivery. Hardware behavior needs a real multi-display check; report that limitation if unavailable.
- Write code, comments, documentation, and release notes in English. Localize the interface in English and Russian. Keep Russian translations in `Resources/ru.lproj/`.
