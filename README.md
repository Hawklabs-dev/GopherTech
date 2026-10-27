# HawkLabs GopherTech

Local equipment workspace built with FastAPI, SQLite, and a Godot dashboard.

For normal desktop use, run `./run_dashboard.sh`. It starts its own local backend
and closes that backend when the app exits. F5 in the Godot editor still requires
`./run_backend.sh` separately. Every app start opens a blank question workspace;
continue older work explicitly through Menu → Saved Jobs.

Interactive manufacturer lookup waits at most eight seconds before saving an
explicit timeout reply. Outstanding lookups are bounded; late results do not
rewrite saved answers. General web search opens inside the app and does not
read or answer from search results. See `docs/QUESTION-READINESS-2026-10-27.md`
for tested behavior and the remaining shop-readiness blocker.

## Interactive reference webpages

HTML references now open as live webpages inside the conversation's reference
area, with Back, Forward, Reload, Stop, Saved text and Open externally controls.
The conversation's **Search the web for this question** action also opens results
in this embedded browser. Only the explicitly labeled external actions launch
the system browser.
Links and webpage scrolling work inside the app. Saved text is the locally
archived extract; live browsing does not automatically archive subsequent pages
or provide evidence for an answer. PDF references retain the saved text and
original-page reader.

The desktop browser uses [Godot CEF 2.1.0](https://github.com/dsh0416/godot-cef/releases/tag/v2.1.0).
Restart the Godot editor once after adding it, then run F5 (with the backend
running) or `./run_dashboard.sh`. The browser is created only when opening a
reference, so startup remains a blank question workspace.

Native browser files are installed locally and excluded from Git. To set up a
new Linux x86_64 checkout (other platforms use the upstream release instructions):

```bash
.venv/bin/python tools/setup_browser.py
godot --headless --editor --path Godot/gopher-tech --import
```

The explicit setup command downloads about 655 MiB and checks the pinned SHA-256
before extracting only the current platform's runtime. No runtime download takes
place at app startup. Without the runtime, saved text and external links remain
available. Linux uses software webpage rendering to avoid driver-specific GPU
interop requirements. Browser camera/microphone permissions and file dialogs
are disabled; normal page JavaScript and HTTPS remain enabled.

Live integration check (opens a disposable app window, no shop database writes):

```bash
godot --path Godot/gopher-tech --script res://browser_integration.gd
```

Verified on this Linux desktop with Godot 4.7.2: the real Honda owner-manual page
renders inside the full app; pointer clicks reach page JavaScript; wheel events
scroll the webpage without scrolling the conversation; Saved text and Return to
live webpage switch correctly; resetting clears the browser. The live test
passes with both the normal Vulkan renderer and OpenGL compatibility renderer.
The 84 Python tests, prototype restart/recovery integration, reference/PDF
integration and Milestone 1 interface smoke check also pass.

## Shop Buddy — Milestone 1 review

The owner acceptance gate is Milestone 1 only. The current interface has a compact
branded header, one question box, one Ask action and a small **Menu** for history
and existing tools. Replies use visible exchange separators and evidence links attached to the
answer that retrieved them. Raw PDF extracts are kept out of technical answers;
source pages remain available for inspection. The primary layout adapts to a phone-sized portrait viewport.

Restart `./run_backend.sh`, press F5 in Godot, and try the interface before
advancing. AI is still unavailable; this milestone only connects the existing
reference-mode backend. Photo attachment and mobile platform export packages
are not implemented. Later research/provider work is preserved but parked.

```bash
godot --headless --path Godot/gopher-tech --script res://milestone_one_smoke.gd
```

## Question-first prototype

F5 opens a simple screen with the GopherTech logo, **What are we working on?**,
one large question box, **Ask GopherTech**, and the conversation below.
The compact Menu contains three navigation choices:

- **Ask GopherTech:** type a question, answer a relevant follow-up, and open
  suggested manufacturer references inside the conversation screen.
- **Saved Jobs:** reopen a conversation, start a new job, or edit current-job notes.
- **Tools:** one selector gives access to the existing parts/manual/diagram,
  fabrication, calculator, equipment, payable and receivable tools.

This is explicitly **reference mode, not AI**. The backend uses limited,
deterministic routing and guided checklists for common requests. It remembers
explicit engine/model, fuel, serial, year and region information within the job.
It cannot reason about arbitrary symptoms, identify photos or infer an unknown
specification. Unsupported questions get an honest limitation or follow-up.
No AI provider, keys, billing, purchases or paid calls are enabled.

Start (or restart) `./run_backend.sh`, then F5 in Godot. No equipment profile is
required. Asking the first question automatically creates a workshop job in the
existing SQLite database. Subsequent questions, notes, parts lists and reference
URLs are saved with it. Read document text and link metadata are archived so that
saved copies can reopen even when the website is unavailable. PDF page images
still need the original PDF to be reachable (or in the short-lived memory cache).
If the backend is unavailable, unsaved questions stay in the input and the UI
reports that saving was not confirmed; do not close the app before reconnecting.

The limited manufacturer directory covers Honda, Briggs & Stratton, Briggs Racing
and Vanguard. Conversation suggestions filter by recognized brand and prioritize
model-specific locations. A suggested URL is not a successful search, a verified
manual, or proof of compatibility. Region, serial range, year, revision and
applicability must still be checked. Owner manuals may lack service/wiring/
hydraulic diagrams. Unsupported manufacturers, missing documents and blocked
interactive sites are reported honestly. Opening an external copy is an optional
link in the document view; it is not the default action.

Use the source links beneath the conversation to read documents in app. Actual
serial-table text is retained with document links where the source page supplies
it. Saved Jobs can resume the context after both app and backend restart.
Tool briefs and calculator input fields remain transient; durable job notes,
parts, questions and read references use the new additive workshop tables.
Existing equipment, loans and finance tables and routes are preserved.

Verification (prefer a temporary project copy to avoid editor-cache changes):

```bash
.venv/bin/python -B -m unittest discover -s tests -v
godot --headless --path Godot/gopher-tech --script res://shop_smoke.gd
.venv/bin/python -B tests/run_dashboard_integration.py --references
.venv/bin/python -B tests/run_prototype_integration.py
```

The prototype integration uses original document fixtures and one disposable
SQLite database across **two backend lifetimes and two Godot processes**. No
manufacturer network access or paid API calls occur during this test.

## Reference reader requirements and limits

`research.py` uses Python's standard library and the existing FastAPI dependency.
PDF text and original page images use the free Poppler command-line utilities
`pdftotext` and `pdftoppm` on PATH (on Fedora, the `poppler-utils` package).
The API reports a clear error if either required utility is missing; HTML reading
still works. No dependency installation or paid calls occur automatically.

Only HTTPS URLs on the supported manufacturer hosts are fetched. Every redirect
is checked, DNS addresses must be public, and connections are pinned to a checked
address while preserving TLS hostname verification. The reader does not execute
JavaScript, submit forms, use logins, or accept arbitrary private/local URLs.
Downloads are limited to 8 MiB, extracted text to 60 PDF pages / 100,000 characters,
and page images to pages 1–60 at a maximum 1,400-pixel dimension. HTML is text-only;
PDF page images retain diagrams and layout. Scanned PDFs may have no searchable
text. Raw downloads use a small five-minute memory cache. Read text/link snapshots opened through a job are persisted in the local user DB; no raw PDF or rendered page image is stored there.

Reference endpoints:

- `POST /research/sources`: `{ "query": "Honda GX160 manual" }`.
- `POST /research/document`: `{ "url": "https://…" }`.
- `POST /research/pdf-page`: `{ "url": "https://…pdf", "page": 1 }`.
- `GET /research/status`: reader capabilities and explicit disabled AI status.

The reference integration test uses original HTML/PDF fixtures through a real
temporary HTTP backend; it does not call external sites or paid APIs.

## Run the existing backend

From a terminal:

```bash
cd ~/HawkLabs/GopherTech
source .venv/bin/activate
python -m uvicorn main:app --reload --host 127.0.0.1 --port 8000
```

The existing virtual environment has FastAPI and Uvicorn installed.
Open http://127.0.0.1:8000/docs for interactive API documentation.
Stop the server with Ctrl+C.

## Current API

- `GET /`: application information.
- `GET /health`: returns `{"status":"healthy"}`.
- `GET /equipment`: returns `{"equipment":[...]}`, ordered by ID.
- `POST /equipment`: creates equipment and returns its ID and a message (HTTP 201).
  `name` is required; `manufacturer`, `model`, and `notes` are optional.

Read-only checks while the server is running:

```bash
curl http://127.0.0.1:8000/health
curl http://127.0.0.1:8000/equipment
```

Using POST in the interactive documentation writes to the local database.

## Project files

- `main.py`: FastAPI routes and startup initialization.
- `database.py`: SQLite location and equipment table initialization.
- `gophertech.db`: existing local equipment data. Preserve this file.
- `Godot/gopher-tech/project.godot`: Godot project.
- `Godot/gopher-tech/gopher_tech_main.tscn`: starter Control scene.

## Open the equipment dashboard

Start the backend above, then open a second terminal:

```bash
cd ~/HawkLabs/GopherTech
./run_dashboard.sh
```

Or open `Godot/gopher-tech/project.godot` in Godot 4.7 and press F6 on
`equipment_dashboard.tscn`, or F5 to run the configured dashboard main scene.
The original `gopher_tech_main.tscn` starter scene is preserved.

The dashboard puts checking equipment in and out first:

1. Find and select the equipment.
2. To take it, enter the person's name and press **Check out**.
3. To return it, select it and press **Check in**.

Each row shows **Available** or **Out with [name]**. The counts above the list
show what is available and what is out. You can also search by borrower name.
Use **Add new equipment** to open the equipment-entry form.

The dashboard loads your equipment, searches across names/manufacturers/models/
notes and borrower names, displays record details, and adds equipment. Name is required in the form.
Refresh retries the connection. If a save cannot be confirmed, refresh before
retrying to avoid duplicate records. Existing API clients keep the same routes
and response shapes. Search currently filters the inventory already loaded in
memory. Editing and deleting records are not implemented yet.

The default backend address is `http://127.0.0.1:8000`. For another local port:

```bash
GOPHERTECH_API_URL=http://127.0.0.1:8001 ./run_dashboard.sh
```

This increment targets the native desktop Godot app, not a browser export.

## Data and development precautions

The backend uses `gophertech.db` beside `database.py`, regardless of the terminal's
working directory. Startup creates the equipment table if missing. Do not delete
or replace the database to reset development state. Stop the backend before
making a simple file-copy backup, and keep backups outside version control.

The root `.gitignore` excludes the virtual environment, generated Python/Godot
files, local SQLite data, and local environment files. It does not delete files
or remove anything already tracked by Git.

## Verify changes safely

From the project root, with the existing virtual environment:

```bash
.venv/bin/python -B -m unittest discover -s tests -v
godot --headless --path Godot/gopher-tech --script res://dashboard_smoke.gd
.venv/bin/python -B tests/run_dashboard_integration.py
```

The API suite uses Python's built-in unittest runner and patches both database
references to a fresh temporary SQLite file before entering the app lifespan.
The integration check starts a temporary backend on an OS-selected loopback port
and runs real Godot GET/POST requests against its disposable database. It shuts
down the temporary server afterward. Neither test uses your equipment database.
The smoke check cancels its initial GET before testing dashboard states.
No additional test dependencies are required.

Direct runtime dependencies are recorded in `requirements.txt` from the installed
versions. The existing virtual environment is preserved.

## Development notes

SQLite connections are now explicitly closed after each operation. Existing
routes, response formats, database location, and table structure are unchanged.
The dashboard HTTP client follows the official Godot reference:
https://docs.godotengine.org/en/stable/classes/class_httprequest.html

Suggested next increment: equipment editing with API validation and isolated
tests before adding more inventory features.


## Checkout records

On the next backend startup, initialization adds an `equipment_loans` table and
a unique index for active checkouts. Existing equipment rows and fields are
preserved. Each checkout keeps the person's name and a UTC timestamp. Returning
an item records a return timestamp and keeps that checkout in the database.
The UI shows current availability; a checkout-history screen is future work.

New API endpoints:

- `GET /equipment/availability`: equipment with status, borrower, checkout ID,
  and checkout time. The original `GET /equipment` response remains unchanged.
- `POST /equipment/{id}/checkout`: JSON `{"borrower":"Sam"}`.
- `POST /equipment/{id}/checkin`: JSON `{"checkout_id":1}`. Send the active
  checkout ID returned by availability, so a stale screen cannot return a newer loan.

An item can have only one active checkout. Conflicts return HTTP 409 and unknown
items return HTTP 404. Borrower names are required and limited to 120 characters.
After an uncertain response, refresh before trying again. Actions are disabled
when the availability list cannot be refreshed. Names are entered directly;
this increment does not add employee accounts or sign-in.

Restart an already-running backend after this update so the new checkout table
and endpoints become available. The update was tested against both fresh and
original-format temporary databases.

## Bills to pay and invoices to collect

Choose **Tools**, then select **Equipment records**, **Bills to pay** (accounts payable), or **Invoices to collect** (accounts receivable).

To add a record, choose **Add a bill** or **Add an invoice**. Enter the supplier
or customer, bill/invoice number, issue date, due date, currency, and the existing
bill or invoice's total including tax. Dates use `YYYY-MM-DD`. Choose CAD, USD,
EUR, or GBP explicitly; there is no assumed currency and no currency conversion.
The amount must be positive with at most two decimal places.

The list shows the remaining balance, due date, and whether the record is open,
part paid, overdue, or paid. Select it to see its payment history. Search finds
names and reference numbers. Outstanding and overdue totals remain separate for
each currency. Due-today items become overdue on the following server date.

To record a payment that has already happened, select the bill or invoice,
enter its amount and date, optionally add a receipt/transfer reference, and
choose **Record payment made** or **Record payment received**. Partial payments
reduce the remaining balance. Overpayments and future-dated payments are
rejected. Recording does not transfer money or email a customer.

SQLite stores money in integer cents; the API accepts decimal amounts and returns
formatted decimal strings plus cent values. Writes are transactional, and request
keys protect retries from duplicate documents/payments. The desktop retains the
same key for an unchanged retry during that session. After an interrupted save,
refresh and inspect payment history before entering another payment. Payment
entry drafts are kept separately for each selected document during the session.

Startup adds `finance_documents` and `finance_payments` tables and an index,
preserving equipment and checkout records. Backend implementation is in
`finance.py`; the Godot interface is in `finance_dashboard.gd`.

API endpoints:

- `GET /finance/documents`: documents, totals by side/currency, and as-of date.
- `GET /finance/documents/{id}`: document balance and recorded payments.
- `POST /finance/documents`: kind (`payable`/`receivable`), party, reference,
  issue_date, due_date, currency, amount (decimal string), notes, and request_key
  (UUID). Reusing a key with different details returns HTTP 409.
- `POST /finance/documents/{id}/payments`: amount (decimal string), paid_on,
  reference, and request_key (UUID).

Duplicate bill/invoice numbers for the same supplier/customer, side, and currency
are rejected. Payment dates must be on or after the issue date and no later than
today. Balances cannot be overpaid, including by simultaneous requests.

Run the finance desktop checks against a disposable database:

```bash
.venv/bin/python -B tests/run_dashboard_integration.py --finance
```

The usual unittest command includes finance tests. Existing equipment checks
remain available with `tests/run_dashboard_integration.py` without `--finance`.

This increment tracks existing bills/invoices and payments. Invoice PDF creation,
email delivery, tax calculation/filing, bank reconciliation, refunds/credit notes,
and entry correction/reversal screens are future work. Existing entries cannot
be edited or deleted through this first interface. It is not a full general
ledger. The validation APIs used here are documented at:
https://docs.pydantic.dev/latest/api/standard_library_types/

## Conversation reference safeguards

A newly identified model replaces the previous machine context. Spark-plug
questions start a fresh specification lookup. Unknown machine identities do not
reuse brand-only saved documents. Model matching is required before a retrieved
PDF can be offered as evidence; extracted text alone does not verify a technical
answer. The current reference engine returns a short limitation and one follow-up
instead of promoting PDF passages to repair instructions.

New replies save their evidence links with the message. Earlier replies retain
those links when the machine changes or the job is reopened. Legacy job sources
remain in collapsed **Job reference history**; their original message association
cannot be reconstructed. Legacy raw PDF replies display a limitation in the UI
while their stored conversation text remains intact.

## Conversation archive and targeted web search

Use **Archive conversation & start new** below Ask GopherTech to mark the
current conversation archived in SQLite and clear the working screen. Messages,
notes, parts and reference snapshots are preserved. Saved Jobs includes archived
conversations with an `[Archived]` label; continuing with a new question makes
one active again. Startup opens a clean question workspace; use Saved Jobs to resume
a conversation explicitly. Existing jobs gain
a nullable `archived_at` column on backend startup.

Honda `TRX 200` and `200 TRX` are recognized as `TRX200`. New explicit questions
replace the previous task while short identity follow-ups retain the task.
When local evidence is insufficient, **Search the web for this question** opens
a targeted query in the device browser. This is a browser handoff, not automatic
result retrieval or deep research. Automatic general web search and synthesis
are still unimplemented; no AI or paid search API has been enabled.
