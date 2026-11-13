"""HK Tools: read and write iPhone contacts directly on the device.

Uses the device's own sync service (com.apple.mobilesync, the protocol Finder /
iTunes contact sync and tools like 3uTools use), driven through
pymobiledevice3's lockdown and service connections. Run with the Python that
has pymobiledevice3 installed:

    python hk_contacts.py read  <udid>                 -> JSON on stdout
    python hk_contacts.py write <udid> <changes.json>  -> JSON on stdout

changes.json: {"upsert": [contact, ...], "delete": [record id, ...]}
(deleting a contact id removes the contact; a phone / email id removes just
that entry); a contact is
    {"id": "<device record id, or empty for a new one>",
     "first": "", "last": "", "middle": "", "company": "", "note": "",
     "phones": [{"id": "", "value": "", "label": "mobile"}],
     "emails": [{"id": "", "value": "", "label": "home"}]}

Contacts synced with iCloud are not offered over this service: the device
refuses the session ("RefuseToSync"), which is reported as an error.
"""

import asyncio
import datetime
import inspect
import json
import sys
import uuid

from pymobiledevice3.lockdown import create_using_usbmux

SERVICE = "com.apple.mobilesync"
DATA_CLASS = "com.apple.Contacts"
EMPTY = "___EmptyParameterString___"
ENTITY_KEY = "com.apple.syncservices.RecordEntityName"
E_CONTACT = "com.apple.contacts.Contact"
E_PHONE = "com.apple.contacts.Phone Number"
E_EMAIL = "com.apple.contacts.Email Address"


async def _maybe(value):
    return await value if inspect.isawaitable(value) else value


class Sync:
    def __init__(self, service):
        self.s = service

    async def send(self, msg):
        await _maybe(self.s.send_plist(msg))

    async def recv(self):
        return await _maybe(self.s.recv_plist())

    async def start(self):
        # DeviceLink handshake.
        msg = await self.recv()
        await self.send(["DLMessageVersionExchange", "DLVersionsOk", msg[1]])
        msg = await self.recv()
        if msg[0] != "DLMessageDeviceReady":
            raise RuntimeError(f"Sync service not ready: {msg[0]}")
        now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M:%S %z")
        await self.send(["SDMessageSyncDataClassWithDevice", DATA_CLASS, "---", now, 106, EMPTY])
        msg = await self.recv()
        kind = msg[0]
        if kind == "SDMessageRefuseToSyncDataClassWithComputer":
            raise RuntimeError(
                "The iPhone refused to sync contacts with this computer. Contacts kept in "
                "iCloud are not offered for computer sync: turn off Contacts in "
                "Settings > your name > iCloud, keep them on the iPhone, then try again."
            )
        if kind == "SDMessageCancelSession":
            raise RuntimeError(f"The iPhone cancelled the sync: {msg[2] if len(msg) > 2 else ''}")
        if kind != "SDMessageSyncDataClassWithComputer":
            raise RuntimeError(f"Unexpected answer from the iPhone: {kind}")

    async def read_all(self):
        await self.send(["SDMessageGetAllRecordsFromDevice", DATA_CLASS])
        records = {}
        while True:
            msg = await self.recv()
            kind = msg[0]
            if kind == "SDMessageProcessChanges":
                entities = msg[2] if isinstance(msg[2], dict) else {}
                records.update(entities)
                await self.send(["SDMessageAcknowledgeChangesFromDevice", DATA_CLASS])
                continue
            if kind == "SDMessageDeviceReadyToReceiveChanges":
                await self.send(["DLMessagePing", "Preparing to get changes for device"])
                return records
            if kind == "SDMessageCancelSession":
                raise RuntimeError(f"The iPhone cancelled the sync: {msg[2] if len(msg) > 2 else ''}")
            raise RuntimeError(f"Unexpected message while reading: {kind}")

    async def send_changes(self, entities):
        actions = {
            "SyncDeviceLinkEntityNamesKey": [E_CONTACT, E_PHONE, E_EMAIL],
            # Only these records changed: the iPhone keeps everything else.
            "SyncDeviceLinkAllRecordsOfPulledEntityTypeSentKey": False,
        }
        # Index 3 = "more changes follow".
        await self.send(["SDMessageProcessChanges", DATA_CLASS, entities, False, actions])
        msg = await self.recv()
        if msg[0] == "SDMessageCancelSession":
            raise RuntimeError(f"The iPhone rejected the changes: {msg[2] if len(msg) > 2 else ''}")
        return msg[2] if len(msg) > 2 and isinstance(msg[2], dict) else {}

    async def finish(self):
        await self.send(["SDMessageFinishSessionOnDevice", DATA_CLASS])
        try:
            await self.recv()  # SDMessageDeviceFinishedSession
        except Exception:
            pass
        try:
            await self.send(["DLMessageDisconnect", "All done, thanks for the memories"])
        except Exception:
            pass


