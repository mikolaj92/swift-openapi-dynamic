# Approach plan

<!-- lokay-approach source=deterministic repo=mikolaj92/swift-openapi-dynamic issue=23 -->

Repository: `mikolaj92/swift-openapi-dynamic`  
Issue: #23 — [test-audit] Publiczne dekodowanie JSON nie ma unit test\u00f3w bez sieci

## Goal

README i AUDIT.md sprzedają Codable, status decoding, type-map i auto-headery jako kontrakt. Deterministyczne testy w `Tests/OpenAPIDynamicTests` tego nie pokrywają. Jedyny dowód to live suite gated `OPENAPI_DYNAMIC_ENABLE_LIVE_TESTS=1`.

## Files likely touched

- `Tests/OpenAPIDynamicTests/OpenAPIDynamicTests.swift`

## Test plan

- Unit testy `MockURLProtocol` dla każdej publicznej ścieżki dekodowania
- Auto-header i override są asercjami na `URLRequest`, nie na echo httpbin
- `swift test` bez env var przechodzi te przypadki
- Live suite zostaje opcjonalnym smoke, nie jedynym pokryciem

## Non-goals

- (none stated)

## Notes

- Trust intentional issue; this plan is evidence for later review, not a human gate.
- Coding agent may refine details but should stay on the stated goal and non-goals.
- Collector boundary: if implementation introduces unbounded collection, ship only a bounded collector patch that starts durably in the background after merge. The coding agent and lokay must not populate data or wait for collection to finish.
