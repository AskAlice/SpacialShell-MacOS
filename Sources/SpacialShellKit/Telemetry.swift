import OpenTelemetryApi

/// #148: where Kit's spans come from. Kit sees the OpenTelemetry *API* only: until the app registers
/// the SDK the global provider is a no-op, so with telemetry off a span costs a few allocations and
/// nothing leaves the machine.
///
/// Privacy rule for every span in the shell: attributes are bundle ids, window ids, display ids,
/// counts and durations. Never a window title — titles carry document names, URLs, message subjects.
public enum Telemetry {
    public static let instrumentationName = "spacial-shell"

    /// Resolved per call, not captured: the app may register the SDK after a store is built, and
    /// the SDK caches its tracers, so a lookup is a dictionary hit.
    public static func tracer(_ provider: (any TracerProvider)? = nil) -> any Tracer {
        (provider ?? OpenTelemetry.instance.tracerProvider)
            .get(instrumentationName: instrumentationName, instrumentationVersion: SpacialShellKit.version)
    }
}
