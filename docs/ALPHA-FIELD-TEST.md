# HawkLabs Alpha Field Test — target October 28, 2026

The target is a readiness decision, not a public release promise. Start with
2–3 trusted mechanics/equipment owners only after hands-on checks pass.

October 25–26: stabilize research, PDF reading, concise cited answers and recovery.
October 27: use three riding mowers, one saved conversation per mower. Record
make/model, symptom, what helped, what was wrong, and any unavailable information.
October 28: invite testers only if the checks below pass. October 29–30: fix
reported problems; keep unrelated features frozen.

## Hands-on readiness — 0 of 6 confirmed

Automated checks do not tick these boxes. Record tester, date and evidence when
performing each check on the actual candidate.

- [ ] Questions produce useful answers or clear limitations.
- [ ] Manual references, citations and applicability can be checked.
- [ ] Conversations and findings survive closing and restarting.
- [ ] Reviewed answers contain no invented specifications or unsafe directions.
- [ ] Another person launches without developer assistance.
- [ ] Disconnecting the network produces a clear error without crashing.

For each mower, try a vague question first, provide model details naturally,
read a cited passage and the corresponding PDF page, save a note and parts item,
restart, and reopen that mower. Check offline access to previously saved material.
Never treat a plausible answer or a serial-range match as proof of compatibility.

## Current local launch

From the project folder run `./run_dashboard.sh`. Closing Godot closes its owned
backend. An already running manual backend is left alone. Running from the Godot
editor still needs the separately started backend; Python source changes require
restarting that backend before an editor-run test sees them.

## Tester-friendly build work still required

This checkout is not yet a portable distribution. Prepare and test a bundle for
the testers' actual operating systems. It needs a Godot export, backend runtime
and dependencies, PDF text/page utilities with their licensing notices, a launcher
that reports startup failures visibly, and a writable user-data location rather
than a database inside an installed application folder. Verify installation and
upgrade preserve existing data. Do not distribute this workshop's SQLite file.

The optional local model/runtime currently lives outside Git on this workstation.
Choose either an explicitly labelled reference-only alpha or a separately tested
local-model installation. Do not assume tester hardware can run the workstation's
GPU configuration. Package appropriate model/runtime license and download details
if including that option. No cloud billing or paid API setup is authorized.

No Amazon store, buying, new fabrication features, large redesign, broad machine
support or unrestricted AI conversation is needed for this alpha.
