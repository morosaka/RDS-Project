# Phase 8c.6 — WaveformGenerator

**Date:** 2026-03-14  
**Status:** ✅ COMPLETED  
**Tests:** 12/12 passing (WaveformGeneratorTests.swift)  
**Build:** `swift build` clean

## Acceptance Criteria

- [x] Genera piramide a 5 livelli da audio Float32
- [x] vDSP usato per min/max a Level 0 (`vDSP_minv` / `vDSP_maxv`)
- [x] Output: `.waveform.gz` (lz4-compressed JSON, coerente con `.telemetry.gz`)
- [x] `peaksForViewport` seleziona livello ottimale
- [x] Integrato in pipeline di import (fire-and-forget dopo fusione)
- [x] 12 test (target: 5+)

## Files Changed

### WaveformPeaks.swift [NEW] v1.0.0
**Model:**
```swift
public struct PeakPair: Codable, Sendable, Hashable {
    public let min: Float
    public let max: Float
}

public struct WaveformPeaks: Codable, Sendable {
    public let sampleRate: Int
    public let totalSamples: Int
    public let levels: [[PeakPair]]
    public static let samplesPerBin: [Int] = [256, 1_024, 4_096, 16_384, 65_536]
}
```

**`peaksForViewport(viewportMs:widthPixels:)` algorithm:**
1. `samplesPerPixel = visibleSamples / widthPixels`
2. Itera livelli 0→4: tiene il più grossolano dove `samplesPerBin ≤ samplesPerPixel`
3. Calcola `startBin`/`endBin` dalla finestra temporale
4. Ritorna `(levelIndex, levels[levelIndex][startBin..<endBin])`
- Scelta: livello più grossolano che dà ≤1 bin per pixel → rendering efficiente

### WaveformGenerator.swift [NEW] v1.0.0
**Due metodi pubblici:**

```swift
// Full pipeline (AVFoundation + I/O) — usato in produzione
static func generate(from videoURL: URL, outputDir: URL) async throws -> URL

// Pure kernel (no I/O) — testabile con buffer sintetico
static func build(from samples: ContiguousArray<Float>, sampleRate: Int) -> WaveformPeaks
```

**Pipeline `build`:**
- Level 0: blocchi di 256 campioni → `vDSP_minv` + `vDSP_maxv` (Accelerate)
- Levels 1–4: `deriveLevel(from:)` → min-di-min / max-di-max su gruppi di 4 bin
- Tail handling: bin incompleto in fondo a ogni livello

**Pipeline `generate`:**
- `AVAsset` → `loadTracks(withMediaType: .audio)` via DispatchSemaphore (sync su background thread)
- `AVAssetReaderTrackOutput` settings: mono, Float32 32-bit, non-interleaved
- Sample rate rilevato da `CMAudioFormatDescriptionGetStreamBasicDescription`
- Loop `copyNextSampleBuffer()` → append Float32 via `CMBlockBufferGetDataPointer`
- `JSONEncoder` + `.lz4` compress → write atomic

**`load(from:)` utility:** decomprime + decodifica un sidecar esistente.

**Naming:** `{videoBasename}.waveform.gz` (es. `GX030230.waveform.gz`)

### FileImportHelper.swift — integrazione
Aggiunto dopo l'update del DataContext:
```swift
let outputDir = videoURL.deletingLastPathComponent()
Task.detached(priority: .background) {
    _ = try? await WaveformGenerator.generate(from: videoURL, outputDir: outputDir)
}
```
Fire-and-forget: la pipeline principale non attende il waveform. Il sidecar appare su disco in background. Errori ignorati silenziosamente (il waveform è opzionale per il rendering).

### WaveformGeneratorTests.swift [NEW] — 12 test
```
✔ Level 0 has correct number of bins for exact multiple
✔ Level 0 has ceil bins when sample count is not a multiple of 256
✔ Level 0 min is <= 0 and max >= 0 for sine wave
✔ Level 0 max is ~1.0 for a full-amplitude sine wave bin
✔ Level 1 count is ¼ of level 0 count (for exact multiples of 4)
✔ Level 1 min is <= minimum of its 4 source bins
✔ WaveformPeaks stores correct sampleRate and totalSamples
✔ peaksForViewport selects level 0 (finest) when zoomed in
✔ peaksForViewport selects coarser level when zoomed out
✔ peaksForViewport clips to visible time range
✔ PeakPair Codable round-trip
✔ WaveformPeaks Codable round-trip preserves all levels
```

## Decisioni Architetturali

**`build()` separato da `generate()`:** Separation of concerns — il kernel di calcolo è testabile con dati sintetici senza richiedere un file MP4. Pattern identico a `SidecarGenerator` dove l'estrazione GPMF è separata dalla scrittura su disco.

**lz4 invece di gzip:** SidecarGenerator usa `.lz4` (non vera gzip). WaveformGenerator segue la stessa convenzione per coerenza, anche se l'estensione è `.gz`. lz4 è più veloce in decompressione (importante per il rendering audio).

**Fire-and-forget in FileImportHelper:** Il waveform sidecar non è critico per la sessione (si usa come ottimizzazione del rendering audio). Lanciarlo in background con `priority: .background` e silenziare gli errori è l'approccio corretto — se il video non ha audio, nessun problema.

**DispatchSemaphore per loadTracks:** `AVAsset.loadTracks` usa una completion closure sul thread chiamante. Poiché siamo già su un Task background detached, un semaphore è sicuro e più semplice che gestire continuation.

## Next: 8c.7 — AudioTrackWidget (dipende da 8c.6 e 8c.8)

---

Completed by: Claude Sonnet 4.6  
Model: claude-sonnet-4-6
