# Visualization Architecture for RowData Studio (RDS)

**Date:** 2026-02-28
**Author:** Mauro Sacca + Claude (Sonnet 4.5)
**Status:** PROPOSAL — Native Swift/SwiftUI greenfield architecture

---

## 1. Context

RDS is a native Apple Swift/SwiftUI greenfield project for rowing analysis. **It has no compatibility constraints with RDL** (concluded TypeScript/web project). Architectural lessons from RDL are available as historical reference, but RDS can freely choose the best tools of the modern Apple ecosystem.

### 1.1 Key Visualization Requirements

- **200Hz sensor data** (60k+ samples per 5 minutes of telemetry)
- **60fps smooth rendering** without jank during scrubbing
- **Multi-widget infinite canvas** (14+ widget types simultaneously)
- **Real-time cursor tracking** synchronized across all widgets
- **Viewport culling** and downsampling (LTTB)
- **Dual-layer rendering** (static data + ephemeral cursor)

### 1.2 Patterns Confirmed from RDL (to Carry Over)

RDL validated these patterns in production with real data:

| Pattern | RDL Validation | RDS Implementation |
|---------|----------------|---------------------|
| **Custom rendering** | No library (Chart.js, Recharts, D3) handles 200Hz at 60fps | Native SwiftUI Canvas API |
| **LTTB downsampling** | Reduces 60k→2k samples preserving visual features | Algorithm ported to Swift via Accelerate |
| **Viewport culling** | Only data visible in the temporal range is processed | ViewportCull transform in pipeline |
| **Dual-layer rendering** | Static layer (grid+data) + ephemeral layer (cursor) | Canvas + separate CursorOverlay |
| **Adaptive smoothing** | SMA (wide zoom) → Gaussian (medium) → Savitzky-Golay (tight) | AdaptiveSmooth transform with switch on ZoomLevel |

---

## 2. Architectural Proposals

### 2.1 Option 1: SwiftUI Canvas + Accelerate (RECOMMENDED)

**Technology stack:**

```
SwiftUI Canvas API (iOS 15+, macOS 12+)
    ↓
Core Graphics (drawing primitives)
    ↓
Automatically Metal-backed (via .drawingGroup())
    ↓
Accelerate/vDSP (SIMD-optimized data transforms)
```

#### Widget Architecture

```swift
protocol Widget: Identifiable {
    var id: UUID { get }
    var config: WidgetConfig { get }

    func dataTransform(
        context: DataContext,
        viewport: TimeRange
    ) -> TransformedData

    func body(data: TransformedData) -> some View
}

struct LineChartWidget: Widget {
    var config: LineChartConfig

    func dataTransform(context: DataContext, viewport: TimeRange) -> LineData {
        let samples = context.sensorBuffers.accelerometer.surge
        let indices = viewport.indices(in: context.timestamps)

        // LTTB downsampling using Accelerate
        let downsampled = LTTB.downsample(
            samples[indices],
            targetPoints: config.maxPoints
        )

        // Adaptive smoothing
        let smoothed = switch config.zoom {
            case .wide: vDSP.movingAverage(downsampled, window: 10)
            case .medium: gaussianSmooth(downsampled, sigma: 4)
            case .tight: savitzkyGolay(downsampled, window: 15, order: 3)
        }

        return LineData(points: smoothed)
    }

    var body: some View {
        Canvas { context, size in
            // Static layer: grid + data
            let path = linePath(from: data.points, size: size)
            context.stroke(path, with: .color(config.color), lineWidth: config.lineWidth)

            // Cursor layer is managed by the CanvasController
        }
        .drawingGroup() // Automatic Metal-backed rendering
        .gesture(dragGesture) // Scrubbing
    }
}
```

#### Global Cursor Management

