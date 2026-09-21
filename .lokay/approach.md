# Approach plan

<!-- lokay-approach source=deterministic repo=mikolaj92/swift-openapi-dynamic issue=22 -->

Repository: `mikolaj92/swift-openapi-dynamic`  
Issue: #22 — [code-audit] OpenAPIDynamic nie jest Sendable, docs o izolacji milcz\u0105

## Goal

`public final class OpenAPIDynamic` nie jest `Sendable`. README, DocC i komentarz typu milczą o izolacji. Biblioteka ma żyć obok generated clientów w Swift 6.

## Files likely touched

- (infer from repo inspection)

## Test plan

- Klasa jest `Sendable` (albo `@unchecked Sendable` z uzasadnieniem w komentarzu)
- Albo README jasno mówi, że instancja nie przechodzi granic izolacji i trzeba robić nową na isolation
- Kompilacja z `StrictConcurrency` nie ostrzega na publicznym typie

## Non-goals

- (none stated)

## Notes

- Trust intentional issue; this plan is evidence for later review, not a human gate.
- Coding agent may refine details but should stay on the stated goal and non-goals.
- Collector boundary: if implementation introduces unbounded collection, ship only a bounded collector patch that starts durably in the background after merge. The coding agent and lokay must not populate data or wait for collection to finish.
- No explicit file paths in issue; infer from repo inspection.
