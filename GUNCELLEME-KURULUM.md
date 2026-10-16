# Aura X — Yeni güncellemeler ve gerekli kurulum

Bu paket mevcut Aura X dosyalarının üzerine çalışan değişiklikleri içerir. Bazı özellikler istemci kodunun yanında Supabase Edge Function ve SQL izinleri de gerektirir; bu adımlar yapılmadan canlı ortamda başarı garantisi verilemez.

## Kodda yapılanlar

- Oda içindeki `+` düğmesine yukarı sıçrama ve parıltı animasyonu eklendi.
- Oda arka planları 16 temaya, konuşma baloncuğu seçenekleri koyu/açık toplam 48 renge çıkarıldı.
- Profil ayarlarının altına gönderiler, beğenilen gönderiler, gelen/alınan özel mesajlar ve etkinlik sayıları eklendi.
- Hesap silme için sunucu tarafında `delete-account` Edge Function eklendi; yalnızca doğrulanmış oturumun sahibi hesabını silebilir.
- Hikâye paylaşım izinleri tek SQL yamasında toplandı. Hikâyeler yalnızca kendisini takip eden kişilere görünür.
- Bildirimi oluşturan işlem artık `push-notify` Edge Function'ını çağırır; bu, uygulama kapalıyken Web Push gönderiminin sunucu tarafını sağlar.
- Oda sohbetinde tarih ayraçları ve mesajların saatleri görünür. Özel mesaj konuşmaları da tarih/saat gösterir.
- AURAI'nin Türkçe selamlaşmaları ve Aura X yardım bilgi tabanı genişletildi.
- 192px ve 512px Aura X uygulama simgeleri yenilendi; eski FCM `gcm_sender_id` alanı manifestten kaldırıldı ve Service Worker önbellek sürümü yükseltildi.

## 1. Hikâye paylaşımı ve gizliliği

Supabase Dashboard → **SQL Editor**'ü açıp `supabase_aura_status_policy_fix.sql` dosyasının tamamını çalıştır. Bu dosya `statuses` için kendi hikâyeni oluşturma/güncelleme/silme izinlerini ve yalnızca takipçilerin görüntülemesi kuralını tanımlar. Medya yükleme politikası için `media` Storage bucket'ının daha önce kurulum dosyalarında oluşturulmuş olması gerekir.

## 2. Push bildirimleri (uygulama kapalıyken)

SQL Editor'de `supabase_aura_push_setup.sql` dosyasını çalıştır. Ardından iki fonksiyonu yayımla:

```bash
supabase functions deploy push-notify
supabase functions deploy delete-account
```

`push-notify` için Web Push VAPID anahtar çifti gerekir. Bu, ücretsiz Web Push protokolü anahtarıdır; bir ücretli sağlayıcı aboneliği değildir. Node.js kurulu bilgisayarda `web-push` aracıyla bir çift oluşturabilirsin:

```bash
npx web-push generate-vapid-keys
```

Komutun verdiği **Public Key** değerini `index.html` içindeki `SUPABASE_VAPID_PUBLIC_KEY` ile değiştir ve aynı değeri Supabase Dashboard → Edge Functions → Secrets bölümündeki `WEB_PUSH_VAPID_PUBLIC_KEY` secret'ına koy. Komutun verdiği **Private Key** değerini yalnızca `WEB_PUSH_VAPID_PRIVATE_KEY` secret'ına koy; bu özel anahtarı HTML'ye, Git deposuna veya herkese açık bir dosyaya ekleme. Ek olarak `WEB_PUSH_VAPID_SUBJECT` değerini `mailto:destek-adresin` biçiminde ayarla.

Supabase Edge Functions'ın sistem değişkenleri olan `SUPABASE_URL`, `SUPABASE_ANON_KEY` ve `SUPABASE_SERVICE_ROLE_KEY` tanımlı olmalı. `service_role` anahtarını uygulamanın ön yüz koduna yazma. Tarayıcı/telefon için bildirim izni de kullanıcının kendisi tarafından verilmelidir. iPhone'da Web Push için desteklenen iOS sürümünde Aura X'i Ana Ekrana ekleyip ana ekrandaki simgeden açmak gerekir.

## 3. Hesap silme

`delete-account` Edge Function'ı, JWT oturumunu doğrular; istemcinin gönderdiği kullanıcı adını yetkili kabul etmez. Bağlı profil/veri kayıtlarını temizleyip Supabase Auth kullanıcısını silmeye çalışır. Fonksiyonun `SUPABASE_SERVICE_ROLE_KEY` secret'ına erişmesi gerekir. Canlı ortamda gerçek bir hesabı silmeden önce test hesabıyla sınama yap.

## 4. Test

Proje klasöründe:

```bash
node --check aurai-widget.js
node --test tests/aurai-logic.test.cjs
```

`index.html` içindeki satır içi JavaScript için paketleme öncesinde tarayıcı konsolunda hata kontrolü de yap. SQL dosyaları ve Edge Function'lar ZIP içinde bulunur ancak bu arşivi oluşturmak onları Supabase projesine otomatik yayımlamaz.

## Sınırlamalar

- Web Push'ın kapalı uygulamaya ulaşması, doğru VAPID anahtar eşleşmesi, izin verilmiş tarayıcı/cihaz ve `push-notify` fonksiyonunun yayımlanmasına bağlıdır.
- Hesap silme birden fazla veritabanı tablosu ve Auth kaydını etkiler. Supabase proje şemasındaki tablo adları farklıysa fonksiyon hata döndürür; canlıya almadan test hesabında doğrula.
- AURAI'nin sunucu tabanlı genel sohbeti için `aurai-chat` Edge Function ve bir model sağlayıcısı gerekir; yerel selamlaşma ve Aura X bilgi cevapları istemci tarafında çalışır.
