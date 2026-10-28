# GopherTech morning handoff — October 28, 2026

The owner approved publishing this morning's local checkpoint to the existing
`Hawklabs-dev/GopherTech` repository on `main`, then resuming this afternoon.

## Current product shape

Standalone tablet helper is the target; the tested build is still desktop.
Quick search opens first. A permanent compact header shows the current work
order number and machine summary. Four main buttons open Go For Gopher,
Work Area, Parts and Tools. Work Area combines order selection/creation,
machine details and Parts / Troubleshoot / Repair / Fabricate / Photos panels.
No required status workflow, finance UI, parent PC, inventory/POS or purchasing
in this release. Retain the existing calculators/reference/equipment tools.

Each research section auto-saves its own task and notes within its work order.
Unused sections open blank. Switching flushes pending changes and restores the
selected section/order, including after restart. Machine details are common to
the order. Historical shared notes remain available as Parts notes; do not guess
and redistribute their intended section. Draft conversation questions, selected
mode, brief displays and scroll positions are session-only.

Photo selection/preview/Keep Photo preserves original JPEG/PNG/WebP files on the
local device under Godot's `user://work-order-photos/<job UUID>/` directory.
Photos remain separate from SQLite, so backups must include both locations.
Camera capture, OCR/label identification and AI image interpretation are absent.

## Verification

- 90 Python tests pass, including section persistence, validation, legacy notes
  compatibility and repeatable additive database migration.
- Godot interface and workshop-tool smoke checks pass.
- Work order workflow/reopen tests pass across two app processes and two backend
  lifetimes. Coverage includes distinct section tasks/notes, untouched blank
  fields, Ford F250-to-other-order isolation, late response handling, offline
  save/reconnect, per-order scroll positions and original photo preservation.
- Existing conversation/reopen and HTML/PDF reference integrations pass.
- The previous real-browser input test could not acquire desktop focus. Click
  and wheel retesting remains outstanding; fixture-based reference checks pass.
- Test runs use disposable databases and photo directories. Local shop data,
  photos, credentials, runtime downloads and backups are excluded from Git.

## Start here this afternoon

1. Run the current backend and app together with `./run_dashboard.sh`, or restart
   `./run_backend.sh` and then F5 in Godot. An older backend is explicitly rejected
   for section-saving replies rather than falsely reporting Saved. Confirm all
   four sections on the real workshop records and check the Saved indicator.
2. Prove the standalone Android approach before promising a tablet build date.
   The workstation has Java, but Android SDK/adb and export templates were not
   found during the morning check. Godot's desktop Python launcher and desktop
   CEF addon do not become Android-compatible just by exporting the project.
   Validate runtime/storage/lifecycle, then mobile WebView and camera/picker.
3. Add native camera capture, then photo-label extraction with user confirmation
   of model/serial characters. Keep original photos and clear provenance.
4. Plan connected AI and automatic internet retrieval. No provider credentials,
   paid calls or budget were enabled. Choose a trial budget and safe credential
   delivery before activation; do not ship a shared provider secret in an APK.
   Embedded browsing currently does not read/synthesize results into answers.

Aim for a limited HawkLabs trial in the week of November 2, then fixes and a
one-week outside-shop trial if a shop agrees. Early December is a tentative
first-sale target, conditional on reliability and trial results. Hardware
purchase is still a budget-planning discussion; no tablet was bought or chosen.

See `TABLET-TRIAL-2026-10-28.md` for storage, technical findings and test commands.
See `SCREENSHOT-NOTES.md` for the included design and media captures.
