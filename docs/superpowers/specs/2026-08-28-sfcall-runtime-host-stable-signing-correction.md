# SFCall Runtime Host Stable Signing Correction

## Status

Approved corrective authority derived from native runtime evidence.

This document supersedes only the signing-related clauses in:

- `docs/superpowers/specs/2026-08-28-sfcall-runtime-host-design.md`;
- `docs/superpowers/plans/2026-08-28-sfcall-runtime-host.md`.

All other host architecture, privacy, capture, STT, HUD, persistence, provider, and branch boundaries remain unchanged.

## Evidence that invalidated ad-hoc signing

At `76660c42446db4811f429f9f8dbb21248892c7d9`, the host had already passed:

- 10 focused host tests;
- 35 full tests;
- `SFCallHost` build;
- strict Sendable / actor-isolation checks;
- app-bundle verification.

The packaged host nevertheless reported Screen Capture permission as denied after rebuilding the app, while the same permission had previously been authorized for the host.

A causal packaging RED at `2ef8224030b04074da541edad8ad6805d9dbaecc` proved the generated app had:

```text
Signature=adhoc
TeamIdentifier=not set
```

The verifier therefore correctly rejected the bundle as unable to provide a stable TCC code-signing identity across rebuilds.

## Superseded requirement

The earlier requirement to sign the canonical runtime-smoke host with:

```text
codesign --sign -
```

is invalid and must not be used for TCC-dependent smoke testing.

There is no fallback from stable signing to ad-hoc signing in the canonical smoke path.

## Correct signing contract

`scripts/build-host-app.sh` must package `SFCallHost.app` with a stable macOS code-signing identity.

Identity selection order is exactly:

1. use nonblank `SFCALL_CODESIGN_IDENTITY` when explicitly provided;
2. otherwise select the first valid keychain identity whose certificate name begins with `Apple Development:`;
3. if neither exists, stop with a setup error before signing.

The script must never silently fall back to `-` / ad-hoc signing.

The stable bundle identifier remains exactly:

```text
com.sfcall.host
```

## Verification contract

`scripts/verify-host-bundle.sh` must reject a packaged host unless all of the following hold:

- bundle structure and executable are valid;
- `CFBundleIdentifier == com.sfcall.host`;
- all four privacy usage-description keys are nonblank;
- `codesign --verify --deep --strict` succeeds;
- `Signature` is not `adhoc`;
- `TeamIdentifier` is nonblank and is not `not set`;
- `codesign -dr -` returns a nonblank designated requirement.

The verifier reports the signing team and designated requirement as runtime evidence.

## Local developer setup boundary

A machine without a stable development code-signing identity is a setup blocker for TCC-persistent runtime smoke testing.

The operator may inspect available identities with:

```bash
security find-identity -v -p codesigning
```

When more than one suitable identity exists, the operator may select one explicitly:

```bash
SFCALL_CODESIGN_IDENTITY='Apple Development: Name (TEAMID)' \
  bash scripts/build-host-app.sh
```

The repository must not create certificates, export private keys, inspect the TCC database, or mutate TCC records.

## Acceptance

The signing correction is accepted only after native verification proves:

1. packaging succeeds with a non-ad-hoc signature;
2. a stable nonblank TeamIdentifier is present;
3. the designated requirement is nonblank;
4. bundle verification passes;
5. Screen Capture authorization can be granted to the resulting stable host identity and source enumeration proceeds without source mutation.

End-to-end remote audio, microphone audio, STT separation, ResponseRequest routing, and HUD exclusion observation remain the independent native smoke evidence gate from the original design.
