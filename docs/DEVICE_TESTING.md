# Device acceptance and release checklist

Status: experimental; complete this checklist on the exact source revision and
physical devices being evaluated before declaring a stable release. Automated
tests and compilation are not substitutes for these checks. Keep device serials,
UDIDs, pairing secrets, signing profiles and personal screenshots out of reports.
Use Calculator or an unsent Notes draft for input tests.

## Setup

- [ ] Record source revision, OS versions and device model names (no unique IDs).
- [ ] Build from a clean checkout using your own iOS signing team.
- [ ] Exercise Bluetooth, QR camera and Local Network permission denial/recovery.
- [ ] Scan QR, complete OS Bluetooth pairing and enable AssistiveTouch.
- [ ] Verify companion setup versus actual mouse and keyboard subscriptions.
- [ ] Confirm wrong/forgotten QR identities cannot authorize setup.
- [ ] Confirm multiple fully subscribed HID hosts disable control.

## Input

- [ ] First pad click captures without tapping iPhone.
- [ ] Test pointer position at corners, edges and center; record accuracy/latency.
- [ ] Test clicks, double clicks, held drag, four-direction swipes and scrolling.
- [ ] Verify Mac pointer confinement and repeatable Esc release/resume.
- [ ] Type uppercase/lowercase, punctuation, backspace, arrows and modifiers.
- [ ] Esc/focus loss during held keys or dragging releases all input.
- [ ] Resize, close, sleep and transport loss safely release local capture.
- [ ] Record system pointer appearance/auto-hide; immediate phone-pointer hiding
      on Esc is not implemented and must not be represented as passing.

## Wireless and USB view

- [ ] Blank pad remains default; test input with USB disconnected.
- [ ] Start Wi-Fi viewing on the same network and approve system sharing on iPhone.
- [ ] Cancelling sharing consent captures nothing and leaves input usable.
- [ ] Test Home Screen and other apps after leaving the companion.
- [ ] Verify 15 minutes of latency, quality, thermal and battery behavior.
- [ ] Verify capture, clicks, held drag and typing while viewing with USB unplugged.
- [ ] Temporarily lose Wi-Fi and restore; observe stream recovery during consent.
- [ ] Mac viewing OFF stops the connected sender and clears the displayed frame.
- [ ] iPhone/system stop clears Mac frames without disabling Bluetooth input.
- [ ] Record lock/unlock behavior; request new consent if the OS ends sharing.
- [ ] Test wrong pairing identity, permission denial and protected-content behavior.
- [ ] Select USB explicitly; check Trust, Camera permission and iPhone-only capture.
- [ ] Viewing OFF leaves no screen listener or capture session running.

## Lifecycle and release

- [ ] Test phone lock/unlock, app restarts, Mac restart, sleep and Bluetooth loss.
- [ ] Verify saved identity survives restart and Forget pairing invalidates setup.
- [ ] Test companion stop and Mac End session with held input.
- [ ] Record any Keychain prompts after rebuilding the ad-hoc Mac app.
- [ ] Resolve failures or document accepted limitations before claiming stability.
- [ ] Review third-party notices and source for private data.
- [ ] Choose distribution: source/Xcode installation or separately signed releases.
- [ ] Never distribute personal signing profiles, certificates or an owner-signed IPA.
- [ ] Use Developer ID/notarization for a production Mac release, or label it
      explicitly as a local development build.
- [ ] Update README with actual verified support and remaining limitations.

Portrait input only. No audio streaming, clipboard sync, arbitrary Unicode/emoji
injection, guaranteed permanent connections or pre-iOS-27 Wi-Fi screen viewing.
