# AURAI değişiklik özeti

## Değiştirilen dosyalar

- `aurai-widget.js` — AURAI sohbet panelinin tasarımı, başlangıç kısayolları, yeni sohbet, yanıt kopyalama, güvenli metin/link gösterimi, isteğe bağlı web araştırması, hafif/standart yerel model seçimi, Türkçe yazım toleransı ve oturum değişiminde eski yanıtları temizleme geliştirildi.
- `supabase/functions/aurai-chat/index.ts` — kimlik doğrulama/secret kontrolleri, mesaj boyutu sınırı, maliyet kullanım sınırı ve daha ayrıntılı eğitim/teknik yardım talimatları geliştirildi.
- `supabase/functions/aurai-search/index.ts` — arama anahtarı sunucuda tutulur; oturum kontrolü, istek limitleri, zaman aşımı, yanıt boyutu sınırı ve HTTP(S) bağlantı doğrulaması eklendi.
- `sw.js` — önbellek sürümü `aura-x-v16` yapıldı; yeni AURAI dosyalarının eski önbellekte kalma olasılığı azaltıldı.

## Yeni dosyalar

- `supabase/aurai_usage_setup.sql` — günlük kullanıcı ve toplam istek sayaçları için SQL kurulumu.
- `AURAI-KURULUM.md` — SQL, Edge Function ve secret kurulum adımları.
- `tests/aurai-logic.test.cjs` — metin normalleştirme, selamlaşma, bilinen Aura X soruları ve yanlış anahtar kelime eşleşmeleri için otomatik testler.

## Bilerek değiştirilmedi

`index.html`, `supabase-bridge.js`, `manifest.json`, ikonlar ve Aura durum/hikâye SQL dosyaları değiştirilmedi. Ana uygulama akışına müdahale edilmedi.

## Yayına alma sırası

1. `supabase/aurai_usage_setup.sql` içeriğini Supabase SQL Editor'de çalıştır.
2. `aurai-chat` ve `aurai-search` Edge Function'larını güncel kodla yeniden yayımla.
3. `aurai-widget.js` ve `sw.js` dosyalarını web sitesinde güncelle.
4. Oturum açarak AURAI sohbetini, `/ara ...` araştırmasını ve hata durumlarını dene.
