// Adapted from AeroSpace (MIT) — Sources/Common/util/Nullable.swift @ c548c7f
/// Like Swift's built-in Optional but avoids implicit nil coercions
public enum Nullable<T> {
    case just(T)
    case null

    public var valueOrNil: T? {
        switch self {
            case .just(let value): value
            case .null: nil
        }
    }

    public var isNull: Bool { valueOrNil == nil }
}
