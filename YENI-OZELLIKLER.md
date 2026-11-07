# Bu sürümde eklenenler

1. **Oda içi oyun – Şişe Çevirme** (oda başlığındaki 🍾 düğmesi)
2. **Medya yükleme düzeltmesi** (istemci kodu + `SUPABASE_MEDYA_VE_OYUN_DUZELTME.sql`)
3. **Emoji Laboratuvarı**: tüm emojiler birleşir, birleşimler otomatik kaydedilir

## ZORUNLU kurulum adımı
Supabase → SQL Editor → `SUPABASE_MEDYA_VE_OYUN_DUZELTME.sql` dosyasını **bir kez** çalıştırın.
Bu dosya `media` deposunu (yoksa) oluşturur, eksik depolama izinlerini ekler ve oda üyelerinin oda belgesini
(mesaj + oyun durumu) güncellemesine izin verir. Tekrar çalıştırmak güvenlidir.

Yayınladıktan sonra tarayıcıda bir kez sert yenileme yapın (servis çalışanı önbelleği `v22` oldu).
