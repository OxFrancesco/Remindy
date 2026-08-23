# Remindy

Super-minimal local-first reminder/goal app driven by NFC tags.

- **Local-first**: all data stored on-device via SwiftData. No network, no accounts.
- **NFC-driven**: link any ISO14443/MiFare/NTAG sticker (the common hobby tags) to a goal.
- Tap your iPhone on the linked tag -> goal checks off for today, streak updates, haptic fires.

## Requirements

- Xcode 26+ (built against the iOS 26 SDK)
- iOS 17.0+
- A **physical iPhone** for NFC reading (`NFCTagReaderSession` is unavailable on Simulator)

## Build

```sh
xcodegen generate   # only needed after editing project.yml
open Remindy.xcodeproj
```

Select your device + signing team, then Run. The NFC entitlement
(`com.apple.developer.nfc.readersession.formats = TAG`) is already configured,
along with `NFCReaderUsageDescription`.

## Usage

1. `+` -> name a goal -> optionally *Scan a tag* to link it -> Add.
2. NFC icon (top-left) -> hold phone near any linked tag -> matching goal completes for today.
3. Tapping an unlinked tag offers to create a new goal for it.
4. Checkmark button on each row toggles today manually; swipe to delete.

## Structure

```
Remindy/
├── RemindyApp.swift      # entry + model container
├── Goal.swift            # SwiftData model: title, tagID, completions, streak
├── NFCTagScanner.swift   # CoreNFC reader session wrapper + haptics
├── ContentView.swift     # goal list, scan-to-complete flow
└── AddGoalSheet.swift    # create goal + link tag
```
