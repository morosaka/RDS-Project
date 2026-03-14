# Phase 8c.8 — VideoWidget Audio Stripping
**Date:** 2026-03-14
**Status:** Complete
**Complexity:** S

---

## Objective

Mute the AVPlayer in VideoWidget by default, completing the video/audio separation
design (§3 of vision doc). Audio rendering is now the responsibility of
`AudioTrackWidget` (8c.7). VideoWidget remains video-only.

---

## Files Changed

### [MODIFY] `Sources/RowDataStudio/Rendering/Widgets/VideoWidget.swift` v1.2.0 → v1.3.0

Added `syncController.player.isMuted = true` at the start of the `.task` block,
before `syncController.bind(to: playheadController)`:

```
.task {
    // Mute AVPlayer: audio separation — AudioTrackWidget owns audio rendering.
    // AVFoundation still decodes audio internally for A/V sync accuracy.
    syncController.player.isMuted = true
    syncController.bind(to: playheadController)
}
```

**Why in `.task` (not in `VideoSyncController.init`):**
The plan specifies `[MODIFY] VideoWidget.swift` only. Placing it in the task is
consistent with the widget-owns-its-configuration principle: VideoWidget knows
it operates in audio-separated mode; VideoSyncController remains reusable in
contexts where audio might be desired.

**Why AVFoundation still decodes audio:**
`player.isMuted = true` only suppresses audio output. AVFoundation's internal
A/V demuxer and decoder still process the audio track — this is intentional
because AVPlayer uses the audio presentation timestamps to maintain frame-accurate
video synchronisation. Disabling audio decoding entirely (by stripping the audio
track from the AVPlayerItem) would degrade video sync accuracy.

### [MODIFY] `Tests/RowDataStudioTests/VideoSyncControllerTests.swift`

Added 2 tests in `// MARK: - Phase 8c.8: Audio stripping`:

| Test | What is verified |
|---|---|
| `playerMutedDefaultFalse` | `VideoSyncController.player.isMuted == false` out of the box (muting is VideoWidget's responsibility, not the controller's) |
| `playerMutedApiWritable` | `player.isMuted = true` → `player.isMuted == true` (the AVPlayer API used by VideoWidget is writable and effective) |

---

## Architecture Notes

### Video / Audio separation model (Phase 8c)

| Widget | Responsibility |
|---|---|
| `VideoWidget` | Video frame rendering, A/V sync (muted output) |
| `AudioTrackWidget` | Waveform visualisation, volume/mute UI state |
| `WaveformGenerator` | Generates `.waveform.gz` sidecar (peak pyramid) |
| `AVAudioPlayerNode` | Actual audio playback (post-MVP) |

For Phase 8, AudioTrackWidget is visualisation-only (no live audio output).
Volume/mute state is persisted only in `@State` within the widget — not yet
wired to DataContext or to an AVAudioPlayerNode.

---

## Test Results

```
✔ 17/17 VideoSyncController tests passed (15 pre-existing + 2 new)
Build complete — no errors
```
