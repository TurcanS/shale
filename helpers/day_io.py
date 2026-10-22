"""Export, import and backup of the Day store: JSON (everything), CSV (one row per order), Markdown (one list per
site); import of a Shale JSON export or a Todoist CSV export file. No network."""
import csv
import datetime as dt
import io
import json
import os
from pathlib import Path
import re
import sqlite3

FORMATS = {"json": ".json", "csv": ".csv", "md": ".md"}
SOURCES = {"json": ".json", "todoist": ".csv", "plain": ""}
ORDER_KEYS = ("kind", "text", "notes", "site", "section", "tags", "priority", "dueAt", "allDay", "deadlineAt", "durationMin",
              "rule", "ruleFromDone", "doneAt", "quietSeconds", "alerts")
MONTHS = {name: number for number, name in enumerate(("jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"), 1)}


def file_path(value, suffix, must_exist=False):
    """An absolute or ~/ path with the suffix whose folder exists (and, for reading, which is a file)."""
    if not isinstance(value, str) or not (value.startswith("~/") or value.startswith("/")) or "\n" in value:
        raise ValueError("Enter a file path beginning with / or ~/.")
    if suffix and not value.endswith(suffix):
        raise ValueError("The file must end in " + suffix + ".")
    path = Path(value).expanduser()
    if must_exist and not path.is_file():
        raise ValueError(str(path) + " doesn't exist.")
    if not must_exist and not path.parent.is_dir():
        raise ValueError("The folder " + str(path.parent) + " doesn't exist.")
    return path


def write_private(path, text):
    """Orders can be private: the file is readable by its owner only, written whole or not at all."""
    temporary = path.with_name(path.name + ".part")
    descriptor = os.open(temporary, os.O_CREAT | os.O_WRONLY | os.O_TRUNC, 0o600)
    with os.fdopen(descriptor, "w", encoding="utf-8", newline="") as handle:
        handle.write(text)
    os.replace(temporary, path)


def orders_of(store):
    """Every order, open and cleared, with its parent's position in the list instead of its id."""
    orders = store.orders(1)
    index = {order["id"]: number for number, order in enumerate(orders)}
    result = []
    for order in orders:
        entry = {key: order[key] for key in ORDER_KEYS}
        entry["alerts"] = [{key: alert[key] for key in ("at", "beforeMin", "breaksFocus")} for alert in order["alerts"]]
        entry["parent"] = index.get(order["parentId"])
        result.append(entry)
    return result


def day(ms):
    return dt.datetime.fromtimestamp(ms / 1000).strftime("%Y-%m-%d %H:%M") if ms is not None else ""


def to_json(store):
    return json.dumps({"shale": "day", "version": 1, "orders": orders_of(store)}, ensure_ascii=False, indent=1)


def to_csv(store):
    out = io.StringIO()
    writer = csv.writer(out, lineterminator="\n")
    writer.writerow(["text", "notes", "site", "section", "tags", "magnitude", "due", "deadline", "duration_min", "repeat", "cleared", "sub_of"])
    orders = orders_of(store)
    for order in orders:
        parent = orders[order["parent"]]["text"] if order["parent"] is not None else ""
        due = day(order["dueAt"])[:10] if order["allDay"] else day(order["dueAt"])
        writer.writerow([order["text"], order["notes"] or "", order["site"] or "", order["section"] or "", " ".join(order["tags"]),
                         order["priority"], due, day(order["deadlineAt"])[:10], order["durationMin"] or "", order["rule"] or "",
                         day(order["doneAt"]), parent])
    return out.getvalue()


def to_markdown(store):
    orders = orders_of(store)
    sites = {}
    for order in orders:
        sites.setdefault(order["site"] or "Intake", []).append(order)
    lines = ["# Shale orders", ""]
    for name, group in sites.items():
        lines += ["## " + name, ""]
        for order in group:
            detail = [part for part in (("due " + day(order["dueAt"])) if order["dueAt"] else "", " ".join("@" + tag for tag in order["tags"]),
                                        "M" + str(order["priority"]) if order["priority"] > 1 else "") if part]
            indent = "  " if order["parent"] is not None else ""
            lines.append(indent + "- [" + ("x" if order["doneAt"] else " ") + "] " + order["text"] + (" (" + ", ".join(detail) + ")" if detail else ""))
        lines.append("")
    return "\n".join(lines)


def export(store, fmt, value):
    if fmt not in FORMATS:
        raise ValueError("Choose JSON, CSV or Markdown.")
    path = file_path(value, FORMATS[fmt])
    text = {"json": to_json, "csv": to_csv, "md": to_markdown}[fmt](store)
    write_private(path, text)
    return {"path": str(path), "count": len(store.orders(1))}


def add_all(store, orders):
    """Adds `orders` (the shape orders_of writes) to the store; sub-orders follow their parents. Returns the counts."""
    ids, added, skipped = {}, 0, []
    for number, order in enumerate(orders):
        parent = order.get("parent")
        fields = {key: order[key] for key in ORDER_KEYS if key in order and key not in ("doneAt", "kind")}
        fields["kind"] = order.get("kind", "todo")
        if parent is not None:
            if parent not in ids:
                skipped.append(order.get("text", ""))
                continue
            fields["parentId"] = ids[parent]
        try:
            item = store.add(fields)
        except ValueError as error:
            skipped.append((order.get("text") or "") + ": " + str(error))
            continue
        ids[number] = item["id"]
        added += 1
        if order.get("doneAt") is not None:
            store.db.execute("UPDATE items SET done_at = ? WHERE id = ?", (order["doneAt"], item["id"]))
            store.db.commit()
    return {"added": added, "skipped": skipped}


