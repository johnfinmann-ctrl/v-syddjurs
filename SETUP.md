# Venstre Syddjurs — app-opsætning

Bygget på Nordic Media Engine (multi-tenant-klar arkitektur), men denne leverance
kører kun med **Venstre Syddjurs** som organisation. Intet "opret kunde"-flow og
ingen white-label admin-UI i denne version — det kan bygges senere uden at
lave databasen om, se afsnittet "Klar til flere organisationer" nederst.

## 1. Supabase
1. Opret ét Supabase-projekt (EU-region).
2. Kør `supabase-schema.sql`. Den opretter hele hierarkiet og seeder
   organisationen "Venstre Syddjurs" (slug `venstre-syddjurs`) med Venstre-farver
   (dyb navy #254264, blå #1D4ED8) og kategorierne Nyheder, Politik,
   Arrangementer, Video, Information.
3. **Authentication → Providers**: aktiver "Email" (magic link/OTP).
4. **Authentication → URL Configuration**: sæt jeres live-URL som redirect.
5. Kopiér Project URL og anon key ind i `config.js`.

## 2. Ret branding om nødvendigt
Farver/navn/logo ligger i databasen, ikke i koden:
```sql
update organizations set
  logo_url = 'https://.../venstre-logo.png',
  colors = colors || '{"primary":"#1D4ED8"}'::jsonb
where slug = 'venstre-syddjurs';
```

## 3. Roller — hvem gør hvad
| Rolle | Kan |
|---|---|
| Administrator | Alt: tildele roller, redigere/skjule alt indhold, se statistik |
| Redaktør | Publicere direkte, godkende/afvise bidrag fra bidragydere |
| Bidragyder | Indsende opslag → sendes til godkendelse hos redaktør/administrator |
| Moderator | Slette/moderere kommentarer (til fx frivillige der styrer debattonen) |

Flere redaktører kan arbejde samtidig — der er ingen "lås" på opslag, og
feedet opdateres i realtid for alle når nogen udgiver eller retter noget.

Tildel roller: **Adminpanel → Brugere og roller** (kræver administrator-adgang).
Første bruger skal sættes til `administrator` manuelt i Supabase (Table Editor
→ `profiles` → sæt `role` og `org_id` på jeres egen konto), da der ingen
superadmin-onboarding er i denne version.

## 4. Funktioner med i denne udgave
Feed med hero-karrusel og "Det sker"-sektion, eget video-univers med
autoplay-preview, kalenderkort (ikke liste), 3-trins publiceringsflow under
1 minut, søgning, likes + bogmærker (adskilte), kommentarer (til/fra pr.
opslag), realtime, offline-cache, dark/light mode, adminpanel med statistik,
godkendelser og kommentar-moderation.

## 5. Push, ikoner, QR, deploy
- Push kræver VAPID-nøglepar + en Supabase Edge Function til afsendelse
  (`npx web-push generate-vapid-keys`, offentlig nøgle i `config.js`).
- Læg `icon-192.png`, `icon-512.png`, `icon-maskable-512.png` (Venstre-logo,
  PNG) i mappen.
- QR til installation: goqr.me, pegende på jeres live-URL.
- GitHub Pages eller Netlify. Test altid på rigtig mobil/Safari.

## Klar til flere organisationer senere
Databasen er allerede bygget som ægte multi-tenant (RLS pr. `org_id`, 5 roller,
afdelinger/teams-tabeller). Skal I fx senere køre en tilsvarende app for en
anden lokalforening, tilføjes den med en ny `organizations`-række (se
`nordic-media-v2`-leverancen for den fulde forklaring) — kildekoden i
`index.html` skal ikke ændres, kun konfiguration og data.
