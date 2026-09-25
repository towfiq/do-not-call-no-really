# DncWatchdog

Phoenix + SQLite app for tracking unsolicited call/text evidence as workflow-driven cases and generating demand-letter drafts.

## Features

- LiveView case queue (`/cases`) with workflow/status fields
- Mark communications as **violations** or **not a violation**; hide non-violations by default
- Legal entity + mailing address per case, evidence screenshot uploads, certified-mail letter drafts with relief demand
- Santa Clara County small-claims and civil complaint filing drafts with California filing-limit tracking ($12,500 cap, 2/year over $2,500)
- Filled official Judicial Council of California forms (SC-100 for small claims; SUM-100 and CM-010 for civil), attached automatically by the Chrome/Safari helper on Odyssey eFileCA up to the Service step
- Case detail view with workflow checklist and one-click advancement (gated on evidence requirements)
- Import mix task for normalized communication CSV files
- Local macOS import from Messages `chat.db` and Call History SQLite
- Export mix task for markdown demand-letter drafts per company/case

## Setup

1. Install deps and setup DB (creates `priv/repo/dnc_watchdog_dev.db`):

```bash
mix setup
```

No separate database server is required — the app uses a local SQLite file at `priv/repo/dnc_watchdog_dev.db`.

If you still have data in the old PostgreSQL dev database, copy it once with:

```bash
mix dnc.import_from_postgres
```

Uses `PGHOST`, `PGUSER`, `PGPASSWORD`, and `PGDATABASE` (defaults: `localhost`, `postgres`, `postgres`, `dnc_watchdog_dev`).

2. Start Phoenix:

```bash
mix phx.server
```

