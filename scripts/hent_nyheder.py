#!/usr/bin/env python3
"""Henter RSS-feeds fra feeds.json og skriver nyheder.json (kun medie, overskrift, dato, link).
Kun standardbibliotek. Gemmer aldrig brødtekst eller billeder."""
import json, sys, re, html, urllib.request, urllib.error, urllib.parse
from datetime import datetime, timezone, timedelta
from email.utils import parsedate_to_datetime
import xml.etree.ElementTree as ET

UA = "VenstreSyddjursNyhedsbjaelke/1.0 (+https://github.com/johnfinmann-ctrl/v-syddjurs)"

INFO = {}

def hent(url, tekst=None):
    if tekst is not None:
        INFO[url] = {"http": "test", "type": "fixture"}
        return tekst
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "application/rss+xml, application/xml, text/xml"})
    with urllib.request.urlopen(req, timeout=20) as r:
        INFO[url] = {"http": r.status, "type": r.headers.get("Content-Type", "")}
        return r.read()

def tjek_link(url):
    """Verificerer at linket virker. Afvises: 404/410, 5xx, netværksfejl. 401/403/429 (betalingsmur/bot-blokering) accepteres,
    fordi linket kommer fra mediets egen feed. Returnerer (ok, status)."""
    for metode in ("HEAD", "GET"):
        try:
            req = urllib.request.Request(url, method=metode, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=12) as r:
                return (200 <= r.status < 400), r.status
        except urllib.error.HTTPError as e:
            if e.code in (401, 403, 429): return True, e.code
            if metode == "HEAD" and e.code in (405, 501): continue
            return False, e.code
        except Exception as e:
            if metode == "HEAD": continue
            return False, type(e).__name__
    return False, "ukendt"

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

def vaelg(kandidater, cfg, nu, tjek=None):
    maxd = timedelta(hours=cfg["max_alder_timer"])
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
        if tjek:
            ok_l, st = tjek(k["link"])
            if not ok_l:
                print(f"[link] afvist ({st}): {k['link']}"); continue
            # "http" = linket svarede 2xx/3xx ved vores eget tjek. "feed" = kun fundet i mediets feed; selve siden kunne ikke
            # tjekkes teknisk (401/403/429 = betalingsmur eller bot-blokering). Det er IKKE en fuld verificering.
            k["ver"] = "http" if isinstance(st, int) and 200 <= st < 400 else "feed"
            if cfg.get("kun_http_verificerede") and k["ver"] != "http": continue
        else:
            k["ver"] = "feed"
        valgt.append(k); lok += 1 if k["lokal"] else 0
        if len(valgt) >= cfg["antal"]: break
    valgt.sort(key=lambda x: x["dt"], reverse=True)
    return valgt

def rapport(cfg, kilder, kand, tjek):
    """Testtilstand: skriver en statustabel (også til GitHub Actions-opsummeringen). Skriver IKKE nyheder.json."""
    nu = datetime.now(timezone.utc)
    ld = ["| Kilde | Feed | Artikler | Nyeste | Link-tjek (3 stk.) |", "|---|---|---|---|---|"]
    for k in kilder:
        prøver = [c for c in kand if c["kilde"] == k["navn"]][:3]
        res = []
        for c in prøver:
            ok_l, st = tjek(c["link"]); res.append(("http-OK " if ok_l and isinstance(st, int) and st < 400 else ("kun feed " if ok_l else "AFVIST ")) + str(st))
        feed = "virker" if k["ok"] else "FEJL: " + k.get("fejl", "")
        ld.append(f"| {k['navn']} | {feed} | {k['antal']} | {k.get('nyeste') or '-'} | {', '.join(res) or '-'} |")
    txt = "\n".join(["## Test af nyhedskilder (" + nu.strftime("%d-%m-%Y %H:%M") + " UTC)"] + ld)
    print(txt)
    import os
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        open(os.environ["GITHUB_STEP_SUMMARY"], "a", encoding="utf-8").write(txt + "\n")
    return 0

def main(cfg_sti="feeds.json", ud_sti="nyheder.json", fixtures=None, tjek=tjek_link, test=False):
    cfg = json.load(open(cfg_sti, encoding="utf-8"))
    nu = datetime.now(timezone.utc); kand, kilder = [], []
    try: gammel = json.load(open(ud_sti, encoding="utf-8"))
    except Exception: gammel = {}
    sidst = {k.get("id"): k.get("sidst_ok") for k in gammel.get("kilder", []) if isinstance(k, dict)}
    for f in cfg["feeds"]:
        if not f.get("aktiv"):
            print(f"[feed] {f['id']}: slået fra"); continue
        post = {"id": f["id"], "navn": f["navn"], "ok": False, "antal": 0, "sidst_ok": sidst.get(f["id"])}
        try:
            items = parse_feed(hent(f["url"], (fixtures or {}).get(f["id"])))
            for it in items:
                it.update(kilde=f["navn"], lokal=f["lokal"], score=score(it, f["lokal"], cfg["soegeord"]))
            kand += items
            post.update(ok=True, antal=len(items), sidst_ok=nu.isoformat(timespec="seconds"))
            nyeste = max((i["dt"] for i in items), default=None)
            post["nyeste"] = nyeste.isoformat(timespec="seconds") if nyeste else None
            print(f"[feed] {f['id']}: OK, {len(items)} artikler, HTTP {INFO.get(f['url'], {}).get('http')}, nyeste {post['nyeste']}")
        except Exception as e:
            post["fejl"] = f"{type(e).__name__}: {e}"[:160]
            print(f"[feed] {f['id']}: FEJL {post['fejl']}")
        kilder.append(post)
    if test:
        return rapport(cfg, kilder, kand, tjek)
    if not any(k["ok"] for k in kilder):
        print("Ingen feed kunne hentes - nyheder.json ændres ikke."); return 0
    valgt = vaelg(kand, cfg, nu, tjek)
    ud = {"opdateret": nu.isoformat(timespec="seconds"), "kilder": kilder,
          "items": [{"kilde": v["kilde"], "titel": v["title"], "link": v["link"], "dato": v["dt"].isoformat(timespec="seconds"), "lokal": v["lokal"], "verificering": v.get("ver", "feed")} for v in valgt]}
    json.dump(ud, open(ud_sti, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print(f"Skrev {len(valgt)} verificerede nyheder (seneste {cfg['max_alder_timer']} timer).")
    return 0

if __name__ == "__main__":
    sys.exit(main(test="--test" in sys.argv))