```swift
@Observable
final class PlayheadController {
    var currentTime: TimeInterval = 0.0
    var isPlaying: Bool = false
    var playbackRate: Double = 1.0

    // Publisher for real-time updates (60fps)
    private var displayLink: CADisplayLink?

    func startPlayback() {
        displayLink = CADisplayLink(target: self, selector: #selector(tick))
        displayLink?.add(to: .main, forMode: .common)
    }

    @objc private func tick() {
        currentTime += 1.0 / 60.0 * playbackRate
        // All widgets with @ObservedObject update automatically
    }
}

struct RowingCanvas: View {
    @State private var playhead = PlayheadController()
    @State private var widgets: [any Widget] = []

    var body: some View {
        ZStack {
            // Widget layer (static data)
            ForEach(widgets, id: \.id) { widget in
                widget.body(
                    data: widget.dataTransform(
                        context: dataContext,
                        viewport: viewportFor(playhead.currentTime)
                    )
                )
                .position(widget.config.position)
                .frame(width: widget.config.size.width,
                       height: widget.config.size.height)
            }

            // Cursor overlay layer (ephemeral)
            CursorOverlay(playhead: playhead)
                .allowsHitTesting(false) // Click passes through
        }
        .environment(playhead) // Available to all widgets
    }
}
```

#### Pros and Cons

**Pros:**
- ✅ **Apple Native**: Official API, optimized for performance
- ✅ **Declarative**: Testable (validate the data model, not the pixels)
- ✅ **Automatic Metal**: `.drawingGroup()` uses Metal underneath when needed
- ✅ **SwiftUI Integration**: Gestures, animations, layout engine for free
- ✅ **Maintainability**: Clean code, type-safe, no complex shaders
- ✅ **Composability**: Widget = View → easily composable
- ✅ **Debugging**: Xcode Preview, View Inspector work

**Cons:**
- ⚠️ Requires iOS 15+ / macOS 12+ (acceptable for 2026 MVP)
- ⚠️ Less fine-grained control vs pure Metal (but sufficient for 200Hz)

---

## 2.2 Option 2: Layer Architecture with Composability

**Architecture with reusable layers:**

```swift
// Layer = composable unit of processing or rendering
protocol DataLayer {
    associatedtype Input
    associatedtype Output

    func transform(_ input: Input) -> Output
}

protocol RenderLayer {
    func render(in context: GraphicsContext, bounds: CGRect)
}

// Reusable layers
struct DownsamplingLayer: DataLayer {
    let targetPoints: Int

    func transform(_ input: [Float]) -> [Float] {
        LTTB.downsample(input, targetPoints: targetPoints)
    }
}

struct GaussianSmoothLayer: DataLayer {
    let sigma: Double

    func transform(_ input: [Float]) -> [Float] {
        gaussianSmooth(input, sigma: sigma)
    }
}

struct LineRenderLayer: RenderLayer {
    let points: [CGPoint]
    let color: Color

    func render(in context: GraphicsContext, bounds: CGRect) {
        let path = Path { p in
            p.addLines(points)
        }
        context.stroke(path, with: .color(color))
    }
}

// Widget = composition of layers
struct ComposableLineChart: Widget {
    let dataLayers: [any DataLayer]
    let renderLayers: [any RenderLayer]

    var body: some View {
        Canvas { context, size in
            // Apply data transforms
            var data = rawData
            for layer in dataLayers {
                data = layer.transform(data) // Type erasure managed with AnyDataLayer
            }

            // Render
            for layer in renderLayers {
                layer.render(in: context, bounds: CGRect(origin: .zero, size: size))
            }
        }
        .drawingGroup()
    }
}

// Easy composition
let widget = ComposableLineChart(
    dataLayers: [
        ViewportCullingLayer(range: visibleRange),
        DownsamplingLayer(targetPoints: 2000),
        GaussianSmoothLayer(sigma: 4)
    ],
    renderLayers: [
        GridRenderLayer(divisions: 10),
        LineRenderLayer(points: processedPoints, color: .blue),
        ThresholdLineLayer(value: threshold, color: .red)
    ]
)
```

