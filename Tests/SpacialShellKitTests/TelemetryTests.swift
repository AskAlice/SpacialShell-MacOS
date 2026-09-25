import Testing
import Foundation
import InMemoryExporter
import OpenTelemetryApi
import OpenTelemetrySdk
@testable import SpacialShellKit

// The SDK provider locks internally but is not marked Sendable; the tests share one with a store.
extension TracerProviderSdk: @retroactive @unchecked Sendable {}

/// #83: the store's spans, read back through the SDK's in-memory exporter. Each test builds its own
/// provider and hands it to the store, so parallel tests never share the global one.
@Suite struct TelemetryTests {
    let d1 = DisplayInfo(id: "D1", frame: CGRect(x: 0, y: 0, width: 1000, height: 700), visibleFrame: CGRect(x: 0, y: 25, width: 1000, height: 675), isMain: true)
    let a = WindowRef(id: 1, pid: 1), b = WindowRef(id: 2, pid: 1)
    static let secret = "Quarterly layoffs draft"

    func snap(focused: WindowRef) -> Snapshot {
        let ws = [a, b].map {
            WindowSnapshot(ref: $0, frame: CGRect(x: 0, y: 0, width: 300, height: 200), title: Self.secret,
                           bundleID: "com.x", kind: .tile, parent: nil, isMinimized: false, isFullscreen: false, onActiveSpace: true)
        }
        return Snapshot(displays: [d1], apps: [AppInfo(pid: 1, bundleID: "com.x", isHidden: false)], windows: ws,
                        focused: focused, loginwindowFrontmost: false)
    }

    func make(animator: (any SwitchAnimator)? = nil) async -> (WorldStore, Spans, FakeBackend) {
        let exporter = InMemoryExporter()
        let provider = TracerProviderBuilder().add(spanProcessor: SimpleSpanProcessor(spanExporter: exporter)).build()
        let be = FakeBackend(snapshot: snap(focused: a))
        var c = Config(); c.showPanels = false; c.categoryOrder = []
        let store = WorldStore(backend: be, config: c, world: nil, zeroSliverBundleIDs: [], animator: animator,
                               tracerProvider: provider, onChange: { _ in })
        await store.start()
        return (store, Spans(provider: provider, exporter: exporter), be)
    }

    /// The simple processor exports on a queue of its own; flush before reading.
    struct Spans {
        let provider: TracerProviderSdk, exporter: InMemoryExporter
        func finished() -> [SpanData] { provider.forceFlush(); return exporter.getFinishedSpanItems() }
        func reset() { provider.forceFlush(); exporter.reset() }
    }

    func string(_ v: AttributeValue?) -> String? { if case .string(let s)? = v { s } else { nil } }
    func int(_ v: AttributeValue?) -> Int? { if case .int(let i)? = v { i } else { nil } }
    func bool(_ v: AttributeValue?) -> Bool? { if case .bool(let x)? = v { x } else { nil } }

    @Test func aCommandIsOneTraceWithReconcileWritesAndRaise() async throws {
        let (store, exporter, _) = await make()
        exporter.reset()
        await store.run(.focusWindow(.right))
        let spans = exporter.finished()

        let command = try #require(spans.first { $0.name == "command" })
        #expect(command.parentSpanId == nil)
        #expect(string(command.attributes["command"]) == "focusWindow")
        let reconcile = try #require(spans.first { $0.name == "reconcile" })
        #expect(reconcile.parentSpanId == command.spanId && reconcile.traceId == command.traceId)
        #expect(bool(reconcile.attributes["superseded"]) == false)
        let writes = try #require(spans.first { $0.name == "reconcile.writes" })
        #expect(writes.parentSpanId == reconcile.spanId)
        #expect((int(writes.attributes["frames"]) ?? 0) + (int(writes.attributes["parks"]) ?? 0) > 0)
        let raise = try #require(spans.first { $0.name == "reconcile.raise" })
        #expect(raise.parentSpanId == reconcile.spanId)
        #expect(int(raise.attributes["window.id"]) == Int(b.id))
        #expect(string(raise.attributes["bundle.id"]) == "com.x")
        // Counts, not a span per window: one pass is exactly these four.
        #expect(spans.count == 4)
    }

    @Test func noSpanEverCarriesAWindowTitle() async {
        let (store, exporter, _) = await make()
        await store.run(.focusWindow(.right))
        await store.apply(.snapshot(snap(focused: b)))
        let spans = exporter.finished()
        #expect(!spans.isEmpty)
        for s in spans {
            #expect(!s.attributes.keys.contains { $0.localizedCaseInsensitiveContains("title") }, "\(s.name)")
            #expect(!s.attributes.values.contains { "\($0)".contains(Self.secret) }, "\(s.name)")
        }
    }

    @Test func aSnapshotCarriesItsAdoptionsAndParentsItsReconcile() async throws {
        let (_, exporter, _) = await make()
        let spans = exporter.finished()
        let snapshot = try #require(spans.first { $0.name == "snapshot" })
        #expect(int(snapshot.attributes["adopted"]) == 2)
        #expect(int(snapshot.attributes["windows"]) == 2)
        #expect(spans.contains { $0.name == "reconcile" && $0.parentSpanId == snapshot.spanId })
    }

    /// A pass a newer one overtakes mid-switch still ends its span, marked `superseded`; the
    /// animator is handed that pass's context, so the overlay's spans land in the same trace.
    @Test func aSupersededPassIsMarkedAndTheAnimatorGetsItsContext() async throws {
        let recorder = ContextRecorder()
        let (store, exporter, _) = await make(animator: recorder)
        exporter.reset()
        await recorder.setDuringPrepare { await store.run(.toggleOverview) }
        await store.run(.focusWindow(.right))
        let passes = exporter.finished().filter { $0.name == "reconcile" }
        #expect(passes.count == 2)
        let outer = try #require(passes.first { bool($0.attributes["superseded"]) == true })
        #expect(passes.contains { bool($0.attributes["superseded"]) == false })
        #expect(await recorder.prepared.first == outer.spanId)
    }

    actor ContextRecorder: SwitchAnimator {
        var prepared: [SpanId] = []
        var duringPrepare: (@Sendable () async -> Void)?
        func setDuringPrepare(_ f: @escaping @Sendable () async -> Void) { duringPrepare = f }
        func prepare(_ t: [Transition], trace: SpanContext?) async -> Bool {
            if let trace { prepared.append(trace.spanId) }
            if let f = duringPrepare { duringPrepare = nil; await f() }
            return true
        }
        func play(trace: SpanContext?) async {}
    }
}
