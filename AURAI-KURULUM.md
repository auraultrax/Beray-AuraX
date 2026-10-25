# AURAI — geliştirme ve kurulum notları

Bu sürüm, Aura X içindeki AURAI panelini ve AURAI Edge Function'larını geliştirir. Mevcut `index.html`, Supabase bağlantı adresi ve yayınlanan uygulamanın ana akışı korunmuştur.

## Neler geliştirildi?

- AURAI paneline başlangıç kısayolları, yeni sohbet düğmesi, erişilebilir etiketler, yanıt kopyalama ve güvenli biçimlendirilmiş metin eklendi.
- Genel konuşma ile güncel internet araması ayrıldı. Arama yalnızca `/ara aramak istediğin konu` veya açık bir araştırma isteğiyle başlatılır; her bilinmeyen mesaj artık otomatik olarak Google aramasına çevrilmez.
- Bilinen Aura X soruları önce yerel bilgi tabanından yanıtlanır. Kısa anahtar kelimelerin çok geniş eşleşmesi daraltıldı.
- AURAI modeline gönderilen geçmişin boyutu sınırlandı. Yanıt içindeki bağlantılar güvenli HTTP(S) bağlantıları olarak işlenir; mesaj metninden HTML çalıştırılmaz.
- Sohbet ve arama isteklerine günlük kullanıcı/toplam limit kontrolü eklendi. Limit veritabanı kurulmamışsa ücretli modele veya Google aramasına devam etmek yerine açıklayıcı bir hata döndürülür.
- Servis çalışanı önbellek sürümü `v16` yapıldı; bu, yeni AURAI dosyasının eski önbellek nedeniyle görünmemesine karşıdır.

## Kurulum adımları

### 1. Günlük kullanım sayacı SQL'ini çalıştır

Supabase Dashboard → **SQL Editor** bölümünde `supabase/aurai_usage_setup.sql` dosyasının tüm içeriğini bir kez çalıştır. Bu tablo mesaj içeriğini saklamaz; yalnızca günlük istek sayılarını tutar.

### 2. Edge Function'ları yayımla

Supabase projesinde şu iki fonksiyonun kodunu dosyalardaki son hâliyle güncelle ve deploy et:

- `supabase/functions/aurai-chat/index.ts` → `aurai-chat`
- `supabase/functions/aurai-search/index.ts` → `aurai-search`

Supabase CLI kullanıyorsan proje klasöründe:

```bash
supabase functions deploy aurai-chat
supabase functions deploy aurai-search
```

### 3. Secret değerlerini kontrol et

Secret'ları yalnızca Supabase **Edge Function Secrets** bölümüne gir; HTML/JavaScript dosyalarına koyma.

| Secret | Amaç |
|---|---|
| `AURAI_API_URL` | OpenAI uyumlu sağlayıcı için API temel adresi; Anthropic kullanılıyorsa `https://api.anthropic.com` |
| `AURAI_MODEL` | Sağlayıcıda kullanılacak model adı |
| `AURAI_API_KEY` | Model sağlayıcısının gizli anahtarı; Anthropic için gerekli |
| `AURAI_DAILY_LIMIT` | Kişi başı sohbet isteği limiti; varsayılan `30` |
| `AURAI_SEARCH_DAILY_LIMIT` | Kişi başı arama limiti; varsayılan `10` |
| `AURAI_DAILY_BUDGET` | Sohbet ve arama için ortak günlük toplam istek limiti; varsayılan `5000` |
| `GOOGLE_CSE_KEY` | Google Programmable Search API anahtarı |
| `GOOGLE_CSE_CX` | Google Programmable Search Engine kimliği |

Supabase tarafından sağlanan `SUPABASE_URL`, `SUPABASE_ANON_KEY` ve `SUPABASE_SERVICE_ROLE_KEY` ortam değişkenlerinin Edge Function ortamında bulunduğunu da doğrula. `service_role` anahtarını asla istemciye veya bu ZIP'e ekleme.

İnternet araması için `GOOGLE_CSE_KEY` ve `GOOGLE_CSE_CX` olmadan arama özelliği çalışmaz. Genel model için erişilebilir bir sağlayıcı/model tanımlanmalıdır. **Bu kod tek başına ücretsiz bir yapay zekâ servisi sağlamaz**; seçilen sağlayıcının ücretsiz kotası, kullanım koşulları ve ücretleri ayrıdır. Beklenmedik harcamayı önlemek için `AURAI_DAILY_BUDGET` değerini ihtiyacına göre daha düşük belirleyebilirsin.

### 4. Ön yüz dosyalarını yayımla

Güncellenmiş `aurai-widget.js` ve `sw.js` dosyalarını diğer uygulama dosyalarıyla birlikte yayınla. AURAI giriş yapmış kullanıcıya görünür; genel sohbet için Supabase `aurai-chat` fonksiyonuna ulaşması gerekir.

## Hızlı test

Node.js kurulu bir bilgisayarda proje klasöründen:

```bash
node --check aurai-widget.js
node --test tests/aurai-logic.test.cjs
```

Edge Function kodlarını yayınladıktan sonra bir test hesabıyla normal sohbeti, `/ara Türkiye teknoloji gündemi` sorgusunu ve günlük limit aşıldığında dönen yanıtı dene. Gerçek model yanıtı için test ortamında model sağlayıcı secret'larının tanımlı olması gerekir.
