# Main question workflow investigation — October 27, 2026

**Historical investigation.** On October 28 afternoon, Firecrawl search/page
reading and local AI passage selection entered the answer pipeline. Owner testing
confirmed voice capture, relevant source discovery and in-app opening. Choosing
useful passages remains a quality gap. See `HANDOFF-2026-10-28-PM.md` for the
current checkpoint; the limitations below describe the earlier implementation.

The desktop workflow now starts clean, survives a failed connection, and bounds
the time spent waiting for manufacturer research. It is not yet ready to promise
general equipment question answering to local shops.

## Findings and fixes

| Finding | Effect | Change |
| --- | --- | --- |
| Startup loaded the latest active conversation automatically. | A new session inherited an old machine and transcript. | Startup lists saved jobs but leaves the question workspace blank; history opens explicitly. |
| One HTTP request serialized the question workflow, with a 90-second frontend timeout. Manufacturer lookup had no overall question deadline. | A slow site, redirect chain or DNS stall could leave Ask disabled for a long time. | Research returns an explicit timeout after eight seconds. At most two lookup workers may remain outstanding. Questions have a 20-second client timeout; routine local operations five seconds, explicit document reading 45 seconds. |
| Starting a new job retained source records and pending reference state in memory. | A fresh workspace could still carry old reference state. | Reset source records, pending navigation/reference state and request bookkeeping. |
| Unsupported recognized models received another model-identification question. | Repeating the same identity looked like a stuck conversation. | Explain the coverage gap and offer the existing web-search action. |
| Search provider only generates a browser URL. | Search results never reach the answer pipeline. | Remaining implementation gap; not represented as completed research. |
| The optional local model selector is not called by the current answer pipeline. Technical extraction deliberately returns a limitation. | Installing/running the local model does not turn this app into a general answer engine. | Remaining implementation gap. |

Timeout workers only retrieve documents; persistence happens in the question
request after the bounded wait. A late worker result cannot replace a saved
answer. Up to two stalled workers can temporarily occupy research capacity;
new questions then receive an explicit busy reply instead of creating more
threads. The underlying network operation may continue after the UI stops
waiting. This is bounded waiting, not cancellation of DNS/socket work.

## Verification

All checks used temporary databases; the user's equipment and conversations were
not reset. Existing uncommitted work was retained.

- 82 Python tests pass, covering API validation, context changes, archives,
  persisted references, launcher health/shutdown, timeout persistence, late-result
  isolation, and bounded retries.
- Real Godot prototype integration passes through two frontend processes and two
  backend lifetimes: clean restart, explicit history reopen, notes/parts/context
  preservation, saved HTML/PDF reopening without network, offline question draft
  preservation, reconnect, and request-key replay without duplicate messages.
- Godot reference integration passes, including PDF page rendering.
- Godot Milestone 1 interface smoke test passes, including compact menu,
  source associations, draft preservation and narrow portrait layouts.
- `git diff --check` and Python compilation pass.

The restricted sandbox could not open sockets and its first API test run stalled.
Tests were rerun successfully with local runtime access. Those sandbox failures
were not counted as application defects. Godot checks were headless; this does
not replace a person trying the visible desktop app in a shop.

## Live question probes

One fresh disposable database, real manufacturer networking enabled, local AI
disabled, no paid services. Durations are observations from this run, not speed
guarantees.

| Question | Observed time | Result |
| --- | --- | --- |
| My mower turns over but will not start | under 0.01 s | Scripted identity/fuel follow-up; no diagnosis. |
| Find the manual for Honda GX160 | 0.84 s | Manufacturer model listing retrieved; serial needed to select a manual. |
| 2004 Honda TRX200 what spark plug does it take? | under 0.01 s | No verified answer; recognized-model coverage gap. |
| What torque specification for Kohler XT675? | under 0.01 s | No verified answer; recognized-model coverage gap. |

The unsupported-model clarification was corrected after these probes; a new
regression test verifies its replacement wording.

## Before local-shop trials

The primary blocker is now answer capability, beyond startup reliability. The
next increment needs a search provider that returns usable results to the app,
document retrieval for the intended shop equipment, and an answer pipeline that
can turn applicable evidence into a concise sourced answer. Test it against an
agreed set of real shop questions, including unsupported questions, changed
machines, missing serial numbers, conflicting manuals and unavailable sources.
The current automated tests establish workflow behavior; they do not establish
correct repair/specification answers.
