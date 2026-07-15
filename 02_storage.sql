-- ============================================================
-- V-SYDDJURS — SUPABASE STORAGE (billeder/QR-koder)
-- Kør denne fil EFTER 01_schema_and_rls.sql
-- ============================================================

-- ------------------------------------------------------------
-- 1) Opret en offentlig bucket kaldet "media"
--    (Kan også oprettes i UI: Storage → New bucket → navn "media",
--    slå "Public bucket" til)
-- ------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('media', 'media', true)
on conflict (id) do nothing;

-- ------------------------------------------------------------
-- 2) RLS-politikker for filer i "media"-bucketen
-- ------------------------------------------------------------

-- Alle må se/hente filer (billeder, QR-koder osv. skal kunne vises for alle)
drop policy if exists "Offentlig læseadgang til media" on storage.objects;
create policy "Offentlig læseadgang til media"
    on storage.objects for select
    using (bucket_id = 'media');

-- Kun admin/redaktør må uploade nye filer
drop policy if exists "Admin og redaktør må uploade til media" on storage.objects;
create policy "Admin og redaktør må uploade til media"
    on storage.objects for insert
    with check (
        bucket_id = 'media'
        and exists (
            select 1 from profiles
            where id = auth.uid() and role in ('admin', 'redaktor')
        )
    );

-- Kun admin/redaktør må opdatere/udskifte filer
drop policy if exists "Admin og redaktør må opdatere media" on storage.objects;
create policy "Admin og redaktør må opdatere media"
    on storage.objects for update
    using (
        bucket_id = 'media'
        and exists (
            select 1 from profiles
            where id = auth.uid() and role in ('admin', 'redaktor')
        )
    );

-- Kun admin/redaktør må slette filer
drop policy if exists "Admin og redaktør må slette media" on storage.objects;
create policy "Admin og redaktør må slette media"
    on storage.objects for delete
    using (
        bucket_id = 'media'
        and exists (
            select 1 from profiles
            where id = auth.uid() and role in ('admin', 'redaktor')
        )
    );
