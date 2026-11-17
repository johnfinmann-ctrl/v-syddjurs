#!/usr/bin/env python3
"""Henter RSS-feeds fra feeds.json og skriver nyheder.json (kun medie, overskrift, dato, link).
Kun standardbibliotek. Gemmer aldrig brødtekst eller billeder."""
import json, sys, re, html, urllib.request, urllib.parse
from datetime import datetime, timezone, timedelta
from email.utils import parsedate_to_datetime
import xml.etree.ElementTree as ET

UA = "VenstreSyddjursNyhedsbjaelke/1.0 (+https://github.com/johnfinmann-ctrl/v-syddjurs)"

def hent(url, tekst=None):
    if tekst is not None:
        return tekst
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "application/rss+xml, application/xml, text/xml"})
    with urllib.request.urlopen(req, timeout=20) as r:
        return r.read()

def rens(s):
    s = html.unescape(re.sub(r"<[^>]+>", " ", s or ""))
    return re.sub(r"\s+", " ", s).strip()

def parse_dato(s):
    if not s: return None
    try:
        d = parsedate_to_datetime(s)
    except Exception:
        try: d = datetime.fromisoformat(s.replace("Z", "+00:00"))
        except Exception: return None
    if d.tzinfo is None: d = d.replace(tzinfo=timezone.utc)
    return d.astimezone(timezone.utc)

def lokal(tag): return tag.rsplit("}", 1)[-1]

def parse_feed(data):
    root = ET.fromstring(data)
    out = []
    for el in root.iter():
        t = lokal(el.tag)
        if t not in ("item", "entry"): continue
        f = {"title": "", "link": "", "date": "", "desc": ""}
        for c in el:
            n = lokal(c.tag)
            if n == "title": f["title"] = rens(c.text)
            elif n == "link": f["link"] = (c.get("href") or c.text or "").strip() or f["link"]
            elif n in ("pubDate", "published", "updated", "date") and not f["date"]: f["date"] = (c.text or "").strip()
            elif n in ("description", "summary") and not f["desc"]: f["desc"] = rens(c.text)[:300]
        d = parse_dato(f["date"])
        if f["title"] and f["link"].startswith(("http://", "https://")) and d:
            out.append({"title": f["title"], "link": f["link"], "dt": d, "desc": f["desc"]})
    return out

def ord_match(tekst, ordliste):
    t = tekst.lower()
    return any(re.search(r"(?<![\wæøå])" + re.escape(o) + r"(?![\wæøå])", t) for o in ordliste)

def score(item, kilde_lokal, so):
    titel, alt = item["title"], item["title"] + " " + item["desc"]
    s = 0
    if ord_match(titel, so["parti"]) or ord_match(titel, so["personer"]): s = 3          # væsentligt emne
    elif ord_match(alt, so["parti"]) or ord_match(alt, so["personer"]): s = 1             # kun tilfældig omtale -> under tærsklen
    if s < 3 and ord_match(alt, so["lokalt"]) and ord_match(titel, so["kommunalpolitik"] + so["lokalt"]):
        s = max(s, 2)                                                                       # kommunalpolitik i Syddjurs/Norddjurs
    if s < 3 and kilde_lokal and ord_match(titel, so["kommunalpolitik"]) and not ord_match(alt, ["aarhus", "århus", "randers"]):
        s = max(s, 2)
    return s

def norm(t): return re.sub(r"[^a-zæøå0-9]+", " ", t.lower()).strip()

def vaelg(kandidater, cfg, nu):
    maxd = timedelta(days=cfg["max_alder_dage"])
    set_link, set_tit, ok = set(), set(), []
    for k in sorted(kandidater, key=lambda x: x["dt"], reverse=True):
        if nu - k["dt"] > maxd or k["dt"] > nu + timedelta(hours=1): continue
        key = re.sub(r"[?#].*$", "", k["link"])
        if key in set_link or norm(k["title"]) in set_tit: continue
        set_link.add(key); set_tit.add(norm(k["title"])); ok.append(k)
    ok.sort(key=lambda x: (x["score"], x["dt"]), reverse=True)
    valgt, lok = [], 0
    for k in ok:
        if k["score"] < 2: continue
        if k["lokal"] and lok >= cfg["max_lokale"]: continue
        valgt.append(k); lok += 1 if k["lokal"] else 0
        if len(valgt) >= cfg["antal"]: break
    valgt.sort(key=lambda x: x["dt"], reverse=True)
    return valgt

def main(cfg_sti="feeds.json", ud_sti="nyheder.json", fixtures=None):
    cfg = json.load(open(cfg_sti, encoding="utf-8"))
    nu = datetime.now(timezone.utc); kand, status = [], []
    for f in cfg["feeds"]:
        if not f.get("aktiv"): status.append((f["id"], "slået fra")); continue
        try:
            data = hent(f["url"], (fixtures or {}).get(f["id"]))
            items = parse_feed(data)
            for it in items:
                it.update(kilde=f["navn"], lokal=f["lokal"], score=score(it, f["lokal"], cfg["soegeord"]))
            kand += items; status.append((f["id"], f"OK, {len(items)} artikler"))
        except Exception as e:
            status.append((f["id"], f"FEJL: {type(e).__name__}: {e}"))
    for s in status: print(f"[feed] {s[0]}: {s[1]}")
    ok_kilder = [s for s in status if s[1].startswith("OK")]
    if not ok_kilder:
        print("Ingen feed kunne hentes - nyheder.json ændres ikke."); return 0
    valgt = vaelg(kand, cfg, nu)
    ud = {"opdateret": nu.isoformat(timespec="seconds"),
          "items": [{"kilde": v["kilde"], "titel": v["title"], "link": v["link"], "dato": v["dt"].isoformat(timespec="seconds"), "lokal": v["lokal"]} for v in valgt]}
    old = None
    try: old = json.load(open(ud_sti, encoding="utf-8"))
    except Exception: pass
    if old and old.get("items") == ud["items"]:
        print("Uændret."); return 0
    json.dump(ud, open(ud_sti, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print(f"Skrev {len(valgt)} nyheder.")
    return 0

if __name__ == "__main__":
    sys.exit(main())
