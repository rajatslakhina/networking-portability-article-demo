# Networking Portability — article demo

A small, runnable Swift package that answers one question with a number instead of a vibe:

> **If a second HTTP stack shows up, how much of your app actually moves?**

The [Swift Networking workgroup](https://www.swift.org/blog/announcing-networking-workgroup/) was
announced in June 2026 to build a unified networking stack — shared I/O primitives, common protocol
implementations, and a modern HTTP client/server API. The reflex response on every iOS team is
"we're fine, we hid `URLSession` behind a protocol."

This repo is the argument that the protocol is measuring the wrong thing.

**Article:** *(added after publish — see below)*

---

## What it actually does

`PortabilityCore` models an app's networking dependence as a **capability inventory** and scores it.

Every capability is classified by where it lives in the layered stack the workgroup described:

| Class | Ports? | Weight | Examples |
|---|---|---|---|
| `.currencyType` | free | 1 | request/response values, URL encoding, JSON coding |
| `.protocolLayer` | with work | 4 | TLS trust, HTTP/2 multiplexing, WebSocket framing |
| `.platformService` | **no** | 16 | shared cookie jar, credential store, background transfer, `URLCache`, task metrics |

![Three-band diagram titled "Where a networking capability actually lives". A green Currency Type band (weight x1), a yellow Protocol Layer band (weight x4), and a red Platform Service band (weight x16). A blue bracket spans only the top two bands, labelled "what your seam covers"; a red bracket spans the bottom band, labelled "unreachable from any protocol".](Docs/portability-layers.png)

The scorer then computes the gap between what a team *says* its coupling is and what the inventory says:

```swift
let report = PortabilityAnalyzer().analyze(
    declaredSeams: 1,              // "we have one HTTPClient protocol"
    usages: SampleInventory.usages // what the code actually touches
)

print(report.summaryLine())
// MEASURED — declared seams: 1 · effective surface: 14 capabilities (14x) ·
// bypass sites: 37 · cost: 900.0 · verdict: BLOCKED
```

The verdict is policy, not arithmetic. One rule does the work:

```swift
// A platform service with no fallback plan blocks the migration outright.
// It does not matter how clean the protocol above it looks,
// because the protocol was never what made it portable.
for usage in usages where usage.capability.portability == .platformService {
    switch usage.fallback {
    case .none:        hardBlockers.append(...)   // -> .blocked
    case .documented:  stagingBlockers.append(...) // -> .stageable
    case .implemented: continue                    // -> fine
    }
}
```

## The measured result

Run against `SampleInventory` — one ordinary shopping app with checkout, media downloads, auth, and
analytics — **93% of the migration cost sits in capabilities that were never HTTP.**

![Bar chart titled "Measured on the sample inventory" showing migration cost split three ways: Currency type 0.7% (cost 6.7), Protocol layer 6.2% (cost 55.4), Platform service 93.1% (cost 838.0). A footer reads: MEASURED — declared seams 1, effective surface 14 (14x), bypass sites 37, cost 900.0, verdict BLOCKED (4 reasons).](Docs/measured-cost-split.png)

The four things blocking it:

```
Shared cookie storage      — load-bearing in Checkout (5 sites) with no fallback plan.
System credential store    — load-bearing in Auth (4 sites) with no fallback plan.
Background transfer        — load-bearing in MediaDownloader (7 sites) with no fallback plan.
Per-task transfer metrics  — load-bearing in Observability (6 sites) with no fallback plan.
```

None of those are HTTP problems. No new HTTP client fixes any of them.

## Design details worth a look

- **Worst-severity-wins merging.** Duplicate records for the same capability collapse to one; site
  counts add, but routing and fallback take the *worst* value. One unplanned bypass site makes the
  whole capability unplanned, because that is the site that will break.
- **Sub-linear site scaling.** `1 + log2(1 + n)` — the fortieth call site genuinely is cheaper to
  move than the first. Thirty sites do not cost thirty times one site.
- **`surfaceRatio` returns `nil`, not a crash,** when `declaredSeams == 0` — a team with no
  abstraction at all is a real case, not an error case.
- **The weights are tunable and the ordering is the claim.** `CostModel` is injectable. The 1/4/16
  spread encodes "platform services cost roughly an order of magnitude more", not a precise estimate.

## Running it

```bash
git clone https://github.com/rajatslakhina/networking-portability-article-demo.git
cd networking-portability-article-demo
swift test          # 27 tests, headless, no Xcode needed
```

For the app: open `Demo.xcodeproj`, pick any iOS Simulator, Build & Run. No other setup — the
library is consumed via a local Swift package reference to this same repo, so there is nothing else
to fetch.

Tapping a row in the demo upgrades its fallback plan one step. The point of the interaction: watch a
`BLOCKED` verdict become `STAGEABLE` by planning the platform services, **without touching the
protocol abstraction at all.**

## Verification status — read this part

Being straight about what was and was not verified:

| Check | Status |
|---|---|
| `swift build` (`PortabilityCore`) | ✅ passes, Swift 6.2 toolchain, strict concurrency |
| `swift test` | ✅ **27/27 passing**, including 9 edge cases |
| `Demo.xcodeproj/project.pbxproj` brace/paren balance | ✅ verified by script (30/30, 24/24) |
| `Demo.xcscheme` XML validity | ✅ parsed clean |
| No `.executableTarget` in `Package.swift` | ✅ deliberate — see the comment in `Package.swift` |
| `PortabilityKitUI` (SwiftUI) compiled | ❌ **not compiled** — headless Linux, `import SwiftUI` cannot resolve. Syntax-parsed clean (`swiftc -parse`) and manually reviewed. |
| **Run on Simulator + screenshots** | ❌ **did NOT happen this run.** Xcode already had unrelated real work open (a `HooksObservability` project). Driving that session risked interfering with it, so the run was deliberately skipped rather than forced. |

The two images above are original diagrams, not Simulator captures — there is no screenshot in this
repo because the run did not happen, and a fabricated one would be worse than none.

The `Package.swift` comment about `.executableTarget` is not theoretical: that pattern crashed 100%
of launches in an earlier repo in this series with
`__BKSHIDEvent__BUNDLE_IDENTIFIER_FOR_CURRENT_PROCESS_IS_NIL__`, because Xcode's synthesized bundle
ID is a per-checkout setting that never gets committed. Hence the real `.xcodeproj`.

## Sources

- [Announcing the Networking Workgroup](https://www.swift.org/blog/announcing-networking-workgroup/) — Swift Ecosystem Steering Group, 4 June 2026
- [What's new in Swift: June 2026](https://www.swift.org/blog/whats-new-in-swift-june-2026/) — Swift.org
- [Swift at Apple: Migrating the TrueType Hinting Interpreter](https://www.swift.org/blog/migrating-truetype-hinting-to-swift/) — 13% faster than the C it replaced

MIT.
