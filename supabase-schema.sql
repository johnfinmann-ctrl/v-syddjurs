-- ============================================================
-- Nordic Media Engine — MULTI-TENANT schema (v2)
-- Ét fælles Supabase-projekt, mange organisationer, isoleret via RLS.
--
-- Hierarki (forberedt 5-10 år frem):
--   Superadministrator (Nordic Operations, org_id = NULL, ser alt)
--   └─ Organisation (kunde/tenant, org_id = deres egen række)
--       └─ Afdeling (department)
--           └─ Team
--               └─ Bruger (profile, med rolle)
--
-- I DENNE VERSION er der kun sat ÉN organisation op (seedet nederst).
-- Der er IKKE bygget en "opret kunde"-UI eller white-label admin —
-- kun databasen og RLS'en er klar til det. Se SETUP.md.
-- ============================================================

-- 1) ORGANISATIONER (tenants) --------------------------------
create table if not exists organizations (
  id uuid primary key default gen_random_uuid(),
  slug text unique not null,                 -- bruges i URL: ?org=slug (klar til sub-path/domæne senere)
  name text not null,
  tagline text,
  logo_url text,
  colors jsonb not null default '{
    "primary":"#2B4EFF","primaryDeep":"#0F1B3D","secondary":"#FFFFFF",
    "accent":"#17B26A","accent2":"#8B5CF6","accent3":"#F5487F","accent4":"#F5A524",
    "mist":"#F3F5FA"
  }'::jsonb,
  modules jsonb not null default '{"home":true,"nyt":true,"kalender":true,"video":true,"mere":true}'::jsonb,
  custom_domain text unique,                 -- NULL i dag; forberedt til rigtige domæner senere
  created_at timestamptz not null default now()
);

-- 2) AFDELINGER OG TEAMS (forberedt, ikke brugt i UI endnu) --
create table if not exists departments (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references organizations(id) on delete cascade,
  name text not null,
  created_at timestamptz not null default now()
);

create table if not exists teams (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references organizations(id) on delete cascade,
  department_id uuid references departments(id) on delete set null,
  name text not null,
  created_at timestamptz not null default now()
);

-- 3) ROLLER OG PROFILER ----------------------------------------
-- superadministrator: Nordic Operations-niveau, org_id er NULL (ser/administrerer alle organisationer)
-- administrator:       ejer af én organisation
-- redaktoer:            publicerer, godkender bidrag
-- bidragyder:           indsender opslag til godkendelse
-- moderator:             modererer kommentarer/indhold, publicerer ikke selv
create type user_role as enum ('superadministrator', 'administrator', 'redaktoer', 'bidragyder', 'moderator');

create table if not exists profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  org_id uuid references organizations(id) on delete cascade, -- NULL kun for superadministrator
  department_id uuid references departments(id) on delete set null,
  team_id uuid references teams(id) on delete set null,
  full_name text,
  role user_role not null default 'bidragyder',
  created_at timestamptz not null default now()
);

create or replace function handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, full_name)
  values (new.id, new.raw_user_meta_data->>'full_name');
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure handle_new_user();

-- ---------- Hjælpefunktioner til RLS ----------
create or replace function current_org_id()
returns uuid as $$ select org_id from profiles where id = auth.uid() $$
language sql stable security definer;

create or replace function current_role()
returns user_role as $$ select role from profiles where id = auth.uid() $$
language sql stable security definer;

create or replace function is_superadmin()
returns boolean as $$ select current_role() = 'superadministrator' $$
language sql stable security definer;

-- 4) KATEGORIER (pr. organisation) -----------------------------
create table if not exists categories (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references organizations(id) on delete cascade,
  slug text not null,
  label text not null,
  color_key text not null default 'accent',
  unique (org_id, slug)
);

-- 5) OPSLAG -------------------------------------------------------
create type post_status as enum ('kladde', 'afventer', 'planlagt', 'udgivet', 'skjult');

