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
