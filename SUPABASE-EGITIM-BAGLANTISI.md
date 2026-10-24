# Aura X + Beray Eğitim ortak Supabase kurulumu

Bu klasör Aura X'i ve Eğitim uygulamasının Edge Function'larını aynı Supabase projesinde tutar.

1. Supabase Dashboard → SQL Editor'ü açın ve bu klasördeki `SUPABASE_TUM_KURULUM.sql` dosyasının tamamını çalıştırın. Dosya Aura X şema/izinlerini ve Education tablolarını tek sırada birleştirir.
2. Aşağıdaki komutları bu klasörde çalıştırın. Önce Supabase CLI ile oturum açın, `PROJE_REF` değerini kendi Supabase proje kimliğinizle değiştirin:

   ```bash
   supabase login
   supabase link --project-ref PROJE_REF
   supabase functions deploy username-login --no-verify-jwt
   supabase functions deploy username-available --no-verify-jwt
   supabase functions deploy education-actions
   ```

3. Supabase → Authentication → Providers içinde e-posta/şifre sağlayıcısının açık olduğundan emin olun. Google/Apple ile kayıt kullanılan Aura X akışında provider ayarları ve redirect URL'leri ayrıca doğru olmalıdır.
4. Eğitim sitesindeki `supabase-compat.js` içinde belirtilen URL ve publishable key'in burada bağlı olduğunuz **aynı** projeye ait olduğunu doğrulayın.
5. `supabase/functions/education-actions/ready_bank.json` ve `curriculum_seed.json` dosyalarını silmeyin. Bunlar test bankası ve müfredat tohum verileridir; web sunucusunun herkese açık statik dosyaları arasında yer almamalıdır.

## Önemli

- SQL çalıştırmak tek başına Edge Function yayımlamaz; CLI komutları da ayrıca çalıştırılmalıdır.
- İlk Education kayıtları öğrenci rolüyle oluşur. İlk admin yetkisi, yalnızca kendi Auth UUID'niz doğrulandıktan sonra `public.education_records` tablosunda `role` alanına verilir.
- Bu ZIP canlı Supabase projesinde otomatik değişiklik yapmaz. Önce yedek alın ve SQL'i doğru projede çalıştırdığınızı kontrol edin.

**Cevap anahtarı gizliliği:** ZIP, Edge Function'ı yerelde yayımlayabilmeniz için banka JSON dosyalarını içerir. Bunları herkese açık Git deposuna elle yüklemeyin; `.gitignore` ile dışarıda tutulurlar. Kod deposu herkese açıksa yalnızca `_config.yml` yeterli olmaz; Git sağlayıcısında özel repo veya özel sunucu dağıtım deposu kullanın.
