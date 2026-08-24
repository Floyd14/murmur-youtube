# Working on WisperClone

## Product contract

WisperClone is a native macOS 26 push-to-talk dictation app. Hold the configured modifier, speak, release, and the cleaned transcript is inserted into the focused text field.

The production path is local-only. Do not add cloud transcription, remote cleanup, transcript analytics, or integrations with other dictation apps without an explicit product decision and privacy review. Audio and transcripts must not be persisted or logged.

## Verified commands

The active developer directory may point to Command Line Tools. Prefer a per-command override instead of changing the machine globally:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test \
  --scratch-path "$HOME/Library/Caches/WisperCloneBuild/tests"
```

The Makefile deliberately keeps build products in `~/Library/Caches/WisperCloneBuild` and assembles the app there.

## Load-bearing macOS behavior

- `HUDPanel` must remain a `.nonactivatingPanel` with `canBecomeKey == false`, otherwise dictation loses its insertion target.
- The held modifier requires a `CGEventTap`; Carbon and global `NSEvent` monitors do not reliably expose fn or left/right key-up behavior.
- Audio buffers from `AVAudioEngine` are borrowed and recycled. Copy them before crossing the callback boundary.
- Audio reaches the transcription actor through one ordered `AsyncStream` drain. Do not spawn one unstructured task per buffer.
- Accessibility writes can report success while doing nothing. Keep the caret-movement verification before falling back to clipboard paste.
- TCC grants depend on bundle identity and code-signing requirements. Keep `com.andreavisini.wisperclone.app`, the executable name, install path, and signing strategy stable.
- `MainActor.assumeIsolated` asserts rather than checks. Use it only where execution on the main thread is guaranteed.

## Language behavior

Italian is the default. Automatic uses `Locale.current`; English is explicit `en-US`. Never silently fall back from an unsupported requested locale to English.

Rule-based cleanup must remain deterministic and covered by `WisperFormattingTests`. Dictionary behavior is covered by `WisperDictionaryTests`, including Unicode normalization and regex edge cases.

## Design

`Sources/WisperClone/UI/DesignSystem.swift` owns reusable visual tokens and `UI/Brand.swift` owns the WisperClone identity. Red means recording; amber and green are instrumentation only. Keep the icon generator and in-app mark visually aligned, with no gradients.

## Manual checks

No automated test can prove microphone capture, a physical modifier key, TCC state, focus retention, or insertion into another process. After material changes, install the signed app and test one short Italian dictation in TextEdit, Note, a browser, and an Electron editor.
