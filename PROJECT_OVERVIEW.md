# The Cursor — implementation overview

## Current implementation

Native Mac-to-iPhone Bluetooth HID pointer/keyboard with a proportional blank
pad. Optional USB viewing and encrypted local Wi-Fi viewing. Wi-Fi capture uses
user-approved ScreenCaptureKit on iOS 27+. Blank pad is the launch default.

## File map

- Sources/CursorCore: coordinates, HID reports, keyboard, pairing and screen framing.
- Sources/CursorDesign: shared visual theme, original mark and author profile link.
- Sources/TheCursor: Mac capture, Bluetooth peripheral, UI and screen receivers.
- iOS/TheCursorConnect: setup/QR UI, Bluetooth central and wireless screen sender.
- Tests: core input/protocol validation.
- scripts: reproducible builds, project generation and artwork rendering.
- Resources: original assets and app metadata.

## Validation

13 core tests previously passed. Mac and unsigned iOS builds pass locally;
physical pointer control, direct swiping and a wireless Home Screen stream have
been observed. Full physical acceptance and post-restart reliability are not
established. See docs/DEVICE_TESTING.md; never infer device compatibility from
compilation alone. CI results must be checked separately on GitHub.

## Known limitations

Experimental Bluetooth HID interoperability and possible stale GATT caches;
setup/HID identities not yet cryptographically correlated; portrait-only input;
OS-controlled pointer appearance/hiding; no audio/clipboard; no guaranteed
permanent connection. Ad-hoc Mac rebuilds may trigger Keychain prompts, and the
current initialization can wait on that prompt before displaying the window.

## Ordered next actions

1. Run the physical acceptance checklist and record non-sensitive results.
2. Resolve measured failures, especially reconnect, typing and long-running video.
3. Evaluate signing/distribution and a stable release only after acceptance.

Keep this overview synchronized with implementation changes. Preserve all
third-party notices. Public source availability does not establish stable support.

## SDK compatibility fix

Wireless capture is compiled only when the iOS ScreenCaptureKit module exists.
Older SDKs build the Bluetooth companion and show a clear availability card.
Xcode 27.2+ retains full wireless capture. CI with an older SDK does not validate
wireless capture; local iOS 27 compilation must also be checked.
