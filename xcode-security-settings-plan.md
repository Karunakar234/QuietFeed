# QuietFeed Xcode Security Settings Plan

Status: Audit complete; no security build-setting changes applied.

## Scope

- `QuietFeed` application target
- `QuietFeedTV` application target
- `QuietFeedTests` is excluded from Enhanced Security because it is a test bundle.

The project contains Swift source only. No C, C++, Objective-C, Objective-C++, `.xcconfig`, or entitlement files were found, so C-family compiler hardening and entitlement migration are not applicable.

## Current state

| Target | Setting | Current value | Assessment |
|---|---|---:|---|
| QuietFeed | Enhanced Security | `NO` | Eligible app target; opt-in available |
| QuietFeedTV | Enhanced Security | `NO` | Eligible app target; opt-in available |
| QuietFeedTests | Enhanced Security | `NO` | Leave unchanged for the test bundle |
| All targets | User Script Sandboxing | `YES` | Keep enabled |
| All targets | Code-signing entitlements | None | No entitlement migration required |
| All targets | Swift strict concurrency | `minimal` | Review separately; not part of this security-settings rollout |

## Proposed phased rollout

### Phase 1 — QuietFeedTV

Enable Xcode Enhanced Security for `QuietFeedTV`, then build and smoke-test launch and navigation. The TV target is the smaller application surface and is the safer compatibility probe.

### Phase 2 — QuietFeed

After Phase 1 succeeds, enable Xcode Enhanced Security for `QuietFeed`, then rebuild and run the complete test suite plus WebView launch, authentication-session, media, background/foreground, and external-link smoke tests.

## Validation and rollback

For each phase:

1. Apply only the target's Enhanced Security setting.
2. Build the affected target and inspect all new warnings/errors.
3. Run relevant automated and simulator tests.
4. Review signing output and application launch behavior.
5. If compatibility regresses, restore Enhanced Security to `NO` for that target and document the blocker.

## Deferred settings

- Raising Swift strict concurrency from `minimal` needs a dedicated warning-remediation pass and is not bundled into this hardening change.
- Treating all warnings as errors is intentionally not proposed; it can destabilize builds when SDK diagnostics change.
- The nonlocalized-string analyzer is a Clang analyzer setting and has no benefit in this Swift-only codebase.

## Approval gate

No setting in this document may be changed until the user explicitly approves the Run phase.
