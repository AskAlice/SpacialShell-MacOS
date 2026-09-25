import Darwin
import Foundation
import OpenTelemetryApi
import OpenTelemetryProtocolExporterCommon   // `OtlpConfiguration`; comes with the HTTP product
import OpenTelemetryProtocolExporterHttp
import OpenTelemetrySdk
import ResourceExtension
import SpacialShellKit
import os

/// #83: the OpenTelemetry SDK, registered only when `[telemetry]` is on *and* there is a credential
/// (`TelemetryConfig.export`). Otherwise nothing is registered, Kit's spans stay on the API's no-op
/// tracer, and nothing leaves the machine.
///
/// Spans are batched (one POST every few seconds at most, a bounded queue that drops rather than
/// grows), exported as OTLP/HTTP protobuf, and every export failure is a log line under `telemetry`,
/// never an error anywhere else.
///
/// No URLSession instrumentation, although the package has it: the shell makes no URLSession calls
/// (the launcher and every "open" go through `NSWorkspace`), so the only traffic it would trace is
/// this exporter's own — a span per export, exported by the next export.
enum Tracing {
    private static let log = Logger(subsystem: Paths.bundleID, category: "telemetry")
    /// Short, so a quit never waits long on a slow collector: the final flush is bounded by it.
    private static let exportTimeout: TimeInterval = 5

    /// Registers the SDK and returns the provider, to flush on quit; nil when telemetry is off.
    static func start(_ config: TelemetryConfig,
                      env: [String: String] = ProcessInfo.processInfo.environment) -> TracerProviderSdk? {
        guard let target = config.export(env: env) else {
            log.info("telemetry off")
            return nil
        }
        OpenTelemetry.registerFeedbackHandler { message in
            log.error("otel: \(message, privacy: .public)")
        }
        let exporter = OtlpHttpTraceExporter(
            endpoint: target.url,
            config: OtlpConfiguration(timeout: exportTimeout, headers: target.headers.map { ($0.key, $0.value) }),
            httpClient: LoggingHTTPClient(),
            // The exporter's own env parsing mangles Basic auth; `export(env:)` already read it.
            envVarHeaders: nil,
            // A failed batch is dropped, not re-queued behind the next one forever.
            requeueOnFailure: false)
        // The SDK's detection (app, OS, device model), then ours on top: a loose debug binary has
        // no bundle name, and the service is `spacial-shell` whatever the binary is called.
        let resource = DefaultResources().get().merging(other: Resource(attributes: [
            "service.name": .string(Telemetry.instrumentationName),
            "service.version": .string(SpacialShellKit.version),
            "host.name": .string(uname(\.nodename)),
            "host.arch": .string(uname(\.machine)),
            "os.type": .string("darwin"),
        ]))
        let provider = TracerProviderBuilder()
            .with(resource: resource)
            .add(spanProcessor: BatchSpanProcessor(spanExporter: exporter, exportTimeout: exportTimeout))
            .build()
        OpenTelemetry.registerTracerProvider(tracerProvider: provider)
        log.notice("telemetry on: exporting traces to \(target.url.absoluteString, privacy: .public)")
        return provider
    }

    /// `uname(3)`, not `ProcessInfo.hostName`, which can block on a reverse DNS lookup.
    private static func uname<T>(_ field: KeyPath<utsname, T>) -> String {
        var u = utsname()
        guard Darwin.uname(&u) == 0 else { return "" }
        return withUnsafeBytes(of: u[keyPath: field]) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }
}

/// The exporter's own client, plus the status line: the first success is logged at notice so a
/// fresh setup can be confirmed in `log show`, every later one at debug; every failure at error.
/// Never the request headers — they carry the token.
private final class LoggingHTTPClient: HTTPClient, @unchecked Sendable {
    private static let log = Logger(subsystem: Paths.bundleID, category: "telemetry")
    private let base = BaseHTTPClient()
    private let lock = NSLock()
    private var confirmed = false

    func send(request: URLRequest, completion: @escaping (Result<HTTPURLResponse, Error>) -> Void) {
        base.send(request: request) { result in
            self.note(result)
            completion(result)
        }
    }

    func send(request: URLRequest) async throws -> HTTPURLResponse {
        do {
            let r = try await base.send(request: request)
            note(.success(r)); return r
        } catch { note(.failure(error)); throw error }
    }

    private func note(_ result: Result<HTTPURLResponse, Error>) {
        switch result {
        case .success(let r):
            lock.lock(); let first = !confirmed; confirmed = true; lock.unlock()
            if first { Self.log.notice("export ok: HTTP \(r.statusCode)") } else { Self.log.debug("export ok: HTTP \(r.statusCode)") }
        case .failure(let e):
            Self.log.error("export failed: \(String(describing: e), privacy: .public)")
        }
    }
}
