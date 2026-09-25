// On-screen windows from the window server, as JSON. JXA's ObjC bridge reaches CoreGraphics
// without Apple Events, so this needs no Automation grant (owner names and bounds need no
// Screen Recording either — only window titles would).
ObjC.import('CoreGraphics');
function run() {
  const opts = $.kCGWindowListOptionOnScreenOnly | $.kCGWindowListExcludeDesktopElements;
  const list = ObjC.deepUnwrap(ObjC.castRefToObject($.CGWindowListCopyWindowInfo(opts, 0)));
  return JSON.stringify(list.map(w => ({
    owner: w.kCGWindowOwnerName, pid: w.kCGWindowOwnerPID, id: w.kCGWindowNumber,
    layer: w.kCGWindowLayer, alpha: w.kCGWindowAlpha, b: w.kCGWindowBounds,
  })));
}
