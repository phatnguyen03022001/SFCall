# SFCall

Native-macOS-first call copilot for freelance calls.

Current slice implements the durable memory core before audio/UI:

- client identity (`platform`, `platformRef`) and evidence-backed client facts;
- separate requirement ownership: `CLIENT`, `USER`, `MUTUAL`;
- requirement states: confirmed / proposed / needs-confirmation;
- confirmed baseline versioning;
- append-only evidence and case-event history;
- local SQLite persistence across restarts;
- call-session metadata;
- raw audio retention defaults to `NEVER`;
- transcript retention defaults to `EPHEMERAL`;
- optional persisted transcript keeps CLIENT and USER speakers separate;
- final CLIENT turns build compact provider-neutral response context;
- spoken-response policy defaults to A2–B1, max 3 sentences, Vietnamese hint, and no unverified commitments.

## Data model

```text
Client
├─ ClientFacts (evidence-backed)
└─ Case
   ├─ Requirements (CLIENT / USER / MUTUAL)
   ├─ Confirmed Baseline vN
   ├─ Evidence (append-only)
   ├─ CaseEvents (append-only history)
   └─ CallSessions
      └─ TranscriptTurns (only when retention = persist)
```

A client's statement is evidence that the client said something; it does not automatically rewrite the confirmed baseline.

## Local development

```bash
swift test
```

Open `Package.swift` in Xcode on macOS for native adapter work.
