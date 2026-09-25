#!/usr/bin/env python3
"""Fill Judicial Council of California AcroForm PDFs and concatenate them into one packet.

Reads a JSON job from the file given as the first argument, or from stdin:

    {
      "output": "/tmp/packet.pdf",
      "parts": [
        {"template": "priv/judicial_forms/sc100.pdf", "fields": {"FQN": "value"}},
        {"pdf": "/tmp/statement_of_facts.pdf"}
      ]
    }

Prints a JSON report to stdout: {"ok": true, "filled": n, "unmatched": [...]}.

The blank forms ship encrypted with an empty user password and carry an XFA
packet. Viewers prefer XFA over the AcroForm values we set, so the XFA entry is
dropped and NeedAppearances is set so the viewer regenerates field appearances.
"""

import json
import logging
import sys

from pypdf import PdfReader, PdfWriter
from pypdf.generic import BooleanObject, NameObject

# The blank forms have sloppy encryption padding that pypdf recovers from; the
# warnings would otherwise land in the caller's logs on every fill.
logging.getLogger("pypdf").setLevel(logging.ERROR)
logging.getLogger("pypdf._reader").setLevel(logging.ERROR)
logging.getLogger("pypdf._encryption").setLevel(logging.ERROR)


def read_template(path):
    reader = PdfReader(path)
    if reader.is_encrypted:
        reader.decrypt("")
    return reader


def qualified_name(annot):
    parts = []
    node = annot
    seen = 0
    while node is not None and seen < 32:
        title = node.get("/T")
        if title is not None:
            parts.append(str(title))
        parent = node.get("/Parent")
        node = parent.get_object() if parent is not None else None
        seen += 1
    return ".".join(reversed(parts))


def on_state(annot):
    appearances = annot.get("/AP")
    if appearances:
        normal = appearances.get("/N")
        if normal:
            for key in normal.keys():
                if key != "/Off":
                    return NameObject(key)
    return NameObject("/Yes")


def truthy(value):
    if isinstance(value, bool):
        return value
    return str(value).strip().lower() in ("1", "true", "yes", "x", "on")


def field_type(annot):
    kind = annot.get("/FT")
    parent = annot.get("/Parent")
    if kind is None and parent is not None:
        kind = parent.get_object().get("/FT")
    return kind


def fill(writer, template, fields):
    reader = read_template(template)
    start = len(writer.pages)
    writer.append(reader)

    wanted = dict(fields)
    matched = 0

    for page in writer.pages[start:]:
        on_page = {}
        for annot_ref in page.get("/Annots") or []:
            annot = annot_ref.get_object()
            if annot.get("/Subtype") != "/Widget":
                continue
            name = qualified_name(annot)
            if name not in wanted:
                continue
            value = wanted.pop(name)
            if field_type(annot) == "/Btn":
                on_page[name] = on_state(annot) if truthy(value) else NameObject("/Off")
            else:
                on_page[name] = "" if value is None else str(value)

        if on_page:
            # pypdf writes the value and a matching appearance stream, so the text
            # shows even in viewers that ignore NeedAppearances.
            writer.update_page_form_field_values(page, on_page, auto_regenerate=False)
            matched += len(on_page)

    return matched, list(wanted.keys())


def main():
    if len(sys.argv) > 1:
        with open(sys.argv[1]) as handle:
            job = json.load(handle)
    else:
        job = json.load(sys.stdin)
    writer = PdfWriter()
    filled = 0
    unmatched = []

    for part in job.get("parts", []):
        if part.get("template"):
            count, missing = fill(writer, part["template"], part.get("fields") or {})
            filled += count
            unmatched.extend(missing)
        elif part.get("pdf"):
            writer.append(PdfReader(part["pdf"]))

    writer.set_need_appearances_writer(True)
    acroform = writer._root_object.get("/AcroForm")
    if acroform is not None:
        acroform = acroform.get_object()
        if "/XFA" in acroform:
            del acroform["/XFA"]
        acroform[NameObject("/NeedAppearances")] = BooleanObject(True)

    with open(job["output"], "wb") as handle:
        writer.write(handle)

    json.dump({"ok": True, "filled": filled, "unmatched": unmatched}, sys.stdout)


if __name__ == "__main__":
    try:
        main()
    except Exception as error:  # surfaced to the Elixir caller
        json.dump({"ok": False, "error": f"{type(error).__name__}: {error}"}, sys.stdout)
        sys.exit(1)
