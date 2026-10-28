# Tablet helper checkpoint — October 28, 2026

**Afternoon update:** Desktop voice dictation, Clear results and Firecrawl page
research with local AI passage selection are now implemented and owner-reviewed.
See `VOICE-AND-FIRECRAWL-2026-10-28.md` and `HANDOFF-2026-10-28-PM.md`. Android,
camera capture and hosted AI answering remain separate work. Earlier statements
below describe the morning checkpoint and do not override the afternoon update.

## Approved direction

The owner approved a standalone tablet helper organized by work order number,
with Wi-Fi and eventual connected AI. Keep the permanent header and large touch
buttons: Go For Gopher, Work Area, Parts, Tools. No required job
statuses, invoices, payments, inventory, POS or parent computer in this version.
Tools remain available. The early December release date is a working target,
subject to HawkLabs testing and then a one-week outside-shop trial.

## Implemented in this desktop checkpoint

- Go For Gopher is the opening quick-search screen. In Work Area, use New work order to enter a shop number or leave it blank for
  an automatic `WO-…` identifier. Search by number, machine description or title;
  tap a saved entry once to open it.
- Permanent branding, current order number and machine summary beside the logo,
  save/request feedback and four compact labelled Gopher navigation buttons.
  Navigation has 44-pixel minimum touch targets and wraps for portrait widths.
- Work Area combines the inline order picker/creation controls, machine details,
  research, notes and photos. The order picker closes after selection; Find /
  switch order brings it back without leaving the page. New orders have an
  optional number, then use the same active-order machine editor.
- Parts, Troubleshoot, Repair and Fabricate populate a visibly labelled panel
  below their buttons, with different prompts and actions. They reuse one editor layout but load separate, durable task and notes values
  for each section. Photos switches that panel to local attachments.
  The reference reader shares the notes editor rather than showing another pad.
  Quantity lives in the Parts list. Long legacy UUID-based order numbers are
  abbreviated for display only; the saved identifiers are unchanged.
- Workshop tools use direct touch buttons instead of the old Tools dropdown.
  Finance navigation is removed; existing finance storage and APIs remain intact.
- Optional machine description and notes save with the order. The description
  is a free-text record, not a new equipment record or a verified machine match.
  Existing question/reference routing continues to identify machines from the
  conversation; structured identity integration is a later step.
- Existing saved conversations migrate additively to numbered work orders.
  No tables or existing records are deleted. Legacy archive records remain
  accessible, without imposing a status workflow on new work orders.
- Switching screens retains their positions. Question drafts, research form
  drafts and reference-tool state stay separate for each order during the app
  session. Section tasks/notes, parts, conversations and references survive
  restart; unsubmitted conversation questions, generated-brief displays and
  scroll positions do not yet survive exit.
- Pending note/machine saves flush before switching or creating an order.
  New work order creation can wait behind saving without another tap. Failed
  saves keep edits locally in memory and prevent the queued switch. The research panel shows
  a Retry save button when unsaved changes remain after a failed request. Close only after saving is confirmed.
- Photos supports Choose Photo -> preview -> Keep Photo. It preserves the
  original JPEG/PNG/WebP bytes, limited to 12 MiB and 40 megapixels per image.
  Saved photos reopen on their own order after app/backend restart. There is
  no photo upload, AI reading, OCR or camera capture in this checkpoint.

## Photo storage and backup

Pictures live under Godot's local application data directory:
`user://work-order-photos/<internal-job-UUID>/`. On this Linux installation the
normal location is `~/.local/share/godot/app_userdata/GopherTech/work-order-photos/`.
Pictures are not stored inside SQLite or Git. Back up **both** the database and
this directory; transferring the database alone does not transfer pictures.
The original selected file is not modified. A `.part` file and atomic rename
avoid presenting an interrupted write as a saved image. No deletion UI yet.
Tests override `GOPHERTECH_PHOTO_ROOT` to an isolated temporary directory.

## Android delivery findings

This is a **desktop build with tablet-oriented layout**, not an Android APK.
Java is available on the workstation; `adb`, Android SDK tooling and installed
Godot export templates were not found during this check. No tablet/emulator
installation or native camera test has been performed.

The desktop launcher owns a loopback FastAPI server in the workstation's Python
runtime. A Godot Android export does not include that Python environment. The
current Godot CEF addon lists desktop binaries (Windows, Linux, macOS), with no
Android entry in the installed `.gdextension` manifest.

Preferred next proof, retaining the existing code and local data approach:

1. Set up the Android export toolchain and a disposable Godot APK.
2. Prove an Android application lifecycle that starts/stops an embedded Python
   backend and stores SQLite under application-private storage. A native Android
   plugin/runtime bridge is an integration task, not implemented or guaranteed.
3. Prove local save/reopen across process death before porting more features.
4. Replace desktop CEF with an Android-compatible in-app WebView integration.
5. Connect the Android photo picker/camera with permissions and durable local
   copies, then test orientation, the soft keyboard, background/resume and
   network loss on an actual device.