def to_contacts(records):
    contacts = {}
    for rid, rec in records.items():
        if isinstance(rec, dict) and rec.get(ENTITY_KEY) == E_CONTACT:
            contacts[rid] = {
                "id": rid,
                "first": rec.get("first name", ""),
                "last": rec.get("last name", ""),
                "middle": rec.get("middle name", ""),
                "company": rec.get("company name", ""),
                "note": rec.get("notes", ""),
                "phones": [],
                "emails": [],
            }
    for rid, rec in records.items():
        if not isinstance(rec, dict):
            continue
        kind = rec.get(ENTITY_KEY)
        if kind not in (E_PHONE, E_EMAIL):
            continue
        owners = rec.get("contact") or []
        for owner in owners if isinstance(owners, list) else [owners]:
            c = contacts.get(owner)
            if c is None:
                continue
            item = {"id": rid, "value": rec.get("value", ""), "label": rec.get("type", "")}
            (c["phones"] if kind == E_PHONE else c["emails"]).append(item)
    return sorted(contacts.values(), key=lambda c: (c["last"] or c["first"] or c["company"]).lower())


def to_entities(upserts):
    entities = {}
    for c in upserts:
        cid = c.get("id") or f"hk-{uuid.uuid4()}"
        rec = {ENTITY_KEY: E_CONTACT}
        for key, field in (("first name", "first"), ("last name", "last"),
                           ("middle name", "middle"), ("company name", "company"),
                           ("notes", "note")):
            if c.get(field):
                rec[key] = c[field]
        entities[cid] = rec
        for kind, items in ((E_PHONE, c.get("phones") or []), (E_EMAIL, c.get("emails") or [])):
            for i in items:
                if not i.get("value"):
                    continue
                entities[i.get("id") or f"hk-{uuid.uuid4()}"] = {
                    ENTITY_KEY: kind,
                    "contact": [cid],
                    "value": i["value"],
                    "type": i.get("label") or ("mobile" if kind == E_PHONE else "home"),
                }
    return entities


async def main():
    if len(sys.argv) < 3 or sys.argv[1] not in ("read", "write"):
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    mode, udid = sys.argv[1], sys.argv[2]
    service = await _open(udid)
    sync = Sync(service)
    try:
        await sync.start()
        records = await sync.read_all()
        if mode == "read":
            print(json.dumps({"contacts": to_contacts(records)}, default=str))
            return
        with open(sys.argv[3], encoding="utf-8") as f:
            changes = json.load(f)
        upserts = changes.get("upsert", [])
        entities = to_entities(upserts)
        # Deleting a record: its id with an empty value.
        for rid in changes.get("delete", []):
            entities[str(rid)] = EMPTY
        # The iPhone drops phone / email records that point at a contact it
        # hasn't created yet, so new contacts go first and their numbers and
        # addresses follow in a second session, once the contacts have ids.
        first = {k: v for k, v in entities.items()
                 if not isinstance(v, dict)
                 or v.get(ENTITY_KEY) == E_CONTACT
                 or not any(str(c).startswith("hk-") for c in v.get("contact", []))}
        pending = {k: v for k, v in entities.items() if k not in first}
        remap = await sync.send_changes(first)
        await sync.finish()
        await _close(service)
        service = None
        if pending:
            new_ids = {k for k in first if k.startswith("hk-")}
            if not (isinstance(remap, dict) and new_ids <= set(remap)):
                remap = await _find_new_ids(udid, records, first, new_ids)
            for rec in pending.values():
                rec["contact"] = [remap.get(c, c) for c in rec.get("contact", [])]
            service = await _open(udid)
            sync = Sync(service)
            await sync.start()
            await sync.read_all()
            await sync.send_changes(pending)
        print(json.dumps({"written": len(upserts),
                          "deleted": len(changes.get("delete", []))}, default=str))
    finally:
        if service is not None:
            await sync.finish()
            await _close(service)


async def _open(udid):
    """A fresh sync-service connection. The iPhone needs a moment after a
    session ends before it accepts the next one, so retry for a while."""
    last = None
    for attempt in range(8):
        try:
            lockdown = await _maybe(create_using_usbmux(serial=udid))
            return await _maybe(lockdown.start_lockdown_service(SERVICE))
        except Exception as e:  # noqa: BLE001
            last = e
            await asyncio.sleep(1.5 + attempt)
    raise RuntimeError(f"Couldn't reconnect to the iPhone's sync service ({type(last).__name__}).")


async def _close(service):
    close = getattr(service, "close", None)
    if close:
        await _maybe(close())


async def _find_new_ids(udid, before, sent, new_ids):
    """Maps our temporary ids to the ids the iPhone gave the new contacts,
    by matching their names, company and note against what is on the device
    now."""
    service = await _open(udid)
    sync = Sync(service)
    try:
        await sync.start()
        after = await sync.read_all()
    finally:
        await sync.finish()
        await _close(service)
    fields = ("first name", "last name", "middle name", "company name", "notes")
    fresh = [k for k, v in after.items()
             if k not in before and isinstance(v, dict) and v.get(ENTITY_KEY) == E_CONTACT]
    remap = {}
    for tmp in sorted(new_ids):
        want = {f: sent[tmp].get(f, "") for f in fields}
        for k in fresh:
            if k in remap.values():
                continue
            if {f: after[k].get(f, "") for f in fields} == want:
                remap[tmp] = k
                break
    return remap


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except Exception as e:  # one readable line for the app
        print(f"ERROR: {e or type(e).__name__}", file=sys.stderr)
        sys.exit(1)
