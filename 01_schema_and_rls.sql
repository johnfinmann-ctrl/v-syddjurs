-- ============================================================
-- V-SYDDJURS — SKEMA OG ROW LEVEL SECURITY
-- Kør denne fil i Supabase SQL Editor (Database → SQL Editor → New query)
-- ============================================================

-- ------------------------------------------------------------
-- 1) app_content — fælles indhold for hele appen
--    (Nyheder, Kalender, Video, Byrådet, Bestyrelse, Mærkesager,
--     VU, Kontakt, MobilePay, kategorier)
--    Findes formentlig allerede — "if not exists" gør scriptet sikkert
--    at køre igen uden at overskrive eksisterende data.
-- ------------------------------------------------------------
create table if not exists app_content (
    key         text primary key,
    value       jsonb not null,
    updated_at  timestamptz not null default now()
);

alter table app_content enable row level security;

-- ------------------------------------------------------------
-- 2) profiles — kobler en Supabase Auth-bruger til en rolle.
--    En bruger uden række her (eller med en anden rolle) kan
--    logge ind, men får IKKE adgang til admin-panelet i appen,
--    og kan (takket være RLS'en nedenfor) heller ikke skrive
--    til app_content eller uploade filer.
-- ------------------------------------------------------------
create table if not exists profiles (
    id          uuid primary key references auth.users(id) on delete cascade,
    email       text,
    role        text not null check (role in ('admin', 'redaktor')),
    created_at  timestamptz not null default now()
);

alter table profiles enable row level security;

-- En bruger må læse sin egen profil (bruges til at slå rollen op ved login)
drop policy if exists "Bruger kan læse egen profil" on profiles;
create policy "Bruger kan læse egen profil"
    on profiles for select
    using (auth.uid() = id);

-- ------------------------------------------------------------
-- 3) RLS-politikker for app_content
-- ------------------------------------------------------------

-- Alle (også ikke-loggede besøgende) må læse offentliggjort indhold
drop policy if exists "Offentlig læseadgang" on app_content;
create policy "Offentlig læseadgang"
    on app_content for select
    using (true);

-- Kun admin/redaktør må oprette nye rækker
drop policy if exists "Admin og redaktør må oprette" on app_content;
create policy "Admin og redaktør må oprette"
    on app_content for insert
    with check (
        exists (
            select 1 from profiles
            where id = auth.uid() and role in ('admin', 'redaktor')
        )
    );

-- Kun admin/redaktør må opdatere eksisterende rækker
drop policy if exists "Admin og redaktør må opdatere" on app_content;
create policy "Admin og redaktør må opdatere"
    on app_content for update
    using (
        exists (
            select 1 from profiles
            where id = auth.uid() and role in ('admin', 'redaktor')
        )
    );

-- Kun admin/redaktør må slette rækker
drop policy if exists "Admin og redaktør må slette" on app_content;
create policy "Admin og redaktør må slette"
    on app_content for delete
    using (
        exists (
            select 1 from profiles
            where id = auth.uid() and role in ('admin', 'redaktor')
        )
    );

-- ------------------------------------------------------------
-- 4) Aktivér Realtime for app_content
--    (Kan også gøres i UI: Database → Replication → slå
--    "app_content" til i publikationen "supabase_realtime")
-- ------------------------------------------------------------
alter publication supabase_realtime add table app_content;

-- ============================================================
-- OPRET JERES FØRSTE ADMINISTRATOR
-- ============================================================
-- 1) Gå til Authentication → Users → "Add user" og opret brugeren
--    med e-mail + adgangskode (du vælger begge dele).
-- 2) Kør derefter denne linje herunder — udskift e-mailen med den,
--    du netop oprettede, og sæt rollen til 'admin' eller 'redaktor':
--
--    insert into profiles (id, email, role)
--    select id, email, 'admin'
--    from auth.users
--    where email = 'din-email@venstresyddjurs.dk';
--
-- Gentag for hver administrator/redaktør, I opretter.
