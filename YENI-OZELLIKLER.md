# Bu sürümde eklenenler

1. **Oda içi oyun – Şişe Çevirme** (oda başlığındaki 🍾 düğmesi)
2. **Medya yükleme düzeltmesi** (istemci kodu + `SUPABASE_MEDYA_VE_OYUN_DUZELTME.sql`)
3. **Emoji Laboratuvarı**: tüm emojiler birleşir, birleşimler otomatik kaydedilir

## ZORUNLU kurulum adımı
Supabase → SQL Editor → `SUPABASE_MEDYA_VE_OYUN_DUZELTME.sql` dosyasını **bir kez** çalıştırın.
Bu dosya `media` deposunu (yoksa) oluşturur, eksik depolama izinlerini ekler ve oda üyelerinin oda belgesini
(mesaj + oyun durumu) güncellemesine izin verir. Tekrar çalıştırmak güvenlidir.

Yayınladıktan sonra tarayıcıda bir kez sert yenileme yapın (servis çalışanı önbelleği `v22` oldu).

# İkinci güncelleme
- Telefon alt menüsü: yüzen, yuvarlatılmış uzun menü. Sıra: Odalar · Liderlik · **Keşfet (ortada)** · Profil · Ara. Bildirim zili alt menüden kalktı (üstteki zil ve çıkış düğmesi duruyor).
- Beğeni ve oylama düzeltildi: `SUPABASE_BEGENI_OYLAMA_DAVET_DUZELTME.sql` dosyasını SQL Editor'de bir kez çalıştırın.
- Gizli hesaplı (gizlilik modu açık) birini odaya eklemek artık onay bildirimi gönderir; kişi "Evet" derse odaya girer, "Hayır" derse davet reddedilir ve davet eden bilgilendirilir.
- Servis çalışanı önbelleği `v23`.
