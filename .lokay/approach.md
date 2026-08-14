# Approach plan

<!-- lokay-approach source=deterministic repo=mikolaj92/swift-openapi-dynamic issue=5 -->

Repository: `mikolaj92/swift-openapi-dynamic`  
Issue: #5 — Badge CI w README wskazuje na skasowany workflow daily_test.yml

## Goal

README: `[![Build](https://github.com/mikolaj92/swift-openapi-dynamic/actions/workflows/daily_test.yml/badge.svg)]`.

## Files likely touched

- `README.md` (remove the 404 `daily_test.yml` build badge)
- `CHANGELOG.md` (document the docs fix)

## Test plan

- Run the smallest useful tests for files touched

## Non-goals

- (none stated)

## Notes

- Trust intentional issue; this plan is evidence for later review, not a human gate.
- Coding agent may refine details but should stay on the stated goal and non-goals.
- Collector boundary: if implementation introduces unbounded collection, ship only a bounded collector patch that starts durably in the background after merge. The coding agent and mill must not populate data or wait for collection to finish.
