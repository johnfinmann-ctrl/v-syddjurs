-- ============================================================
-- V-SYDDJURS — BRUGERSTYRING (roller) OG SPORBARHED (audit log)
-- Kør denne fil EFTER 01_schema_and_rls.sql og 02_storage.sql
-- ============================================================

-- ------------------------------------------------------------
-- 1) Hjælpefunktioner til at tjekke rolle UDEN risiko for
--    uendelig rekursion i RLS-politikker (standard Supabase-mønster).
--    "security definer" gør at funktionen kører med forhøjet adgang
--    internt, så den ikke selv rammer RLS'en på profiles.
-- ------------------------------------------------------------
create or replace function is_admin() returns boolean as $$
  select exists (
      select 1 from profiles where id = auth.uid() and role = 'admin'
  );
$$ language sql security definer stable;

create or replace function is_editor() returns boolean as $$
  select exists (
      select 1 from profiles where id = auth.uid() and role in ('admin', 'redaktor')
  );
$$ language sql security definer stable;

-- ------------------------------------------------------------
-- 2) Opdatér app_content-politikkerne til at bruge is_editor()
--    (samme regel som før, bare via hjælpefunktionen)
-- ------------------------------------------------------------
drop policy if exists "Admin og redaktør må oprette" on app_content;
create policy "Admin og redaktør må oprette"
    on app_content for insert
    with check (is_editor());

drop policy if exists "Admin og redaktør må opdatere" on app_content;
create policy "Admin og redaktør må opdatere"
    on app_content for update
    using (is_editor());

drop policy if exists "Admin og redaktør må slette" on app_content;
create policy "Admin og redaktør må slette"
    on app_content for delete
    using (is_editor());

-- ------------------------------------------------------------
-- 3) profiles — nu må ADMINISTRATORER se og redigere alle brugeres
--    profiler (roller), ikke kun deres egen. Redaktører kan stadig
--    kun se deres egen profil.
-- ------------------------------------------------------------
drop policy if exists "Bruger kan læse egen profil" on profiles;
create policy "Bruger kan læse egen eller alle hvis admin"
    on profiles for select
    using (auth.uid() = id or is_admin());

drop policy if exists "Admin kan opdatere roller" on profiles;
create policy "Admin kan opdatere roller"
    on profiles for update
    using (is_admin())
    with check (is_admin());

drop policy if exists "Admin kan indsætte profiler" on profiles;
create policy "Admin kan indsætte profiler"
    on profiles for insert
    with check (is_admin());

drop policy if exists "Admin kan fjerne adgang" on profiles;
create policy "Admin kan fjerne adgang"
    on profiles for delete
    using (is_admin());

-- ------------------------------------------------------------
-- 4) SPORBARHED: audit_log registrerer automatisk HVEM der har
--    oprettet, ændret eller slettet indhold — håndhævet af en
--    database-trigger, så det IKKE kan omgås fra klienten.
-- ------------------------------------------------------------
alter table app_content add column if not exists updated_by uuid references auth.users(id);
alter table app_content add column if not exists updated_by_email text;

create table if not exists audit_log (
    id              bigint generated always as identity primary key,
    table_name      text not null,
    row_key         text,
    action          text not null,      -- 'INSERT' | 'UPDATE' | 'DELETE'
    changed_by      uuid,
    changed_by_email text,
    old_value       jsonb,
    new_value       jsonb,
    changed_at      timestamptz not null default now()
);

alter table audit_log enable row level security;

-- Kun administratorer må læse aktivitetsloggen
drop policy if exists "Kun admin kan læse audit log" on audit_log;
create policy "Kun admin kan læse audit log"
    on audit_log for select
    using (is_admin());

-- Ingen insert/update/delete-politik for almindelige brugere:
-- audit_log kan KUN skrives til af triggeren nedenfor (security definer),
-- aldrig direkte fra klienten. Det gør loggen troværdig.

create or replace function log_app_content_change() returns trigger as $$
declare
  v_email text;
begin
  select email into v_email from auth.users where id = auth.uid();

  if (tg_op = 'DELETE') then
      insert into audit_log(table_name, row_key, action, changed_by, changed_by_email, old_value)
      values ('app_content', old.key, 'DELETE', auth.uid(), v_email, old.value);
      return old;
  elsif (tg_op = 'UPDATE') then
      new.updated_by := auth.uid();
      new.updated_by_email := v_email;
      insert into audit_log(table_name, row_key, action, changed_by, changed_by_email, old_value, new_value)
      values ('app_content', new.key, 'UPDATE', auth.uid(), v_email, old.value, new.value);
      return new;
  elsif (tg_op = 'INSERT') then
      new.updated_by := auth.uid();
      new.updated_by_email := v_email;
      insert into audit_log(table_name, row_key, action, changed_by, changed_by_email, new_value)
      values ('app_content', new.key, 'INSERT', auth.uid(), v_email, new.value);
      return new;
  end if;
end;
$$ language plpgsql security definer;

drop trigger if exists trg_app_content_audit_iu on app_content;
create trigger trg_app_content_audit_iu
    before insert or update on app_content
    for each row execute function log_app_content_change();

drop trigger if exists trg_app_content_audit_d on app_content;
create trigger trg_app_content_audit_d
    before delete on app_content
    for each row execute function log_app_content_change();

-- ============================================================
-- OM DENNE FIL
-- ============================================================
-- Efter dette script kan I oprette og fjerne administratorer/redaktører
-- direkte fra appens admin-panel (under "Brugere") — I skal ikke længere
-- manuelt indsætte rækker i profiles via SQL Editor (bortset fra jeres
-- allerførste administrator, som stadig oprettes én gang jf.
-- 01_schema_and_rls.sql).
