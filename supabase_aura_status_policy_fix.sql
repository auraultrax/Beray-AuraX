-- Aura X: Durum (hikâye) oluşturma izinleri
-- Kullanıcılar "Durum Oluştur" ile durum paylaşamıyorsa bu dosyayı Supabase SQL Editor'de bir kez çalıştırın.
-- Her kullanıcı yalnızca kendi adıyla (statuses.id = kullanıcı adı) durum ekleyip güncelleyebilir ve silebilir.
-- Bu dosya güvenlidir: mevcut veriyi silmez, yalnızca statuses tablosu için ekleme/güncelleme/silme politikalarını yeniden kurar.

alter table public.statuses enable row level security;

grant select, insert, update, delete on public.statuses to authenticated;

drop policy if exists statuses_insert_own on public.statuses;
create policy statuses_insert_own
  on public.statuses for insert to authenticated
  with check (id = public.aurax_current_username());

drop policy if exists statuses_update_own on public.statuses;
create policy statuses_update_own
  on public.statuses for update to authenticated
  using (id = public.aurax_current_username())
  with check (id = public.aurax_current_username());

drop policy if exists statuses_delete_own on public.statuses;
create policy statuses_delete_own
  on public.statuses for delete to authenticated
  using (id = public.aurax_current_username());