create table if not exists posts (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references organizations(id) on delete cascade,
  author_id uuid references profiles(id) on delete set null,
  category_id uuid references categories(id),
  title text not null,
  excerpt text,
  body text,
  media_url text,
  media_type text check (media_type in ('billede', 'video')),
  event_date date,
  event_time text,
  event_location text,
  status post_status not null default 'kladde',
  comments_enabled boolean not null default true,
  scheduled_at timestamptz,
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists posts_org_status_idx on posts (org_id, status, published_at desc);
create index if not exists posts_event_date_idx on posts (org_id, event_date);

-- 6) KOMMENTARER, LIKES, BOGMÆRKER (org_id udfyldes automatisk via trigger) ---
create table if not exists comments (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  post_id uuid references posts(id) on delete cascade,
  author_id uuid references profiles(id) on delete set null,
  body text not null,
  created_at timestamptz not null default now()
);

create table if not exists likes (
  org_id uuid not null,
  user_id uuid references profiles(id) on delete cascade,
  post_id uuid references posts(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, post_id)
);

create table if not exists favorites ( -- "Bogmærker" i UI
  org_id uuid not null,
  user_id uuid references profiles(id) on delete cascade,
  post_id uuid references posts(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, post_id)
);

-- Triggerfunktion: udfyld org_id automatisk fra det tilknyttede opslag,
-- så klienten aldrig selv kan sætte/forfalske org_id.
create or replace function set_org_id_from_post()
returns trigger as $$
begin
  select org_id into new.org_id from posts where id = new.post_id;
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists trg_comments_org on comments;
create trigger trg_comments_org before insert on comments for each row execute procedure set_org_id_from_post();
drop trigger if exists trg_likes_org on likes;
create trigger trg_likes_org before insert on likes for each row execute procedure set_org_id_from_post();
drop trigger if exists trg_favorites_org on favorites;
create trigger trg_favorites_org before insert on favorites for each row execute procedure set_org_id_from_post();

-- 7) PUSH-ABONNEMENTER -----------------------------------------
create table if not exists push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null,
  user_id uuid references profiles(id) on delete cascade,
  endpoint text not null,
  p256dh text not null,
  auth_key text not null,
  created_at timestamptz not null default now(),
  unique (endpoint)
);
create or replace function set_org_id_from_profile()
returns trigger as $$
begin
  select org_id into new.org_id from profiles where id = new.user_id;
  return new;
end;
$$ language plpgsql security definer;
drop trigger if exists trg_push_org on push_subscriptions;
create trigger trg_push_org before insert on push_subscriptions for each row execute procedure set_org_id_from_profile();

-- 8) STORAGE (medier deles i ét bucket, sti-præfikset med org_id) ----
insert into storage.buckets (id, name, public)
values ('media', 'media', true)
on conflict (id) do nothing;

-- ============================================================
-- REALTIME
-- ============================================================
alter publication supabase_realtime add table posts;

-- ============================================================
-- ROW LEVEL SECURITY
-- ============================================================
alter table organizations enable row level security;
alter table departments enable row level security;
alter table teams enable row level security;
alter table profiles enable row level security;
alter table categories enable row level security;
alter table posts enable row level security;
alter table comments enable row level security;
alter table likes enable row level security;
alter table favorites enable row level security;
alter table push_subscriptions enable row level security;

-- Organisationer og kategorier er "offentlig branding/struktur" —
-- skal kunne læses af ikke-loggede besøgende, så feedet kan vise sig
-- korrekt før login. Skrivning er lukket ned (kun superadmin/backend).
create policy "organisationer er offentligt læsbare" on organizations for select using (true);
create policy "kun superadmin kan oprette organisationer" on organizations for insert with check (is_superadmin());
create policy "administrator/superadmin kan redigere egen organisation" on organizations for update using (
  is_superadmin() or (current_org_id() = id and current_role() = 'administrator')
);

create policy "kategorier er offentligt læsbare" on categories for select using (true);
create policy "administrator/superadmin kan redigere kategorier" on categories for all using (
  is_superadmin() or (current_org_id() = org_id and current_role() in ('administrator','redaktoer'))
);

-- Afdelinger/teams: kun synlige internt i egen organisation
create policy "org-medlemmer ser egne afdelinger" on departments for select using (is_superadmin() or current_org_id() = org_id);
create policy "administrator styrer afdelinger" on departments for all using (is_superadmin() or (current_org_id() = org_id and current_role() = 'administrator'));
create policy "org-medlemmer ser egne teams" on teams for select using (is_superadmin() or current_org_id() = org_id);
create policy "administrator styrer teams" on teams for all using (is_superadmin() or (current_org_id() = org_id and current_role() = 'administrator'));