def from_json(text):
    try:
        data = json.loads(text)
    except ValueError:
        raise ValueError("That file isn't a Shale orders export.") from None
    if not isinstance(data, dict) or data.get("shale") != "day" or data.get("version") != 1 or not isinstance(data.get("orders"), list):
        raise ValueError("That file isn't a Shale orders export.")
    return [order for order in data["orders"] if isinstance(order, dict)]


def todoist_date(text):
    """Epoch ms and whether it has no time, from the dates a Todoist export writes; None for anything else (a repeat
    such as "every day" is kept in the notes instead)."""
    text = text.strip()
    for pattern, order in ((r"(\d{4})-(\d\d)-(\d\d)(?:[ T](\d\d):(\d\d))?", "ymd"), (r"(\d{1,2}) ([A-Za-z]{3})[a-z]* (\d{4})(?: (\d\d?):(\d\d))?", "dmy")):
        match = re.fullmatch(pattern, text)
        if not match:
            continue
        try:
            if order == "ymd":
                year, month, date = int(match[1]), int(match[2]), int(match[3])
            else:
                year, month, date = int(match[3]), MONTHS[match[2].lower()], int(match[1])
            hour, minute = (int(match[4]), int(match[5])) if match[4] else (0, 0)
            stamp = dt.datetime(year, month, date, hour, minute)
        except (ValueError, KeyError):
            return None
        return int(stamp.timestamp() * 1000), match[4] is None
    return None


def from_todoist(text, site):
    """Orders from a Todoist project export: task rows become orders in `site`, section rows name the section of the
    tasks after them, an indented task is a sub-order. Todoist's priority 1 is the most urgent, Shale's magnitude 4."""
    orders, section, last_top = [], None, None
    for row in csv.DictReader(io.StringIO(text)):
        kind = (row.get("TYPE") or "").strip().lower()
        content = (row.get("CONTENT") or "").strip()
        if kind == "section":
            section = content or None
            last_top = None
            continue
        if kind != "task" or not content:
            continue
        try:
            priority = 5 - int(row.get("PRIORITY") or 4)
        except ValueError:
            priority = 1
        notes = (row.get("DESCRIPTION") or "").strip()
        due = todoist_date(row.get("DATE") or "")
        if (row.get("DATE") or "").strip() and due is None:
            notes = (notes + "\n" if notes else "") + "Todoist date: " + row["DATE"].strip()
        deadline = todoist_date(row.get("DEADLINE") or "")
        try:
            indent = int(row.get("INDENT") or 1)
        except ValueError:
            indent = 1
        order = {"kind": "todo", "text": content[:500], "notes": notes or None, "site": site, "section": section if indent == 1 else None,
                 "tags": [], "priority": min(4, max(1, priority)), "dueAt": due[0] if due else None, "allDay": bool(due and due[1]),
                 "deadlineAt": deadline[0] if deadline else None}
        if indent > 1 and last_top is not None:
            order.update(parent=last_top, site=None, section=None)
        else:
            last_top = len(orders)
        orders.append(order)
    return orders


def import_file(store, kind, value):
    if kind not in SOURCES:
        raise ValueError("Choose a Shale export, a Todoist CSV or a plain list.")
    path = file_path(value, SOURCES[kind], must_exist=True)
    try:
        text = path.read_text(encoding="utf-8-sig")
    except (OSError, UnicodeDecodeError):
        raise ValueError("Could not read " + str(path) + " as text.") from None
    if len(text) > 5_000_000:
        raise ValueError("That file is too large to import.")
    if kind == "plain":
        return {"lines": [line.strip() for line in text.splitlines() if line.strip()][:2000]}
    orders = from_json(text) if kind == "json" else from_todoist(text, path.stem[:60] or "Todoist")
    return add_all(store, orders[:5000])


def backup(store, value):
    """A consistent copy of the whole database (orders, routines, shifts), readable by its owner only."""
    path = file_path(value, ".sqlite3")
    descriptor = os.open(path, os.O_CREAT | os.O_WRONLY | os.O_TRUNC, 0o600)
    os.close(descriptor)
    target = sqlite3.connect(path)
    try:
        store.db.backup(target)
    finally:
        target.close()
    return {"path": str(path)}


def restore(store, value):
    """Replaces everything with a copy made by backup(). The data as it was is kept next to the database first
    (day.sqlite3.before-restore), and a file that is not a Shale Day database of the current version is refused."""
    path = file_path(value, ".sqlite3", must_exist=True)
    try:
        source = sqlite3.connect("file:" + str(path) + "?mode=ro", uri=True)
        try:
            version = source.execute("PRAGMA user_version").fetchone()[0]
            tables = {row[0] for row in source.execute("SELECT name FROM sqlite_master WHERE type = 'table'")}
        finally:
            source.close()
    except sqlite3.Error:
        raise ValueError("That file isn't a Shale Day backup.") from None
    if not {"items", "alerts", "sites", "history"} <= tables:
        raise ValueError("That file isn't a Shale Day backup.")
    if version != store_schema():
        raise ValueError("That backup is from another version of Shale (schema " + str(version) + ").")
    main = store.db.execute("PRAGMA database_list").fetchone()[2]
    if main:
        keep = Path(main + ".before-restore")
        descriptor = os.open(keep, os.O_CREAT | os.O_WRONLY | os.O_TRUNC, 0o600)
        os.close(descriptor)
        copy = sqlite3.connect(keep)
        try:
            store.db.backup(copy)
        finally:
            copy.close()
    source = sqlite3.connect("file:" + str(path) + "?mode=ro", uri=True)
    try:
        source.backup(store.db)
    finally:
        source.close()
    return {"path": str(path), "count": len(store.orders(1))}


def store_schema():
    import day
    return day.SCHEMA
