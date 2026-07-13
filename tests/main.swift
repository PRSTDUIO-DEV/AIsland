// AIsland unit tests — pure helper functions only (no app/bundle state).
// Run: ./tests/run.sh
import Foundation

var failures = 0
func expect(_ condition: Bool, _ name: String) {
    if condition {
        print("  ok  \(name)")
    } else {
        print("FAIL  \(name)")
        failures += 1
    }
}

// parseISO
expect(parseISO("2026-07-13T05:19:59.509805+00:00") != nil, "parseISO 6-digit fraction")
expect(parseISO("2026-07-13T05:19:59.509+00:00") != nil, "parseISO 3-digit fraction")
expect(parseISO("2026-07-13T05:19:59+00:00") != nil, "parseISO no fraction")
expect(parseISO("garbage") == nil, "parseISO garbage → nil")
expect(parseISO(nil) == nil, "parseISO nil → nil")

// resetText
expect(resetText(Date().addingTimeInterval(-5)) == "resetting…", "resetText past → resetting")
expect(resetText(Date().addingTimeInterval(310)).hasPrefix("resets 5m"), "resetText <10m has seconds")
expect(resetText(Date().addingTimeInterval(310)).contains("s"), "resetText <10m s-suffix")
expect(resetText(Date().addingTimeInterval(2 * 3600 + 300)).hasPrefix("resets 2h"), "resetText hours")
expect(resetText(Date().addingTimeInterval(3 * 86_400 + 3700)).hasPrefix("resets 3d"), "resetText days")
expect(resetText(nil) == "", "resetText nil → empty")

// agoText
expect(agoText(nil) == "syncing…", "agoText nil → syncing")
expect(agoText(Date().addingTimeInterval(-3)) == "synced just now", "agoText now")
expect(agoText(Date().addingTimeInterval(-45)) == "synced 45s ago", "agoText seconds")
expect(agoText(Date().addingTimeInterval(-95)) == "synced 1m 35s ago", "agoText m+s under 10m")
expect(agoText(Date().addingTimeInterval(-2 * 86_400)) == "synced 2d ago", "agoText days")

// retryText
expect(retryText(nil) == "", "retryText nil → empty")
expect(retryText(Date().addingTimeInterval(-1)) == " · retrying…", "retryText past")
expect(retryText(Date().addingTimeInterval(61)).contains("retry in"), "retryText future countdown")

// tokenText
expect(tokenText(1_684_107) == "1.7M", "tokenText millions")
expect(tokenText(950_000) == "950k", "tokenText thousands")
expect(tokenText(500) == "500", "tokenText raw")

// isNewer (update check)
expect(UsageModel.isNewer("v1.6.1", than: "1.6.0"), "isNewer patch bump")
expect(UsageModel.isNewer("v2.0", than: "1.9.9"), "isNewer major bump")
expect(!UsageModel.isNewer("v1.6.0", than: "1.6.0"), "isNewer equal → false")
expect(!UsageModel.isNewer("v1.5.9", than: "1.6.0"), "isNewer older → false")
expect(!UsageModel.isNewer("vgarbage", than: "1.6.0"), "isNewer garbage → false")

if failures > 0 {
    print("\n\(failures) test(s) FAILED")
    exit(1)
}
print("\nALL TESTS PASSED")
