# Aura X - Bu sürümdeki değişiklikler

## Güncelleme / kurulum sırası
1. Yedek alın ve önce test Supabase projesinde deneyin.
2. Daha önce temel güvenlik dosyalarını uygulamadıysanız `supabase_final_security_setup.sql` dosyasını çalıştırın. Zaten çalıştırdıysanız tekrar çalıştırmanız gerekmez.
3. Yeni özellikler için `supabase_aura_story_emoji_setup.sql` dosyasını Supabase SQL Editor'da çalıştırın.
4. AURAI değişikliği için `supabase functions deploy aurai-chat` komutuyla `supabase/functions/aurai-chat/index.ts` dosyasını yeniden deploy edin.
5. Güncellenen `index.html`, `supabase-bridge.js`, `aurai-widget.js`, `sw.js` ve SQL yamasını GitHub'a yükleyin. Service worker sürümü artırıldı; yeni sürümün gelmesi için sayfayı yeniden yükleyin.

## Güvenlik
- youtube-search: yalnızca giriş yapmış kullanıcılar arama yapabilir (API kotası korunur).
- username-login / youtube-search: hatalı CORS import'u düzeltildi (fonksiyon çalışmıyordu).
- Sohbet: resim URL'si ve emoji tepki anahtarları artık kaçışlanıyor (XSS kapatıldı).

## Yeni / düzeltilen özellikler
- Duyuru: her duyuru kullanıcıya bir kez gösterilir. Hiç oda girmemiş kullanıcılar akışta görür; daha önce oda girmiş kullanıcılar duyuruyu odanın içinde görür.
- Oda içi (+) menüsü: resim, video, kişiye özel mesaj, çıkartma gönder/oluştur.
- Medya artık Supabase Storage'a yüklenir (oda belgesi şişmez, gönderim hızlanır). Resimler gönderilmeden önce küçültülür.
- Klavye açılınca mesaj kutusu klavyenin hemen üstünde kalır (siyah boşluk düzeltildi).
- Keşfet akışı tetiklemeleri birleştirilir; eski asenkron render yeni çizimin üzerine yazamaz ve aynı gönderi kimliği aynı çizimde ikinci kez gösterilmez.
- Profilde kullanıcı adı değiştirilebilir. Aynı ad (büyük/küçük harf farkı dahil) kabul edilmez. Tüm mesaj ve referanslar yeni ada taşınır.
- Çıkartma oluşturma (512px, kare) ve odada paylaşma. Başkasının çıkartmasını "Çıkartmaya ekle" ile kaydetme.
- Mesajlardaki başkasına ait bir emojiye tıklanınca Emoji Challenge animasyonu çalışır; çoklu emoji efekti ekrandan aşağıdan yukarı çıkar.
- Oda (+) menüsündeki Emoji Laboratuvarı iki emojiyle birleştirilmiş çıkartma görseli üretip odaya yollar. Bu, Unicode'a yeni emoji eklemez; PNG çıkartması üretir.
- Hikâyelere 50 MB'a kadar video eklenebilir ve takip edilen kişilerin hikâyeleri beğenilebilir. Hikâye satırlarına erişim RLS ile hikâye sahibi/takipçisi olarak sınırlandırılır.
- Profil fotoğrafı, mümkün olduğunda JPEG'e çevrilip 1024 piksel sınırına küçültülür; desteklenen cihazlardaki biçim/boyut uyuşmazlıkları azalır.
- Supabase köprüsü güncel belge anlık görüntülerini güvenli biçimde önbelleğe alarak bazı update işlemlerinde fazladan okuma isteğini atlayabilir.
- Mobil: profil, oda listesi ve oda oluşturma butonları alt çentik/ev çubuğunun altında kalmaz.
- Mobil: yazı alanları 16px (iOS'un otomatik yakınlaştırmasını önler).

## AURAI (yapay zekâ asistanı)
1. `supabase_aurai_setup.sql` dosyasını SQL Editor'da çalıştır.
2. Secret'ları tanımla: `AURAI_API_URL`, `AURAI_MODEL`, `AURAI_API_KEY` (ayrıntı: `AURAI_KURULUM.md`).
3. `supabase functions deploy aurai-chat` komutuyla fonksiyonu yükle.
4. `index.html`, `aurai-widget.js`, `sw.js` ve `supabase/` klasörünü GitHub'a yükle.
- Giriş yapmış kullanıcıya sağ altta "✨ AURAI" düğmesi çıkar. Kişi başı günlük limit ve site geneli bütçe sigortası vardır; kriz mesajları limitten muaftır.
- AURAI artık Aura X kurulum/kullanım/sorun giderme danışmanı olarak yönlendirilir. Genel amaçlı araştırma yerine Aura X kapsamına döner; selamlaşmaları ve gündelik Türkçe ifadeleri doğal şekilde yanıtlar.

## Canlıya almadan önce önemli kontrol
- Gerçek Supabase projesinde hikâye SQL yamasını ve Edge Function deploy'unu uygulayıp takipçi/sahip/farklı kullanıcı senaryolarını test edin.
- Hikâye kaydı RLS ile korunur; ancak mevcut `media` bucket'ı genel erişimli olduğu için daha önce paylaşılan/doğrudan bilinen medya URL'leri ayrı bir özel bucket'a taşınmadıkça herkese açık kalabilir. Sadece medya URL'si seviyesinde katı gizlilik için ayrı private story bucket ve kısa ömürlü signed URL akışı gerekir; bu pakette, diğer medya bağlantılarını bozmamak için bucket genel erişimi değiştirilmedi.
