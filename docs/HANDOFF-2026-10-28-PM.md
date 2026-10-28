# GopherTech end-of-day handoff — October 28, 2026

Resume Thursday, October 29. Owner requested the logs, resume notes and a GitHub
checkpoint after successful hands-on microphone and research testing. Stop feature
work at this checkpoint; the items below are tomorrow's work, not background tasks.

## Start here

Read this handoff and `VOICE-AND-FIRECRAWL-2026-10-28.md`, inspect `git status -sb`
and the current sources, and preserve existing shop records. The wider interface
redesign is explicitly deferred. First improve **which information is selected
from a relevant page**, using the owner's Grizzly example below.

The default Go For Gopher route now uses Firecrawl search with page reading,
followed by optional local Qwen passage selection. It is an initial research
assistant returning exact excerpts and references, not unrestricted generated
diagnosis or a verified repair procedure. No paid plan, credit purchase or hosted
AI activation was performed by this setup. Discuss any paid activation with the
owner first; interest in pricing did not authorize it.

## Owner-tested results

The owner reported: "Mic check works, Gopher tech got my wording right" and
"it does find things well, again more info you give the better the output."
They called the result a "huge win" and agreed the next improvement is passage
selection. This is hands-on feedback, separate from automated test results.

The typed Grizzly question shown in the screenshots is:

> 1998 yamaha grizzly 600cc atv it wont start and i need to rebuild the carb how do i do that

The app found a model/year-relevant forum discussion and a MotoSport starting
article. The owner opened the MotoSport page inside the embedded browser.
However, the selected forum excerpt is the author's introduction, rather than
useful troubleshooting or carburetor-rebuild information. Finding a relevant
page is demonstrated; useful repair guidance and correct diagnosis are not.

Evidence, retaining the owner's original filenames:

- `Screenshot_20261028_135524.png`: Grizzly question while researching.
- `Screenshot_20261028_135538.png`: source findings, weak introductory excerpt.
- `Screenshot_20261028_135623.png`: MotoSport source open in GopherTech.
- `voicerec.png`: spoken Arctic Cat request transcribed into the draft.
- `voicerec_001.png`: that request returned broad manual-directory results.

## Tomorrow's priorities

1. Select useful source content instead of introductions, navigation or repeated
   question text. Evaluate against the complete requested task: the Grizzly
   request asks about both a no-start symptom and a carburetor rebuild. Do not
   present the existence of a source as an answered procedure.
2. Improve spoken equipment/model normalization without guessing. The Arctic Cat
   wording includes spoken displacement and imperfect terms, and its result
   shows generic automotive manual directories. Preserve the original wording;
   confirm ambiguous identity before claiming the right machine/manual.
3. Investigate confusing carried labels/search actions in the owner's Grizzly
   screenshot: the Saved line still contains an earlier Arctic Cat question,
   and the older browser-search action appears below the source excerpt.
   Determine whether this is a saved work-order title, retained plan/UI state or
   old runtime behavior. It is an observation, not a proven identity-leak bug.
4. Retest microphone/model-number capture in actual workshop noise. The owner
   confirmed basic capture, not broad accuracy across accents, numbers or tools.
5. Keep standalone Android proof, mobile WebView/camera and later hosted AI as
   separate milestones. The current build remains desktop. Wider interface
   dissatisfaction is recorded but redesign waits for the owner's next direction.

## Implemented controls and protections

- Speak -> Stop recording -> review text -> Ask. Offline Vosk recognition, at
  most 30 seconds, no retained audio file, no automatic submission.
- Leaving quick search, switching orders or clearing cancels voice; canceled
  responses cannot change another order's question draft.
- Clear results hides replies and dismisses references without deleting saved
  records, notes, parts or the typed draft. Show saved history restores them.
  Hidden-history state is session-only. Later answers appear normally.
- Firecrawl reads at most three candidate pages per lookup. Failed page reads,
  mismatched recognized models, credit limits and timeouts are explicit.
- Known manufacturer sources are preferred; video captions are excluded.
  Raw PDF text is not promoted to repair instructions. Original PDF inspection
  remains available, including the added Honda Europe host.
- Sources stay with their exchange and are saved in the existing SQLite tables.
  Suitable saved source reuse/reopen avoids another online request. No new DB
  schema was needed for this afternoon's increment.
- Read-only job GETs do not search. Two research-worker slots, a 24-second
  overall wait and a 35-second frontend question timeout bound interactive waits.
  Late workers cannot rewrite saved replies.

## Runtime and private setup

The normal backend was restarted and verified at `http://127.0.0.1:8000`.
Godot F5 uses that backend. `./run_dashboard.sh` instead owns a private backend
for its app lifetime. Do not assume any service remains running tomorrow.

Live capability checks confirmed Firecrawl authorization, local Qwen readiness
and local dictation readiness. The Firecrawl key is stored in
`~/.config/gophertech/firecrawl.json` with permissions 0600, outside Git. Never
print it, paste it into chat, commit it or put it into an Android package.
`tools/connect_firecrawl.py` performs browser authorization if reconnecting is
needed. Keyless access was refused from this workstation's VPN/proxy network.

Vosk and its English model are installed locally. Another desktop needs
`requirements-voice.txt` and explicit `tools/setup_voice.py`. The CEF browser,
local Qwen/runtime and model downloads are likewise local setup, not Git assets.

## Validation and recovery

- 113 Python tests passed. Godot interface, quick-input, workshop-tool,
  work-order/reopen and HTML/PDF reference integrations passed.
- Desktop and 390-pixel portrait previews were inspected.
- Real Vosk spoken-number sample and local audio HTTP checks passed. Owner then
  confirmed microphone capture during actual use.
- Live Firecrawl + local AI probes retrieved GX160 references and selected
  carburetor-choke source text; saved reference reopen passed.
- Automated checks used disposable DB/photo storage. Physical tablet behavior,
  broad machine coverage, diagnostic quality and outside-shop acceptance remain
  unverified. Earlier full-browser click/wheel retesting remains outstanding.

Owner authorized committing and pushing the afternoon checkpoint to the existing
`Hawklabs-dev/GopherTech` repository on `main`. Verify remote `refs/heads/main`
against local HEAD; do not infer publication from a cached origin/main ref.

A separate private data backup was created at:

`/home/n_hawk/HawkLabs/GopherTech-backups/checkpoint-2026-10-28_140151/`

It contains a consistent SQLite backup (integrity `ok`, no foreign-key violations)
and a manifest. No photo files were found in the default app photo directory at
backup time. Credentials are excluded. Git checkpoints cover code/docs/screenshots;
they do not contain the shop database, local photo store or runtime downloads.