Do not substitute a shop-PC server and call that a standalone tablet. If the
embedded runtime proof is disproportionately complex, review the mobile storage
and service boundary with the owner before selecting a different implementation.

Official references consulted:
- https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_android.html
- https://docs.godotengine.org/en/4.6/tutorials/platform/android/android_plugin.html
- https://github.com/dsh0416/godot-cef
- https://docs.godotengine.org/en/stable/classes/class_image.html

## AI and research

No paid provider, credentials or calls were enabled. Current answers remain
reference mode. Wi-Fi alone does not provide AI integration. Select a provider,
a small trial budget, and a credential delivery design before activation; do not
embed a shared provider secret in a distributable tablet app. Automatic internet
retrieval, evidence selection and image interpretation remain separate work.

## Verification and review

Run against temporary databases and temporary photo storage:

```bash
.venv/bin/python -B -m unittest discover -s tests -q
GOPHERTECH_API_URL=http://127.0.0.1:1 godot --headless --path Godot/gopher-tech --script res://milestone_one_smoke.gd
GOPHERTECH_API_URL=http://127.0.0.1:1 godot --headless --path Godot/gopher-tech --script res://shop_smoke.gd
.venv/bin/python -B tests/run_work_order_integration.py
.venv/bin/python -B tests/run_prototype_integration.py
.venv/bin/python -B tests/run_dashboard_integration.py --references
```

The work order integration covers two app processes and two backend lifetimes,
custom numbers, search, queued creation/switching, machine/notes persistence,
per-order question/research drafts, original-photo persistence/isolation, and
navigation at 1100x800, 800x1100 and 390x844. Desktop layout checks do not establish
physical tablet touch, camera, battery or Android compatibility.

Restart the running desktop app to load the new scripts. Restart its backend if
it is not using auto-reload; initialization applies the additive migration.
For one desktop command, use `./run_dashboard.sh`.

Validated at this checkpoint:
- 90 Python tests passed.
- Work order interface and preserved workshop-tool smoke checks passed.
- Work order workflow/reopen integration passed, including offline-save blocking
  and reconnect, photo byte preservation, and per-order reference isolation.
- Existing conversation workflow/reopen and HTML/PDF reference integration passed.
- The earlier checkpoint passed real embedded-browser input checks. In the
  unified-work-area revision, the live-pointer retest could not obtain desktop
  focus, so its click/wheel results are unverified. HTML/PDF reference
  integration and reference-reader visibility checks pass.
- Rendered desktop and portrait previews were inspected; screenshots use clearly
  labelled example records, not entries added to the shop database.
- At the initial data-preservation check, SQLite integrity was `ok` and all
  pre-existing rows matched the pre-change backup. Later owner test entries
  remain local; automated checks use disposable databases.
- `git diff --check` passed. The owner authorized committing and pushing the
  morning checkpoint to the existing repository.

## Unified work area revision

The owner requested one scrollable work area instead of separate Work Orders,
Job Details and Photos screens. The four main buttons now open Go For Gopher,
Work Area, Parts and Tools. Each work-area mode shows its own heading, prompts
and actions below the buttons while reusing the same task/notes inputs.

The old creation-only machine field is removed. Opening an order clears and
closes the new-number draft. A late open response cannot merge unsaved old-order
notes into the incoming record: the switch waits for saving, then reopens the
requested order. The regression test edits a Ford F250 order, simulates a late
response while its note is being edited, switches to another machine and back,
and checks each record's own fields and photo attachments after restart. Work-area
scroll positions are also tested independently across order switches.

Rendered previews use example records:
- `docs/screenshots/work-area-troubleshoot-desktop.png`
- `docs/screenshots/work-area-photos-desktop.png`
- `docs/screenshots/work-area-repair-portrait.png`

Section task/notes values and machine descriptions are durable. The selected
mode, generated-brief display and scroll positions remain session-only. Existing shop records were not rewritten to guess what a prior draft
was intended to describe.

## Section auto-save correction

Parts, Troubleshoot (`diagnose`), Repair and Fabricate now persist independent
`task` and `notes` entries in the additive `workshop_jobs.section_drafts` JSON
column. A blank section loads blank fields; changing sections flushes the
previous draft, and selecting the current section does not erase an edit.
Machine details and photos remain common to the work order. Generated briefs
are kept per section during the session and can be rebuilt after restart.

The existing `notes` API field remains compatible with Parts notes. Historical
shared notes are preserved under Parts; the application does not copy those
old notes into every section or infer which section the author intended.
Older backends that do not confirm section storage trigger a restart message
and leave edits pending rather than falsely reporting a successful save.

Regression coverage includes four distinct task/note pairs, untouched blank
sections, Photos round-trips, order isolation, two app/backend lifetimes,
invalid payload rejection and legacy-notes compatibility. Restart the backend
if it did not auto-reload, then restart the Godot run to load this revision.
