-- Aura X: tarayıcı Web Push abonelikleri
-- Bu dosyayı Supabase SQL Editor'de bir kez çalıştırın. Uygulama push aboneliğini push_tokens.data içinde saklar.

create table if not exists public.push_tokens (
  id text primary key,
  data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.push_tokens enable row level security;
grant select, insert, update, delete on public.push_tokens to authenticated;

drop policy if exists aurax_push_tokens_select_own on public.push_tokens;
create policy aurax_push_tokens_select_own on public.push_tokens
for select to authenticated
using (data->>'username' = public.aurax_current_username() or public.aurax_is_admin());

drop policy if exists aurax_push_tokens_insert_own on public.push_tokens;
create policy aurax_push_tokens_insert_own on public.push_tokens
for insert to authenticated
with check (data->>'username' = public.aurax_current_username() or public.aurax_is_admin());

drop policy if exists aurax_push_tokens_update_own on public.push_tokens;
create policy aurax_push_tokens_update_own on public.push_tokens
for update to authenticated
using (data->>'username' = public.aurax_current_username() or public.aurax_is_admin())
with check (data->>'username' = public.aurax_current_username() or public.aurax_is_admin());

drop policy if exists aurax_push_tokens_delete_own on public.push_tokens;
create policy aurax_push_tokens_delete_own on public.push_tokens
for delete to authenticated
using (data->>'username' = public.aurax_current_username() or public.aurax_is_admin());

comment on table public.push_tokens is 'Aura X web push subscriptions keyed by subscription hash; private key is stored only in Edge Function secrets.';