3. Open [http://localhost:4000](http://localhost:4000)

4. To fill official court forms, install the PDF form filler once:

```bash
mix dnc.setup_forms
```

This creates `priv/form_filler/.venv` (Python + pypdf) and downloads any missing blank
Judicial Council of California forms into `priv/judicial_forms`. Without it the app still generates the
narrative drafts, but the case page will say the form filler is missing.

## Triage violations in the UI

1. Open **Messages** (`/communications`) after import.
2. For each row, click **Violation** or **Not a violation**.
3. By default, **non-violations are hidden**. Use the filter toggles to show pending review or all statuses.
4. Click **Exclude sender** to dismiss a number now and on **future imports** (manage the list under **Excluded senders**).
5. Open a **Case** (`/cases/:id`) to add the defendant's legal name and mailing address, upload screenshot exhibits, and generate a certified-mail demand letter draft.

Case workflow steps: `intake` → `triage` → `evidence_review` → `draft_review` → `ready_to_send` → `sent` → `litigation_draft` → `ready_to_file` → `filed` → `archived`. Advancing past `evidence_review` requires at least one marked violation, a complete mailing address, and at least one uploaded attachment.

## Import from local macOS databases (recommended)

Reads SQLite databases directly (schema may vary by macOS version; adjust queries in `lib/dnc_watchdog/enforcement/local/` if needed):

- Messages: `~/Library/Messages/chat.db`
- Call History: `~/Library/Application Support/CallHistoryDB/CallHistory.storedata`

Your terminal (or Cursor) needs **Full Disk Access** in System Settings → Privacy & Security.

Import is read-only toward your macOS databases: the app copies `chat.db` / Call History to a temp file, opens that copy with SQLite `mode=ro` + `immutable=1`, and sets `PRAGMA query_only = ON`. The originals are never opened for writing.

```bash
export DNC_MY_PHONE="+1-555-000-1234"
mix dnc.import_local
```

With `DNC_MY_PHONE` set (or `--my-phone`), **outgoing texts and calls you placed are skipped** by default. Use `--include-outgoing` if you need them in the database.

By default, messages and calls from numbers (or iMessage emails) in **macOS Contacts** are skipped (`--skip-contacts`). Use `--no-skip-contacts` to import everything.

Options:

```bash
mix dnc.import_local --no-messages          # calls only
mix dnc.import_local --no-calls             # messages only
mix dnc.import_local --no-skip-contacts     # include people in Contacts
mix dnc.import_local --limit 1000
mix dnc.import_local --messages-db /path/to/chat.db --calls-db /path/to/CallHistory.storedata
mix dnc.import_local --contacts-db /path/to/AddressBook.sqlitedb
```

Incoming contacts without a company name become cases like `Caller 8001234567`.

### Incremental import (lookback window)

Only read recent messages/calls, and skip anything already stored:

```bash
export DNC_MY_PHONE="+1-555-000-1234"
mix dnc.import_local --lookback-days 7
```

Rows outside the window are ignored. Rows inside the window that were imported before are skipped as **Duplicates** (fingerprint deduplication).

Environment variable: `DNC_IMPORT_LOOKBACK_DAYS=7`

### Periodic import while the server runs

With `mix phx.server` running, enable background imports:

```bash
export DNC_MY_PHONE="+1-555-000-1234"
export DNC_PERIODIC_IMPORT=true
export DNC_IMPORT_LOOKBACK_DAYS=7
export DNC_IMPORT_INTERVAL_MS=900000   # 15 minutes
mix phx.server
```

Logs appear as `[PeriodicImport]` in the console. Configure defaults in `config/config.exs` under `:periodic_import`.

## Import communications (CSV)

Expected CSV columns:

`timestamp,channel,direction,from_number,to_number,duration_seconds,body,company`

Use:

```bash
mix dnc.import_csv data/example_communications.csv
```

Re-importing the same data is safe: duplicate rows are skipped automatically.

If you imported before deduplication existed, remove duplicate rows once:

```bash
mix dnc.dedupe              # delete extras and backfill fingerprints
mix dnc.dedupe --dry-run    # preview only
```

Remove outgoing texts/calls you already imported (uses `DNC_MY_PHONE` or `--my-phone`):

```bash
mix dnc.remove_outgoing --dry-run
mix dnc.remove_outgoing
```

Remove communications from macOS Contacts that were imported before contact filtering worked:

```bash
mix dnc.purge_contacts --dry-run
mix dnc.purge_contacts
```

Check whether a number is in Contacts before purging:

```bash
mix dnc.check_contact 6504653718 8476688844
```

## Export demand letters

```bash
mix dnc.export_letters output/letters "Your Name" "+1-555-000-1234" 2020-01-01
mix dnc.export_letters output/letters "Your Name" "+1-555-000-1234" 2020-01-01 --pdf
```

Markdown drafts are written to `output/letters/*.md`. With `--pdf`, matching PDFs are also created with screenshot exhibits embedded after the letter.

From the web UI, open a case with a generated letter draft and click **Download PDF with exhibits**.

PDF export uses [ChromicPDF](https://github.com/bitcrowd/chromic_pdf) and requires Google Chrome or Chromium installed locally.

## Export small-claims filing drafts

Generates Santa Clara County filing packets (for cases with marked violations):

```bash
mix dnc.export_filings output/filings
mix dnc.export_filings output/filings --pdf
```

From the web UI, open a case and click **Generate court filing**, then **Download filing PDF with exhibits**.

To e-file in Santa Clara County, use **Odyssey eFileCA** (the official portal — no extra provider fee). On a case, click **Fill eFileCA form**. The Chrome or Safari helper opens [california.tylertech.cloud](https://california.tylertech.cloud/OfsEfsp/ui/landing) and walks the wizard: Start Filing on the dashboard, then Start New Case, then Case Information, Parties, and Filings. Each court form becomes its own filing with its own filing code, since eFileCA allows one lead document per filing. The helper stops at Service so you review, submit, and pay yourself.

The helper drives Tyler's Forge web components: dropdowns are autocompletes that only
open on focus plus ArrowDown, and the upload control hides its file input in a shadow
root. If the portal's markup changes, the helper says so in its panel and in a flash
message on the case page rather than failing silently.

Chrome loads `priv/chrome_extension` unpacked — after editing it, hit Reload on
`chrome://extensions`. Safari needs a build, and it loads the copy in `/Applications`
rather than Xcode's build output, so install with:

```bash
mix dnc.build_safari_helper
```

The app is ad-hoc signed, so Safari only loads it after **Develop → Allow Unsigned
Extensions** — which Safari forgets every time it quits. Grant the extension access to
both `california.tylertech.cloud` and `localhost`; it needs both to copy case data into
the portal.

The forms follow the recommended venue: small claims files **SC-100**, civil files the complaint
with **SUM-100** and **CM-010** behind it. Download them individually from the case page, or take
the whole thing as one PDF with **Download filled filing packet**.

Review all generated filings before submitting to the court. Blank forms come from
[courts.ca.gov](https://courts.ca.gov/find-court-forms) and are refreshed by `mix dnc.setup_forms`.

## Export civil complaint drafts

```bash
mix dnc.export_civil_complaints output/civil
mix dnc.export_civil_complaints output/civil --pdf
```

## Notes

- Review all generated letters before sending.
- Review all generated court filings before filing.
- This project is software tooling and not legal advice.
