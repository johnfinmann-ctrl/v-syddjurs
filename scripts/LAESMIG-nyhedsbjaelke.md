# Nyhedsbjælken – vejledning (RC48.41)

## Sådan virker den
GitHub Actions (`.github/workflows/nyheder.yml`) kører cirka hver 2. time → `scripts/hent_nyheder.py` henter RSS-feeds fra `feeds.json`
→ relevansvurdering → verificering af links → `nyheder.json` → appen læser filen og viser bjælken over bundmenuen.
Kun medie, overskrift, dato og link gemmes. Ingen brødtekst eller billeder.

## Aktivér og test første gang
1. Upload hele ZIP-indholdet til repoet, **inklusive de skjulte mapper `.github` og `scripts`** (Mac: Cmd+Shift+. viser skjulte filer).
2. GitHub → Settings → Actions → General → *Workflow permissions* → **Read and write permissions** → Save.
3. GitHub → Actions → **Opdater nyhedsbjælke** → *Run workflow* → tilstand **test** → Run.
   Åbn kørslen → *Summary*: tabellen viser pr. kilde om feedet virker, antal artikler, nyeste artikel og link-tjek.
4. Send tabellen (eller en skærmkopi) til Claude. Kilder, der fejler, deaktiveres (`"aktiv": false` i `feeds.json`).
5. Kør workflowen igen med tilstand **opdater**. Den gemmer `nyheder.json`. Efter få minutter viser appen bjælken
   (genindlæs siden; ved ny version hjælper `app-version` selv).
6. Herefter kører den automatisk hver 2. time. Kontrollér i Actions, at der kommer grønne kørsler, og i appen at "Opd. tt.mm" ændrer sig.

Hvis `nyheder.json` er opdateret i repoet, men siden ikke ændrer sig: tjek at GitHub Pages har bygget (Actions → *pages build and deployment*).

## Hvad bjælken viser
- Altid synlig. Uden nyheder vises en rolig besked: "Venter på første automatiske opdatering", "Ingen nye relevante nyheder (seneste 72 t)" eller "Nyheder kan ikke hentes lige nu".
- Op til 10 nyheder fra de seneste 72 timer, højst 5 lokale. "Opd. tt.mm" er tidspunktet for seneste vellykkede kørsel.

## Verificering af links (vigtigt at skelne)
Hver nyhed i `nyheder.json` har feltet `verificering`:
- `http` – vores eget tjek fik svar 200–399 fra artiklens adresse (teknisk verificeret på tjektidspunktet).
- `feed` – linket er kun **fundet i mediets egen feed**. Siden svarede 401/403/429 (typisk betalingsmur eller blokering af automatiske opslag), så linket er **ikke** teknisk verificeret.
Afvist (vises ikke): 404/410, serverfejl og netværksfejl.
Vil du kun vise teknisk verificerede links: sæt `"kun_http_verificerede": true` i `feeds.json`.

## Kilder – status
| Kilde | Status |
|---|---|
| Berlingske (`/content/3/rss`) | Feed-adresse ifølge Feeder; **ikke testet af Claude** – kør testen |
| DR Nyheder | Adresse ikke bekræftet (Feeder: ingen egen RSS); **kør testen** |
| Politiken | Adresse ikke bekræftet; **kør testen** |
| TV 2 Østjylland (`/rss`) | Ifølge Feeder muligt; **ikke testet** |
| Din Avis Syddjurs / Norddjurs | Ønsket kilde. Hentes **ikke**: ingen RSS; vilkårene forbyder brug i oversigter til andre uden tilladelse (https://dinavis.dk/ophavsret/). Kræver skriftlig aftale. |
| TV 2 Nyheder, Jyllands-Posten | Ingen egen feed bekræftet – skrabning bruges ikke |
| Ritzau | Kræver kommerciel licens |
Claude kunne ikke nå mediernes feeds fra sin testmiljø, så den første rigtige test sker i GitHub Actions (trin 3).

## Relevansvurdering (`feeds.json` → `soegeord`)
- Venstre/Venstre-politiker i **overskriften** = væsentlig (3 point). Kun omtale i den korte tekst = tilfældig (1 point) og vises ikke.
- Kommunalpolitik med Syddjurs/Norddjurs/Djursland (byråd, borgmester, budget m.m.) = 2 point. Tærskel: mindst 2 point.
- Lokale kilder fylder højst 5 af 10 pladser. Dubletter fjernes (samme link eller overskrift).
- Søgeordene kan redigeres i `feeds.json` (fx tilføje navne på Venstre-politikere i Norddjurs).

## Begrænsninger
- Planlagte kørsler kan blive forsinket af GitHub, og GitHub kan sætte planlagte workflows på pause efter 60 dages inaktivitet i repoet.
- Kilder, der fejler, springes over; de øvrige fortsætter. Fejlen står i Actions-loggen og i `nyheder.json` → `kilder`.
- Tjek mediernes vilkår for visning af overskrifter og links, før en kilde slås til. Dette er ikke juridisk rådgivning.

## Udvalgte artikler i bjælken (RC48.45)
Bjælken kombinerer to ting: (1) automatisk hentede medienyheder (`nyheder.json`, 72-timersreglen) og (2) manuelt udvalgte artikler, som vises først.
Udvalgte artikler kan komme fra to steder – **ingen kodeændringer er nødvendige**:
1. **Appens egne nyheder:** tilføj `bjaelke: true` på en nyhed, der har `externalLink`. Valgfrit: `bjaelkeKilde`, `bjaelkeDato`, `bjaelkeUdloeb` (se Din Avis-kommentaren i `index.html`).
2. **Filen `udvalgte.json`** (redigeres direkte på GitHub, intet andet skal røres): tilføj en række under `artikler`:
   `{ "kilde": "Din Avis Syddjurs", "titel": "...", "link": "https://...", "dato": "2026-11-17", "udloeb": "2026-12-07" }`
   `udloeb` er sidste visningsdag. Uden `udloeb` vises artiklen i 30 dage fra `dato`.
- Samme artikel vises kun én gang (sammenlignet på link uden parametre og på overskrift), også hvis den senere findes automatisk. Den manuelle version vinder.
- Manuelle artikler skjules aldrig af automatikkens status. Til højre i bjælken står enten »Opd. tt.mm« (seneste vellykkede automatiske kørsel), »Auto venter« (kørt endnu ikke) eller »Auto utilgængelig« (nyheder.json kunne ikke hentes).