#### Pros and Cons

**Pros:**
- ✅ **Zero Duplication**: Smoothing written once, reused by all widgets
- ✅ **Testability**: Each layer testable independently
- ✅ **Extensibility**: New widgets = mix & match existing layers
- ✅ **Maintainability**: Change algorithm = 1 layer, not 14 widgets

**Cons:**
- ⚠️ Initial complexity: Type erasure for AnyDataLayer<Input, Output>
- ⚠️ Performance overhead from composition (mitigatable with caching)

---

## 2.3 Option 3: Pure Metal (NOT RECOMMENDED for MVP)

**Only for completeness - not recommended without profiling justification**

```swift
final class MetalChartRenderer {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let pipelineState: MTLRenderPipelineState

    func render(samples: [Float], to texture: MTLTexture) {
        let commandBuffer = commandQueue.makeCommandBuffer()!
        let encoder = commandBuffer.makeRenderCommandEncoder(/* ... */)!

        // Data buffer on GPU
        let vertexBuffer = device.makeBuffer(
            bytes: samples,
            length: samples.count * MemoryLayout<Float>.stride
        )

        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.drawPrimitives(type: .lineStrip, /* ... */)
        encoder.endEncoding()
        commandBuffer.commit()
    }
}
```

#### Pros and Cons

**Pros:**
- ✅ Theoretical maximum performance

**Cons:**
- ❌ 10x complexity vs SwiftUI Canvas
- ❌ Shader compilation, GPU memory management
- ❌ Difficult debugging (RenderDoc, Xcode GPU debugger)
- ❌ **Premature optimization** without profiling demonstrating need
- ❌ Maintainability: Metal expertise required for future changes

---

## 3. Final Recommendation: Option 1 + Layer Pattern (Hybrid)

**Strategy:**
1. **Core rendering**: SwiftUI Canvas API (Option 1)
2. **Data transforms**: Layer compositional pattern (Option 2)
3. **Pure Metal**: Only if profiling demonstrates bottleneck (Option 3 as fallback)

### 3.1 Concrete Architecture