-- Profiler: synlige for kollegaer i samme organisation
create policy "profiler er læsbare inden for egen organisation" on profiles for select using (
  is_superadmin() or auth.uid() = id or current_org_id() = org_id
);
create policy "brugere kan opdatere egen profil" on profiles for update using (auth.uid() = id);
create policy "administrator/superadmin kan opdatere profiler i egen org" on profiles for update using (
  is_superadmin() or (current_role() = 'administrator' and current_org_id() = org_id)
);

-- Opslag: udgivet indhold er offentligt (som en almindelig medieplatform).
-- Kladde/afventer er kun synligt for forfatter + redaktion i samme org.
create policy "udgivne opslag er offentlige" on posts for select using (status = 'udgivet' and published_at <= now());
create policy "forfattere ser egne opslag" on posts for select using (auth.uid() = author_id);
create policy "redaktion ser alt i egen organisation" on posts for select using (
  is_superadmin() or (current_org_id() = org_id and current_role() in ('redaktoer','administrator','moderator'))
);
create policy "godkendte brugere kan oprette opslag i egen org" on posts for insert with check (
  auth.uid() = author_id and (is_superadmin() or current_org_id() = org_id)
);
create policy "forfattere kan redigere egne kladder" on posts for update using (auth.uid() = author_id and status in ('kladde','afventer'));
create policy "redaktion kan redigere alt i egen org" on posts for update using (
  is_superadmin() or (current_org_id() = org_id and current_role() in ('redaktoer','administrator'))
);
create policy "redaktion kan slette i egen org" on posts for delete using (
  is_superadmin() or (current_org_id() = org_id and current_role() in ('redaktoer','administrator'))
);

-- Kommentarer: offentligt læsbare, kun godkendte brugere kan skrive,
-- moderator har ret til at fjerne i egen organisation.
create policy "kommentarer er offentligt læsbare" on comments for select using (true);
create policy "godkendte brugere kan kommentere" on comments for insert with check (auth.uid() = author_id);
create policy "ejer eller moderation kan slette kommentar" on comments for delete using (
  auth.uid() = author_id or is_superadmin() or
  (current_org_id() = org_id and current_role() in ('moderator','redaktoer','administrator'))
);

-- Likes og bogmærker: kun egen bruger
create policy "brugere administrerer egne likes" on likes for all using (auth.uid() = user_id);
create policy "brugere administrerer egne bogmærker" on favorites for all using (auth.uid() = user_id);

-- Push: kun egen bruger
create policy "brugere administrerer eget push-abonnement" on push_subscriptions for all using (auth.uid() = user_id);

-- ============================================================
-- STATISTIK-VIEW (pr. organisation)
-- ============================================================
create or replace view post_stats as
select
  p.org_id,
  c.label as kategori,
  count(*) filter (where p.status = 'udgivet') as udgivet,
  count(*) filter (where p.status = 'afventer') as afventer,
  count(*) filter (where p.status = 'planlagt') as planlagt
from posts p
left join categories c on c.id = p.category_id
group by p.org_id, c.label;

-- ============================================================
-- SEED — Venstre Syddjurs (denne leverance bygger kun på denne ene
-- organisation; arkitekturen er klar til flere senere, se SETUP.md)
-- ============================================================
insert into organizations (slug, name, tagline, colors)
values (
  'venstre-syddjurs', 'Venstre Syddjurs', 'Din fremtid. Dine valg.',
  '{
    "primary":"#1D4ED8","primaryDeep":"#254264","secondary":"#FFFFFF",
    "accent":"#17B26A","accent2":"#8B5CF6","accent3":"#F5487F","accent4":"#F5A524",
    "mist":"#F3F5FA"
  }'::jsonb
)
on conflict (slug) do nothing;

insert into categories (org_id, slug, label, color_key)
select o.id, v.slug, v.label, v.color_key
from organizations o,
  (values
    ('nyheder','Nyheder','accent'),
    ('politik','Politik','accent2'),
    ('arrangementer','Arrangementer','accent3'),
    ('video','Video','accent4'),
    ('information','Information','accent')
  ) as v(slug,label,color_key)
where o.slug = 'venstre-syddjurs'
on conflict (org_id, slug) do nothing;
