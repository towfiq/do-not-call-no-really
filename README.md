# DncWatchdog

Phoenix + SQLite app for tracking unsolicited call/text evidence as workflow-driven cases and generating demand-letter drafts.

## Features

- LiveView case queue (`/cases`) with workflow/status fields
- Mark communications as **violations** or **not a violation**; hide non-violations by default
- Legal entity + mailing address per case, evidence screenshot uploads, certified-mail letter drafts with relief demand
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

## Triage violations in the UI

1. Open **Messages** (`/communications`) after import.
2. For each row, click **Violation** or **Not a violation**.
3. By default, **non-violations are hidden**. Use the filter toggles to show pending review or all statuses.
4. Click **Exclude sender** to dismiss a number now and on **future imports** (manage the list under **Excluded senders**).
5. Open a **Case** (`/cases/:id`) to add the defendant's legal name and mailing address, upload screenshot exhibits, and generate a certified-mail demand letter draft.

Case workflow steps: `intake` → `triage` → `evidence_review` → `draft_review` → `ready_to_send` → `sent` → `archived`. Advancing past `evidence_review` requires at least one marked violation, a complete mailing address, and at least one uploaded attachment.

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

## Notes

- Review all generated letters before sending.
- This project is software tooling and not legal advice.