```swift
// 1. Data Transform Pipeline (reusable, composable)
struct TransformPipeline {
    let stages: [any DataTransform]

    func execute(on data: [Float]) -> [Float] {
        stages.reduce(data) { $1.transform($0) }
    }
}

protocol DataTransform {
    func transform(_ input: [Float]) -> [Float]
}

struct ViewportCull: DataTransform {
    let timeRange: ClosedRange<TimeInterval>
    let timestamps: [TimeInterval]

    func transform(_ input: [Float]) -> [Float] {
        let indices = timestamps.indices(where: { timeRange.contains($0) })
        return Array(input[indices])
    }
}

struct LTTBDownsample: DataTransform {
    let targetPoints: Int

    func transform(_ input: [Float]) -> [Float] {
        LTTB.downsample(input, targetPoints: targetPoints)
    }
}

struct AdaptiveSmooth: DataTransform {
    let zoomLevel: ZoomLevel

    func transform(_ input: [Float]) -> [Float] {
        switch zoomLevel {
        case .wide: return vDSP.movingAverage(input, window: 10)
        case .medium: return gaussianSmooth(input, sigma: 4)
        case .tight: return savitzkyGolay(input, window: 15, order: 3)
        }
    }
}

// 2. Base Widget with Transform Pipeline
protocol ChartWidget: View {
    var pipeline: TransformPipeline { get }
    var renderConfig: RenderConfig { get }

    func render(data: [Float], in context: GraphicsContext, size: CGSize)
}

extension ChartWidget {
    var body: some View {
        Canvas { context, size in
            let rawData = fetchRawData() // From SensorDataBuffers SoA
            let transformed = pipeline.execute(on: rawData)
            render(data: transformed, in: context, size: size)
        }
        .drawingGroup() // Metal-backed
    }
}

// 3. Concrete Widgets (14+ types)
struct BasicLineChart: ChartWidget {
    var pipeline: TransformPipeline {
        TransformPipeline(stages: [
            ViewportCull(timeRange: viewport, timestamps: context.timestamps),
            LTTBDownsample(targetPoints: 2000),
            AdaptiveSmooth(zoomLevel: currentZoom)
        ])
    }

    func render(data: [Float], in context: GraphicsContext, size: CGSize) {
        let points = data.enumerated().map { idx, val in
            CGPoint(
                x: CGFloat(idx) / CGFloat(data.count) * size.width,
                y: size.height - (CGFloat(val) * size.height)
            )
        }

        let path = Path { p in
            p.addLines(points)
        }

        context.stroke(path, with: .color(renderConfig.color), lineWidth: 2)
    }
}

struct GradientLineChart: ChartWidget {
    var pipeline: TransformPipeline {
        // Same pipeline as BasicLine - ZERO DUPLICATION
        TransformPipeline(stages: [
            ViewportCull(timeRange: viewport, timestamps: context.timestamps),
            LTTBDownsample(targetPoints: 2000),
            AdaptiveSmooth(zoomLevel: currentZoom)
        ])
    }

    func render(data: [Float], in context: GraphicsContext, size: CGSize) {
        // Custom rendering with gradient
        let gradient = Gradient(colors: [.blue, .green, .yellow, .red])
        // ... gradient implementation based on values intensity
    }
}

// 4. Cursor Controller (single source of truth)
@Observable
final class PlayheadController {
    var currentTime: TimeInterval = 0.0
    var isPlaying: Bool = false

    private var displayLink: CADisplayLink?

    func startPlayback() {
        displayLink = CADisplayLink { [weak self] _ in
            self?.tick()
        }
        displayLink?.add(to: .main, forMode: .common)
    }

    private func tick() {
        currentTime += 1.0 / 60.0
    }
}

// 5. Infinite Canvas
struct RowingDeskCanvas: View {
    @State private var playhead = PlayheadController()
    @State private var widgets: [WidgetInstance] = []
    @State private var zoom: CGFloat = 1.0
    @State private var offset: CGPoint = .zero

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background grid
                GridView(zoom: zoom, offset: offset)

                // Widgets layer
                ForEach(widgets) { widget in
                    widget.view
                        .position(widget.position * zoom + offset)
                        .frame(width: widget.size.width * zoom,
                               height: widget.size.height * zoom)
                        .environment(playhead)
                }

                // Cursor overlay (ephemeral layer)
                CursorOverlay(time: playhead.currentTime)
                    .allowsHitTesting(false)
            }
            .gesture(
                MagnificationGesture()
                    .onChanged { zoom = $0 }
            )
            .gesture(
                DragGesture()
                    .onChanged { offset = $0.translation }
            )
        }
    }
}
```

### 3.2 Hybrid Architecture Benefits

| Aspect | Benefit |
|---------|-----------|
| **Performance** | SwiftUI Canvas + `.drawingGroup()` = Automatic Metal when needed |
| **Reusability** | Composable transform pipelines → zero duplicate smoothing/LTTB |
| **Testability** | Pure data transforms → easy unit tests; render validation via snapshot |
| **Maintainability** | SwiftUI declarative code, no custom shaders |
| **Extensibility** | New widgets = compose existing layers |
| **Debugging** | Xcode Preview, View Inspector, Instruments |
| **Type Safety** | Swift type system prevents errors at compile time |

---

## 4. Patterns Confirmed from RDL → Swift Port

