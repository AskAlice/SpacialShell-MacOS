// appearance dark|light — switches the whole session's appearance, as System Settings does (#81).
// `defaults write -g AppleInterfaceStyle Dark` alone changes nothing until the next login; the
// switch itself is SkyLight's, reached here by name since it is not public API.
import Foundation

let args = CommandLine.arguments
guard args.count == 2, ["dark", "light"].contains(args[1]) else {
    fputs("usage: appearance dark|light\n", stderr); exit(2)
}
guard let sl = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
      let sym = dlsym(sl, "SLSSetAppearanceThemeLegacy") else {
    fputs("appearance: SLSSetAppearanceThemeLegacy not found\n", stderr); exit(3)
}
typealias SetTheme = @convention(c) (Bool) -> Void
unsafeBitCast(sym, to: SetTheme.self)(args[1] == "dark")
