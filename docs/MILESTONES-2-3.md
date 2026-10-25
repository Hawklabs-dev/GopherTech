# Shop Buddy milestones 2–3

Launch with `./run_dashboard.sh`. It starts the existing FastAPI app on a private
loopback port and passes that address to Godot. Closing Godot stops that backend.
An editor Run still requires `./run_backend.sh`; it does not invoke the desktop
launcher. Existing equipment, finance, parts and conversation tables are retained.

No paid search or inference is enabled. A local llama.cpp/Qwen3-4B installation
can select relevant retrieved passages. `tools/setup_local_ai.py` installs pinned,
SHA-256 checked official runtime/model files outside the repository, under
`~/.local/share/gophertech-ai` (about 2.6 GB). The installation has already been
performed on this workstation. Models are not uploaded or bundled in Git.
The model service listens only on loopback. It may remain loaded after closing
the app so subsequent launches are fast. `/system/info` reports readiness.
Set `GOPHERTECH_LOCAL_AI=0` to disable it; reference extraction remains available.
No credentials are required. This is evidence selection, not unrestricted AI chat.

The in-app pipeline checks saved references, then fetches supported public
manufacturer model listings. Honda model indexes can lead to an actual PDF when
a full serial prefix and number match the published applicability row. Unknown
ranges are not guessed. Exact passages carry source URLs and PDF page numbers.
PDF diagrams remain available through the existing reader. HTML/PDF copies and
retrieval metadata persist in SQLite. Cache reuse is labelled as unverified
applicability; a keyword match alone never verifies a numeric specification.

This is scoped document research, not a whole-web search engine. Deere, Exmark
and other unsupported models currently receive an honest limitation or identity
follow-up, not invented procedures. Interactive-only/restricted sites are not
bypassed. General generated diagnostic conversation and broad manufacturer
coverage remain incomplete. The browser provider is an explicitly optional
handoff, and the API provider is an unavailable boundary; neither claims to
return in-app search results. No checkout/order features were added.

Tests use disposable databases, original document fixtures, network disabled and
local AI disabled unless explicitly mocked. Live validation separately checks
public Honda retrieval and the installed local model. No production records are
used for test questions.

## Workshop refinement pass

- Answers scroll smoothly to the beginning of the latest reply. Manual passages,
  source URLs and applicability cautions remain visible without opening details.
- Ctrl+Enter sends; Enter still starts a new line. The Ask button shows a busy
  label. A newer draft typed during a request is preserved when the reply arrives.
- Common aliases (JD, John Deer, B&S), `model is D120`, natural Honda serial
  follow-ups and corrected serial numbers are recognized. Explicitly mentioning
  another mower clears carried identity and observations from routing context.
- Manufacturer lookup limitations supplement troubleshooting guidance. Ambiguous
  serial matches are flagged rather than choosing the first PDF. Known full
  serial numbers that fail to match are acknowledged rather than requested again.
- Cached PDF answers include page references. Quick-answer requests limit extracts
  to one passage; guided troubleshooting adds a short identification/check sequence.

Retest with a separate saved conversation for each mower: describe its symptom
without a model, answer the identity follow-up, then close/reopen and check that
its notes and parts belong to that mower. Try a question with a known manual and
an unavailable document. Source coverage remains limited to the supported libraries;
this pass does not add a paid service or claim broad manufacturer coverage.

Validation: 71 isolated Python tests; Godot interface acceptance (desktop and
360/390px widths), including visible citations and preservation of a new draft;
Godot question/manual/notes/parts workflow and restart/reopen. Desktop and phone
screens were rendered and visually inspected with original fixture text.