| RDL Pattern | Swift Implementation |
|-------------|----------------------|
| **Dual-layer rendering** | Static Canvas + separate CursorOverlay (`allowsHitTesting: false`) |
| **LTTB downsampling** | Algorithm ported to Swift using Accelerate for SIMD |
| **Viewport culling** | `ViewportCull` transform in the pipeline |
| **Adaptive smoothing** | `AdaptiveSmooth` switch on ZoomLevel |
| **SoA buffers** | `ContiguousArray<Float>` or `UnsafeMutableBufferPointer<Float>` |
| **Playhead observable** | `@Observable` PlayheadController with CADisplayLink |

---

## 5. Critical Files to Create

```
RowingSuperApp/
├── app/
│   ├── Rendering/
│   │   ├── Transforms/
│   │   │   ├── DataTransform.swift          // Base protocol
│   │   │   ├── ViewportCull.swift
│   │   │   ├── LTTBDownsample.swift
│   │   │   ├── AdaptiveSmooth.swift
│   │   │   └── TransformPipeline.swift
│   │   │
│   │   ├── Widgets/
│   │   │   ├── ChartWidget.swift            // Base protocol
│   │   │   ├── BasicLineChart.swift
│   │   │   ├── GradientLineChart.swift
│   │   │   ├── AreaChart.swift
│   │   │   ├── PerStrokeBarChart.swift
│   │   │   ├── PhasePlaneChart.swift
│   │   │   ├── ScatterChart.swift
│   │   │   └── ... (14+ widget types)
│   │   │
│   │   ├── PlayheadController.swift         // Observable time controller
│   │   └── RowingDeskCanvas.swift           // Infinite canvas
│   │
│   └── SignalProcessing/                    // Port from RDL mathUtils.ts
│       ├── Accelerate+Extensions.swift
│       ├── LTTB.swift
│       ├── GaussianSmooth.swift
│       ├── SavitzkyGolay.swift
│       └── StrokeDetection.swift
```

---

## 6. Verification Plan

### 6.1 Performance Testing (Pre-MVP)

**Objective**: Validate that SwiftUI Canvas + `.drawingGroup()` reaches 60fps target

**Methodology**:
1. Benchmark SwiftUI Canvas vs pure Metal on real dataset (60k samples)
2. Measure frame time during continuous scrubbing with 10 simultaneous widgets
3. **Target**: <16ms per frame (60fps)
4. **Only if it fails**: Consider pure Metal (Option 3)

**Test setup**:
```swift
func testRenderingPerformance() {
    let samples = generateTestData(count: 60_000) // 5 min @ 200Hz
    let widgets = createWidgets(count: 10)

    measure(metrics: [XCTClockMetric()]) {
        for time in stride(from: 0, to: 300, by: 1.0/60.0) {
            widgets.forEach { widget in
                let data = widget.dataTransform(
                    context: testContext,
                    viewport: TimeRange(center: time, width: 30)
                )
                // Simulated rendering
            }
        }
    }
}
```

### 6.2 Composability Testing

**Objective**: Verify zero code duplication between widgets

**Test case**:
1. Create 3 widgets (BasicLine, GradientLine, Area) using shared pipeline
2. Modify `AdaptiveSmooth` (e.g. change Gaussian sigma)
3. Verify: change reflects in all widgets without individual modifications
4. Unit test: each isolated transform produces expected output

```swift
func testPipelineReuse() {
    let pipeline = TransformPipeline(stages: [
        LTTBDownsample(targetPoints: 2000),
        AdaptiveSmooth(zoomLevel: .medium)
    ])

    let widget1 = BasicLineChart(pipeline: pipeline)
    let widget2 = GradientLineChart(pipeline: pipeline)

    // Modify pipeline → both widgets updated
    pipeline.stages[1] = AdaptiveSmooth(zoomLevel: .tight)

    XCTAssertEqual(widget1.pipeline, widget2.pipeline)
}
```

### 6.3 Visual Rendering Testing

**Objective**: Visual validation of chart output

**Methodology**: Snapshot testing with `swift-snapshot-testing`

