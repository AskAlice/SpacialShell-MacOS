import Foundation

/// `SO_RCVTIMEO` for the socket tests: a hang detector, not a latency bound — a loaded machine can starve the server for seconds (#157).
let socketTestReceiveTimeout = timeval(tv_sec: 30, tv_usec: 0)
