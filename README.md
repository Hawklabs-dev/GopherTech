# HawkLabs GopherTech

Local equipment workspace built with FastAPI, SQLite, and a Godot dashboard.

## Shop home

F5 now opens the GopherTech shop dashboard. Your existing Equipment, Bills to pay,
and Invoices to collect tools remain accessible from the left navigation.

- **Find a part:** build a research brief, find manufacturer reference sources
  inside the app, and prepare a supplier request in My parts list.
- **Check a problem / Repair help / Fabrication:** describe the task, add model
  details if known, and build a brief to copy or take to the in-app reference desk.
- **Manuals & diagrams:** browse the supported manufacturer directory, read
  HTML/PDF text, filter document text, follow supported document links, and view
  PDF page images without opening a browser.
- **Shop calculators:** convert length, torque, and US fluid ounces, or calculate
  two-stroke oil quantity from your own manufacturer-specified ratio.

No tool requires an equipment profile. Briefs and calculators work without the
backend; the reference reader, equipment and finance screens require it. Form
entries, questions and the parts list last only for the current session; copy
them before closing. Notes are not sent to manufacturer websites.

Paid AI setup and calls are paused by the owner. The question pad records your
questions; it does not generate answers. There are no paid provider integrations,
API keys, live stock/price checks, automatic purchases or verified fitment claims.
No browser launches occur from research buttons.

The reference directory currently covers Honda, Briggs & Stratton, Briggs Racing
and Vanguard sources. It ranks known sources and can construct a Honda model
lookup; it is **not** a live general web search or a guarantee of a matching
manual. Source pages may require interactive forms that the text reader cannot
run; try a direct supported PDF link in those cases. Confirm model, serial range,
region and publication applicability before using a document.

The supplied GopherTech logo and workshop reference are in
`Godot/gopher-tech/assets/`. Product requirements are in
`docs/PRODUCT_DIRECTION.md`. The original equipment scene still runs directly.

Shop checks (use a temporary project copy to avoid editor-cache changes):

```bash
godot --headless --path Godot/gopher-tech --script res://shop_smoke.gd
.venv/bin/python -B tests/run_dashboard_integration.py --references
```

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
text. Documents are held in a small five-minute memory cache, not the user DB.

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

Use the three buttons across the top of the dashboard to switch between
**Equipment**, **Bills to pay** (accounts payable), and **Invoices to collect**
(accounts receivable).

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
