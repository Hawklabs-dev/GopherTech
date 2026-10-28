# Voice, clear results and Firecrawl — October 28, 2026

Owner direction: defer the wider interface redesign. Make Go For Gopher useful
for quick questions; add voice input and a way to clear the results beneath it.
The owner then authorized integrating Firecrawl, starting with free access and
considering paid services later.

## Owner review and tomorrow's resume

After implementation, the owner confirmed microphone capture of their wording,
useful research results and in-app source opening. Their 1998 Yamaha Grizzly
600cc no-start/carburetor question found relevant pages, but the selected excerpt
was a forum introduction. Improve task-relevant passage selection next. Basic
voice capture is now owner-tested; noisy-shop/model-number accuracy and correct
repair advice are not established. See `HANDOFF-2026-10-28-PM.md` for evidence,
remaining observations, private backup and October 29 starting instructions.

## Current behavior

- Speak checks local speech availability, then records only after that explicit
  tap. Stop recording or the 30-second limit sends mono PCM WAV to the local
  backend. Vosk transcribes locally; the frontend appends the words to the
  existing draft for review. No automatic Ask, background listening or audio
  file retention. The owner confirmed basic capture; names, numbers and speech
  in a noisy shop need broader human testing.
- Leaving Go For Gopher, starting an order switch or clearing cancels dictation.
  Late canceled transcription replies cannot change the incoming order's draft.
- Clear results hides existing exchanges and clears document/browser content,
  preserving SQLite history, notes, parts and the unsubmitted question.
  Background saves do not restore hidden exchanges. Later answers appear;
  Show saved history restores previous exchanges. Hidden-history state is
  session-only and separate per order. Clearing is not archiving or deletion.
- Ask checks saved information, then uses Firecrawl `/v2/search` with markdown
  reading enabled for at most three web results. It requests no crawl, agent,
  browser automation, hosted model or paid fallback. Requests send the current
  research question and recognized machine context to Firecrawl; notes and
  photos are not uploaded by this integration.
- Search results without readable page content are not read evidence. A page
  must contain the current model where one is known. Recognized manufacturer
  sources take priority; video transcripts are excluded. Publisher identity,
  serial/year/region applicability and conflicting specifications still need
  checking. The manufacturer classification currently covers the existing Honda
  and Briggs/Vanguard directory, rather than claiming every brand is verified.
- The existing local Qwen model now selects actual passage IDs in the answer
  pipeline. It cannot supply new facts or URLs. Exact short source excerpts are
  shown; if it abstains, the reply reports that. If local inference is unavailable
  or times out, matching excerpts are explicitly described without an AI claim.
  This is an initial research integration, not unrestricted generated repair
  advice or a completed general AI assistant.
- PDF text is saved, with the source/manual available for inspection. Its text
  is not automatically promoted to repair instructions. Honda Europe's manual
  host is also allowed by the existing bounded original-PDF/page reader.
- Source snapshots and links are stored using the existing workshop tables.
  Offline reopen and suitable saved-source reuse avoid another Firecrawl call.
  The Firecrawl plan retains source metadata, not duplicated full page text.

## Authentication and limits

The workstation's keyless call returned HTTP 403 because Firecrawl classified
its network as a VPN/proxy. The supported browser authorization flow succeeded,
and a subsequent direct API test retrieved source pages.

`tools/connect_firecrawl.py` uses Firecrawl's documented browser authorization
with a verifier/challenge. It saves the returned credential with mode 0600 to
`~/.config/gophertech/firecrawl.json`; it never prints the credential. The backend
also accepts `FIRECRAWL_API_KEY` from its environment. Credentials are not put
in job responses, SQLite, Godot scripts, Git or an Android package.

The helper does not select a paid plan, purchase credits or enable auto-recharge.
Firecrawl's account plan controls its credit balance and billing; this app does
not change that plan. HTTP 401/403 and 402/429 produce explicit connection or
limit messages. No automatic retry or paid-provider fallback is performed.

Default search provider is now `firecrawl`. Explicit alternatives are `browser`
and `disabled`. `GOPHERTECH_RESEARCH_NETWORK=0` prevents question-driven online
lookup. A read-only job GET only returns its saved plan; it never researches.

Search/page response caching lasts five minutes and is bounded to 16 queries.
At most two research workers may run. Interactive research waits at most 24
seconds; late workers cannot alter saved answers. The frontend question timeout
is 35 seconds. Local inference has a five-second request timeout in this path.
Routine local saves retain their existing shorter timeouts.

Local speech uses optional `requirements-voice.txt` and a pinned, SHA-256-checked
39 MiB English Vosk model outside Git. New desktops need explicit setup; no
model downloads occur at application startup. Android packaging and its
microphone permission/lifecycle remain separate work.

## Validation

Tests use disposable databases and photo storage. No shop records were reset.

- 113 Python tests pass. Godot interface, quick-input, workshop-tool,
  work-order/reopen and HTML/PDF reference integration checks pass.
- Desktop and 390-pixel portrait previews were rendered and inspected; the
  Speak and Clear results controls fit without a wider interface redesign.
- The normal localhost backend was restarted after verification. Its live
  capability endpoints confirm Firecrawl authorization, local AI availability
  and local dictation readiness. The next Godot F5 run uses these endpoints.
- Backend regression tests cover audio validation/limits, raw HTTP audio uploads,
  source parsing, connection/credit errors, model mismatch, PDF/table limits,
  video exclusion, local-AI abstention, saved-source reuse, per-exchange source
  isolation, request-key replay and timeout/late-worker behavior.
- Godot quick-input checks cover clear/restore, preserved drafts/notes/parts,
  background-save behavior, late answers/references, voice cancellation,
  stereo-to-mono WAV encoding and a 360-pixel touch layout.
- The existing interface and work-order/reopen checks remain part of validation.
- Real Vosk recognition passed using the upstream spoken-number WAV sample;
  the raw-audio HTTP route returned words without creating a work order.
  This does not establish the owner's microphone or noisy-shop accuracy.
- Real Firecrawl requests through the temporary app backend retrieved Honda
  GX160 references in roughly five to six seconds, with saved-source reopen.
  An initial result selected a repetitive video transcript; the final selection
  policy excludes it and favors the manufacturer manual for that case.
- A general carburetor-choke question exercised live Firecrawl and the real
  local model in about ten seconds, selecting relevant text from Summit Racing.
  Timings are observations, not latency guarantees.

Commands:

```bash
GOPHERTECH_LOCAL_AI=0 GOPHERTECH_RESEARCH_NETWORK=0 .venv/bin/python -B -m unittest discover -s tests -q
GOPHERTECH_API_URL=http://127.0.0.1:1 godot --headless --path Godot/gopher-tech --script res://quick_input_smoke.gd
GOPHERTECH_API_URL=http://127.0.0.1:1 godot --headless --path Godot/gopher-tech --script res://milestone_one_smoke.gd
GOPHERTECH_LOCAL_AI=0 GOPHERTECH_RESEARCH_NETWORK=0 .venv/bin/python -B tests/run_work_order_integration.py
```

Official integration references:
- https://docs.firecrawl.dev/features/search
- https://docs.firecrawl.dev/rate-limits
- https://www.firecrawl.dev/agent-onboarding/SKILL.md
- https://docs.godotengine.org/en/stable/tutorials/audio/recording_with_microphone.html
- https://github.com/alphacep/vosk-api/blob/master/python/example/test_simple.py
