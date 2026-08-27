# SFCall Stable Signing Correction Implementation Plan

> **For agentic workers:** This plan corrects only the canonical smoke-host signing path. It supersedes the ad-hoc-signing steps in `docs/superpowers/plans/2026-08-28-sfcall-runtime-host.md` and implements `docs/superpowers/specs/2026-08-28-sfcall-runtime-host-stable-signing-correction.md`.

**Goal:** Preserve one stable macOS TCC identity for `SFCallHost.app` across rebuilds so Screen Capture authorization is not invalidated by ad-hoc signatures.

**Architecture:** Keep the SwiftPM host, bundle identifier, privacy metadata, permission flow, capture/STT runtime, and HUD unchanged. Change only local packaging/signing and its verification: use an explicit or auto-detected `Apple Development` identity, reject ad-hoc signatures, and surface missing signing setup as a blocker.

**Tech Stack:** macOS `security`, `codesign`, Bash, existing SwiftPM host packaging.

## Global Constraints

- Keep `main` untouched.
- Do not change capture, STT, routing, persistence, provider, or HUD behavior.
- Do not inspect or modify the TCC database.
- Do not generate, export, or persist private signing keys.
- Bundle identifier remains exactly `com.sfcall.host`.
- Canonical runtime smoke packaging must never fall back to ad-hoc signing.

---

### Task 1: Causal RED for unstable signing

**Files:**
- Modify: `scripts/verify-host-bundle.sh`

- [x] Reject `Signature=adhoc`.
- [x] Require nonblank `TeamIdentifier`.
- [x] Require nonblank output from `codesign -dr -`.
- [x] Run the verifier against the existing ad-hoc packager and confirm RED.

Observed RED at `2ef8224030b04074da541edad8ad6805d9dbaecc`:

```text
Signature=adhoc
TeamIdentifier=not set
HOST_BUNDLE_VERIFY: FAIL — ad-hoc signing cannot preserve TCC identity across rebuilds
```

---

### Task 2: Stable signing implementation

**Files:**
- Modify: `scripts/build-host-app.sh`

Identity selection:

```text
SFCALL_CODESIGN_IDENTITY when explicitly nonblank
otherwise first valid keychain identity named Apple Development: ...
otherwise fail before codesign
```

Canonical signing command:

```bash
/usr/bin/codesign --force --sign "$IDENTITY" --timestamp=none "$APP"
```

Post-sign checks performed by the packager:

```text
codesign verification succeeds
Signature != adhoc
TeamIdentifier exists and is not "not set"
```

Missing stable identity is a setup blocker. The script prints:

```bash
security find-identity -v -p codesigning
```

and documents the `SFCALL_CODESIGN_IDENTITY` override instead of falling back to ad-hoc signing.

---

### Task 3: Native GREEN verification

**Files:**
- No source mutation authorized.

Run from a clean `dev` checkout:

```bash
security find-identity -v -p codesigning
bash scripts/verify-host-bundle.sh
```

Require:

```text
HOST_BUNDLE_VERIFY: PASS
Signature != adhoc
TeamIdentifier = nonblank
HOST_DESIGNATED_REQUIREMENT = nonblank
```

Then inspect the packaged host directly:

```bash
/usr/bin/codesign -dv --verbose=4 .build/SFCallHost.app 2>&1 | \
  grep -E 'Identifier=|Signature=|TeamIdentifier='

/usr/bin/codesign -dr - .build/SFCallHost.app 2>&1
```

Launch the same stable bundle:

```bash
open .build/SFCallHost.app
```

Use `Grant Required Permissions`, then `Refresh Sources`.

Require Screen Capture authorization and source enumeration to proceed without editing TCC state or source files.

If no suitable `Apple Development` identity exists, return `BLOCKED_SIGNING_IDENTITY` and stop. Do not substitute an ad-hoc signature.

---

### Task 4: Preserve independent runtime smoke gate

Stable signing fixes only TCC identity persistence. It does not prove audio/STT behavior.

After signing/TCC verification passes, the existing native runtime gate still must separately verify:

```text
remote/system audio capture
remote Apple Speech STT
microphone capture
microphone Apple Speech STT
CLIENT/USER stream separation
remote-final ResponseRequest behavior
microphone-final no-ResponseRequest behavior
HUD sharingType == .none
empirical HUD capture exclusion when practical
clean Stop teardown
```

No provider/LLM work is authorized by this correction.
