// Adapted from AeroSpace (MIT) — Sources/AppBundle/util/AxSubscription.swift @ c548c7f
import AppKit

/// The subscription is active as long as you keep this class in memory
final class AxSubscription {
    let obs: AXObserver
    let ax: AXUIElement
    let axThreadToken: AxAppThreadToken = axTaskLocalAppThreadToken ?? dieT("axTaskLocalAppThreadToken is not initialized")
    var notifKeys: Set<String> = []

    private init(obs: AXObserver, ax: AXUIElement) {
        axThreadToken.checkEquals(axTaskLocalAppThreadToken)
        self.obs = obs
        self.ax = ax
    }

    // SpacialShell deviation: the original returned `Bool`. We need the raw `AXError` because
    // apps routinely answer `kAXErrorCannotComplete` for a beat right after launch, and that
    // case is retried with backoff instead of costing the app its observers for good.
    private func subscribe(_ key: String) throws -> AXError {
        axThreadToken.checkEquals(axTaskLocalAppThreadToken)
        let err = AXObserverAddNotification(obs, ax, key as CFString, nil)
        if err == .success { notifKeys.insert(key) }
        return err
    }

    /// SpacialShell deviation: the original returned `[AxSubscription]` and used an empty array
    /// to mean "failed". We return the failing `AXError` instead so the caller can tell a
    /// transient `kAXErrorCannotComplete` from a permanent refusal (see `AXApp`).
    /// (`AXError` doesn't conform to `Error`, hence the bespoke enum rather than `Result`.)
    static func bulkSubscribe(
        _ nsApp: NSRunningApplication,
        _ ax: AXUIElement,
        _ job: RunLoopJob,
        _ handlerToNotifKeyMapping: HandlerToNotifKeyMapping,
    ) throws -> AxSubscribeResult {
        var result: [AxSubscription] = []
        var visitedNotifKeys: Set<String> = []
        for (handler, notifKeys) in handlerToNotifKeyMapping {
            try job.checkCancellation()
            guard let obs = AXObserver.new(nsApp.processIdentifier, handler) else { return .failed(.failure) }
            let subscription = AxSubscription(obs: obs, ax: ax)
            for key: String in notifKeys {
                try job.checkCancellation()
                assert(visitedNotifKeys.insert(key).inserted)
                let err = try subscription.subscribe(key)
                if err != .success { return .failed(err) }
            }
            CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(obs), .defaultMode)
            result.append(subscription)
        }
        return .subscribed(result)
    }

    deinit {
        axThreadToken.checkEquals(axTaskLocalAppThreadToken)
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(obs), .defaultMode)
        for notifKey in notifKeys {
            AXObserverRemoveNotification(obs, ax, notifKey as CFString)
        }
    }
}

typealias HandlerToNotifKeyMapping = [(AXObserverCallback, [String])]

/// SpacialShell addition — see `AxSubscription.bulkSubscribe`.
enum AxSubscribeResult {
    case subscribed([AxSubscription])
    case failed(AXError)
}