```swift
func testBasicLineChartSnapshot() {
    let widget = BasicLineChart(
        data: knownGoodDataset,
        config: LineChartConfig(color: .blue, lineWidth: 2)
    )

    assertSnapshot(matching: widget, as: .image(size: CGSize(width: 800, height: 400)))
}
```

**Comparison**: RDS output vs known-good dataset from RDL (PNG export for visual validation)

---

## 7. Open Questions

### 7.1 SoA Format in Swift

**Options**:
- `ContiguousArray<Float>`: Safer, ARC-managed, Swift-friendly API
- `UnsafeMutableBufferPointer<Float>`: Zero-copy with Accelerate, maximum performance

**Recommendation**: Start with `ContiguousArray<Float>` (safe). Migrate to `UnsafeMutableBufferPointer` only if profiling demonstrates bottleneck.

### 7.2 Transform Pipeline Caching

**Invalidation Strategy**:
- **Viewport change** → re-run `ViewportCull` + downstream transforms
- **Config change** (e.g. smoothing sigma) → re-run from that transform onwards
- **Raw data change** → re-run entire pipeline

**Implementation**:
```swift
struct CachedPipeline {
    private var cache: [CacheKey: [Float]] = [:]

    mutating func execute(on data: [Float], stages: [DataTransform]) -> [Float] {
        let key = CacheKey(dataHash: data.hashValue, stages: stages)
        if let cached = cache[key] {
            return cached
        }

        let result = stages.reduce(data) { $1.transform($0) }
        cache[key] = result
        return result
    }
}
```

### 7.3 Widget Persistence

**Format**: Codable JSON for config serialization

```swift
struct WidgetConfig: Codable {
    let type: WidgetType
    let position: CGPoint
    let size: CGSize
    let pipeline: TransformPipelineConfig
    let render: RenderConfig
}

// Saved in SessionDocument
struct SessionDocument: Codable {
    // ... other fields
    let canvasWidgets: [WidgetConfig]
}
```

### 7.4 Real-World Performance

**Test on target hardware**: iPad Pro M2 with 10 simultaneous widgets

**Metrics**:
- Frame time during scrubbing (target: <16ms)
- Memory footprint (60k samples × 10 widgets)
- Battery drain during 30-minute analysis session

---

## 8. Key Differences vs RDL

| Aspect | RDL (TypeScript/Web) | RDS (Swift/Native) |
|---------|----------------------|---------------------|
| **Rendering** | Manual 2D Canvas API | Declarative SwiftUI Canvas API |
| **Architecture** | Each Lens = isolated silo | Shared Transform Pipelines |
| **Code Duplication** | 14 smoothing implementations | 1 reused implementation |
| **Performance** | JavaScript TypedArray | Accelerate/vDSP SIMD-optimized |
| **Reactivity** | Combine/RxJS | Native @Observable |
| **Testing** | Manual snapshot testing | Swift Testing + Xcode Preview |
| **Metal** | Not available (limited WebGL) | Automatic via `.drawingGroup()` |
| **Type safety** | TypeScript (runtime errors possible) | Swift (compile-time guarantees) |

---

## 9. Conclusions

The proposed hybrid architecture (SwiftUI Canvas + Transform Pipeline) represents the optimal approach for RDS:

- **Leverages the modern Apple ecosystem** (SwiftUI, Accelerate, Metal)
- **Eliminates code duplication** compared to the RDL Lens pattern
- **Maintains validated patterns** (LTTB, dual-layer, viewport culling)
- **Balances performance and maintainability** (no premature pure Metal optimization)
- **Extensible for the future** (14+ widget types, custom user widgets)

**Next steps**:
1. BasicLineChart prototype with SwiftUI Canvas
2. Implement LTTB in Swift using Accelerate
3. Performance benchmark vs 60fps target
4. If benchmark passes → commit to hybrid architecture
5. If benchmark fails → evaluate pure Metal (Option 3)
