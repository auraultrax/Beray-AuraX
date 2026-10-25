import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import readyBank from './ready_bank.json' with { type: 'json' };
import curriculumSeed from './curriculum_seed.json' with { type: 'json' };

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || '';
const ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY') || Deno.env.get('SUPABASE_PUBLISHABLE_KEY') || '';
const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';
const json = (payload: unknown, status = 200) => new Response(JSON.stringify(payload), {
  status, headers: { ...corsHeaders, 'Content-Type': 'application/json; charset=utf-8' }
});
class ApiError extends Error {
  status: number; code: string;
  constructor(status: number, code: string, message: string) { super(message); this.status = status; this.code = code; }
}
const timestamp = () => ({ seconds: Math.floor(Date.now() / 1000), nanoseconds: (Date.now() % 1000) * 1_000_000 });
const clean = (v: unknown, max = 5000) => typeof v === 'string' ? v.trim().slice(0, max) : '';
const asArray = (v: unknown) => Array.isArray(v) ? v : [];
const randomId = () => crypto.randomUUID();
const recordRow = (collection_name: string, id: string, data: Record<string, unknown>) => ({ collection_name, id, data });

let service: ReturnType<typeof createClient>;
async function getRecord(collectionName: string, id: string) {
  const { data, error } = await service.from('education_records').select('id,data,updated_at').eq('collection_name', collectionName).eq('id', id).maybeSingle();
  if (error) throw new ApiError(500, error.code || 'database_error', error.message || 'Supabase verisi okunamadı.');
  return data ? { id: data.id as string, data: (data.data || {}) as Record<string, any>, updated_at: data.updated_at } : null;
}
async function writeRecord(collectionName: string, id: string, data: Record<string, any>) {
  const { error } = await service.from('education_records').upsert(recordRow(collectionName, id, data), { onConflict: 'collection_name,id' });
  if (error) throw new ApiError(500, error.code || 'database_error', error.message || 'Supabase kaydı yazılamadı.');
}
async function deleteRecord(collectionName: string, id: string) {
  const { error } = await service.from('education_records').delete().eq('collection_name', collectionName).eq('id', id);
  if (error) throw new ApiError(500, error.code || 'database_error', error.message || 'Supabase kaydı silinemedi.');
}
async function needProfile(uid: string) {
  const row = await getRecord('users', uid);
  if (!row) throw new ApiError(412, 'failed-precondition', 'Eğitim profili bulunamadı. Önce Aura X ile giriş yap veya eğitim hesabını oluştur.');
  return row.data;
}
function requireStudent(profile: Record<string, any>) {
  if (profile.role !== 'student') throw new ApiError(403, 'permission-denied', 'Bu işlem yalnızca öğrenci hesabında kullanılabilir.');
}
function requireTeacher(profile: Record<string, any>, user: Record<string, any>) {
  if (!['teacher', 'admin'].includes(String(profile.role || ''))) throw new ApiError(403, 'permission-denied', 'Bu işlem için öğretmen yetkisi gerekir.');
  if (user.email && !(user.email_confirmed_at || user.confirmed_at)) throw new ApiError(403, 'permission-denied', 'Öğretmen hesabının e-posta adresi doğrulanmış olmalı.');
}
function requireAdmin(profile: Record<string, any>) {
  if (profile.role !== 'admin') throw new ApiError(403, 'permission-denied', 'Bu işlem yalnızca admin için kullanılabilir.');
}
function publicStudent(uid: string, profile: Record<string, any>) {
  const completedTests = Array.isArray(profile.completedTests) ? profile.completedTests.length : Number(profile.completedTestsCount || 0);
  const completedLessons = Array.isArray(profile.completedLessons) ? profile.completedLessons.length : Number(profile.completedLessonsCount || 0);
  const points = Number(profile.points || 0);
  const badges: string[] = [];
  if (points >= 100) badges.push('⭐ Puan Avcısı');
  if (points >= 500) badges.push('🏆 Yıldız Öğrenci');
  if (completedTests >= 10) badges.push('📝 Test Ustası');
  if (completedLessons >= 10) badges.push('📚 İstikrarlı Öğrenci');
  if (!badges.length) badges.push('🌱 Yeni Başlangıç');
  const username = clean(profile.username || profile.auraxUsername || '', 40);
  return { uid, name: clean(profile.name || profile.displayName || username || 'Öğrenci', 80) || 'Öğrenci', username, usernameLower: clean(profile.usernameLower || username, 40).toLowerCase(), avatarId: ['owl-blue','cat-white','bird-gray','panda-pink','fox-orange','frog-green'].includes(profile.avatarId) ? profile.avatarId : 'owl-blue', points, completedTestsCount: completedTests, completedLessonsCount: completedLessons, badges: badges.slice(0,3) };
}
async function notify(userId: string, title: string, body: string, type: string, extra: Record<string, unknown> = {}) {
  await writeRecord('notifications', randomId(), { userId, title: clean(title,160), body: clean(body,1000), type, read: false, createdAt: timestamp(), ...extra });
}
async function gradeTest(uid: string, testId: string, title: string, picked: number[], key: number[], wrongFocus: string[], ready: boolean) {
  const { data, error } = await service.rpc('education_grade_test', {
    p_user_id: uid,
    p_test_id: testId,
    p_test_title: title,
    p_answers: picked,
    p_answer_key: key,
    p_wrong_focus: wrongFocus,
    p_points_per_correct: ready ? 0 : 5,
    p_is_ready: ready,
  });
  if (error) throw new ApiError(400, error.code || 'test_submit_failed', error.message || 'Test sonucu kaydedilemedi.');
  return data;
}
function validGrade(value: unknown) { const v = String(value || ''); return v === '' || ['5','6','7','8','9','10','11','12'].includes(v); }
async function safeRows(collectionName: string, max = 1000) {
  const { data, error } = await service.from('education_records').select('id,data,updated_at').eq('collection_name', collectionName).order('updated_at', { ascending: false }).limit(max);
  if (error) throw new ApiError(500, error.code || 'database_error', error.message || 'Kayıtlar okunamadı.');
  return (data || []).map((r: any) => ({ id: r.id as string, data: (r.data || {}) as Record<string, any> }));
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json({ error: { code: 'method_not_allowed', message: 'Yalnızca POST isteği kabul edilir.' } }, 405);
  if (!SUPABASE_URL || !ANON_KEY || !SERVICE_KEY) return json({ error: { code: 'server_configuration', message: 'Supabase Edge Function ortam değişkenleri eksik.' } }, 500);
  const authorization = req.headers.get('Authorization') || '';
  if (!/^Bearer\s+\S+/i.test(authorization)) return json({ error: { code: 'unauthenticated', message: 'Önce giriş yapmalısın.' } }, 401);

  try {
    const authClient = createClient(SUPABASE_URL, ANON_KEY, { global: { headers: { Authorization: authorization } }, auth: { persistSession: false, autoRefreshToken: false } });
    const { data: authData, error: authError } = await authClient.auth.getUser();
    const user = authData?.user as Record<string, any> | null;
    if (authError || !user?.id) throw new ApiError(401, 'unauthenticated', 'Oturum doğrulanamadı. Tekrar giriş yap.');
    service = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false, autoRefreshToken: false } });
    const body = await req.json().catch(() => ({}));
    const action = clean(body?.action, 80);
    const uid = String(user.id);
    const profile = await needProfile(uid);
    let output: Record<string, any> = {};

    switch (action) {
      case 'createTest': {
        requireTeacher(profile, user);
        const title = clean(body.title, 200), description = clean(body.description, 2000), grade = clean(body.grade, 2);
        const questions = asArray(body.questions), answers = asArray(body.answers).map(Number);
        if (!title) throw new ApiError(400,'invalid-argument','Test başlığı gerekli.');
        if (!validGrade(grade)) throw new ApiError(400,'invalid-argument','Geçersiz sınıf.');
        if (questions.length < 1 || questions.length > 100 || answers.length !== questions.length) throw new ApiError(400,'invalid-argument','Test 1–100 soru içermeli.');
        const normalized = questions.map((q: any, i: number) => {
          const question = clean(q?.question, 1000);
          const options = asArray(q?.options).map((v) => clean(v,500)).slice(0,6);
          if (!question || options.length < 2 || options.some((v) => !v) || !Number.isInteger(answers[i]) || answers[i] < 0 || answers[i] >= options.length) throw new ApiError(400,'invalid-argument',`Soru ${i + 1} veya doğru cevabı eksik.`);
          return { question, options };
        });
        const testId = randomId();
        await writeRecord('tests', testId, { title, description, grade, questions: normalized, teacherId: uid, teacherName: clean(profile.name || user.user_metadata?.name || 'Öğretmen',80), createdAt: timestamp() });
        const { error } = await service.from('education_test_answer_keys').upsert({ test_id: testId, answers, created_by: uid }, { onConflict: 'test_id' });
        if (error) { await deleteRecord('tests', testId); throw new ApiError(500,error.code || 'answer_key_write_failed','Testin cevap anahtarı kaydedilemedi.'); }
        output = { testId };
        break;
      }
      case 'submitTest': {
        requireStudent(profile);
        const testId = clean(body.testId,200), answers = asArray(body.answers).map(Number);
        if (!testId || !answers.length) throw new ApiError(400,'invalid-argument','Test gönderisi geçersiz.');
        const test = await getRecord('tests', testId);
        const { data: keyRow, error: keyError } = await service.from('education_test_answer_keys').select('answers').eq('test_id', testId).maybeSingle();
        if (!test || keyError || !Array.isArray(keyRow?.answers)) throw new ApiError(404,'not-found','Test bulunamadı veya cevap anahtarı eksik.');
        const questions = asArray(test.data.questions), key = asArray(keyRow.answers).map(Number);
        if (questions.length !== key.length || answers.length !== key.length) throw new ApiError(400,'invalid-argument','Testteki tüm sorular cevaplanmalı.');
        if (!answers.every((v, i) => Number.isInteger(v) && v >= 0 && v < asArray((questions[i] as any)?.options).length)) throw new ApiError(400,'invalid-argument','Cevaplardan biri geçersiz.');
        output = await gradeTest(uid,testId,clean(test.data.title,200) || 'Test',answers,key,[],false);
        break;
      }
      case 'getReadyTest': {
        const testId = clean(body.testId,200), entry = (readyBank as Record<string, any>)[testId];
        if (!entry) throw new ApiError(404,'not-found','Hazır test bulunamadı. Müfredat test bankası güncel değil.');
        output = { questions: entry.questions };
        break;
      }
      case 'checkReadyTest': {
        requireStudent(profile);
        const testId = clean(body.testId,200), entry = (readyBank as Record<string, any>)[testId];
        const answers = asArray(body.answers).map(Number);
        if (!entry || answers.length !== asArray(entry.answers).length || !answers.every((v) => Number.isInteger(v) && v >= 0 && v <= 3)) throw new ApiError(400,'invalid-argument','Test cevapları geçersiz veya eksik.');
        const wrongFocus = [...new Set(answers.flatMap((v,i) => v === Number(entry.answers[i]) ? [] : [clean(entry.questions?.[i]?.focus,200)]).filter(Boolean))].slice(0,6);
        output = await gradeTest(uid,testId,clean(entry.title,200) || testId,answers,entry.answers.map(Number),wrongFocus,true);
        break;
      }
      case 'completeCourse': {
        requireStudent(profile);
        const courseId = clean(body.courseId,200);
        if (!courseId) throw new ApiError(400,'invalid-argument','Ders seçilmedi.');
        const completed = Array.isArray(profile.completedLessons) ? profile.completedLessons : [];
        if (completed.includes(courseId)) { output = { alreadyCompleted: true }; break; }
        await writeRecord('users',uid,{ ...profile, completedLessons:[...completed,courseId], points:Number(profile.points || 0)+10 });
        output = { alreadyCompleted:false, pointsAwarded:10 };
        break;
      }
      case 'setStudentGrade': {
        requireStudent(profile);
        const grade = clean(body.grade,2);
        if (!validGrade(grade) || !grade) throw new ApiError(400,'invalid-argument','Geçerli bir sınıf seç.');
        await writeRecord('users',uid,{ ...profile, grade }); output = { success:true, grade }; break;
      }
      case 'updateStudentProfile': {
        requireStudent(profile);
        const name = clean(body.name,80).replace(/\s+/g,' '), grade = clean(body.grade,2), avatarId = clean(body.avatarId,40);
        if (name.length < 2 || !validGrade(grade) || !grade) throw new ApiError(400,'invalid-argument','Ad soyad ve geçerli sınıf gerekli.');
        if (!['owl-blue','cat-white','bird-gray','panda-pink','fox-orange','frog-green'].includes(avatarId)) throw new ApiError(400,'invalid-argument','Profil avatarı geçersiz.');
        await writeRecord('users',uid,{ ...profile, name, grade, avatarId });
        try { await service.auth.admin.updateUserById(uid,{ user_metadata:{ ...(user.user_metadata || {}), display_name:name } }); } catch (_) {}
        output = { success:true,name,grade,avatarId }; break;
      }
      case 'setUserRole': {
        requireAdmin(profile);
        const userId = clean(body.userId,200), role = clean(body.role,20);
        if (!userId || !['student','teacher'].includes(role) || userId === uid) throw new ApiError(400,'invalid-argument','Kullanıcı veya rol geçersiz.');
        const target = await getRecord('users',userId);
        if (!target) throw new ApiError(404,'not-found','Kullanıcı bulunamadı.');
        if (target.data.role === 'admin') throw new ApiError(412,'failed-precondition','Başka bir adminin rolü bu panelden değiştirilemez.');
        await writeRecord('users',userId,{ ...target.data, role }); output = { success:true,role }; break;
      }
      case 'deleteCourse': {
        requireTeacher(profile,user);
        const courseId = clean(body.courseId,200), course = await getRecord('courses',courseId);
        if (!course) throw new ApiError(404,'not-found','Ders bulunamadı.');
        if (profile.role !== 'admin' && course.data.teacherId !== uid) throw new ApiError(403,'permission-denied','Bu dersi silemezsin.');
        const lessons = await safeRows('lessons');
        let deletedLessons = 0;
        for (const lesson of lessons.filter((r) => r.data.courseId === courseId)) { await deleteRecord('lessons',lesson.id); deletedLessons++; }
        await deleteRecord('courses',courseId); output = { success:true,deletedLessons }; break;
      }
      case 'deleteLesson': {
        requireTeacher(profile,user);
        const lessonId = clean(body.lessonId,200), lesson = await getRecord('lessons',lessonId);
        if (!lesson) throw new ApiError(404,'not-found','Konu bulunamadı.');
        if (profile.role !== 'admin' && lesson.data.teacherId !== uid) throw new ApiError(403,'permission-denied','Bu konuyu silemezsin.');
        await deleteRecord('lessons',lessonId); output = { success:true }; break;
      }
      case 'deleteTest': {
        requireTeacher(profile,user);
        const testId = clean(body.testId,200), test = await getRecord('tests',testId);
        if (!test) throw new ApiError(404,'not-found','Test bulunamadı.');
        if (profile.role !== 'admin' && test.data.teacherId !== uid) throw new ApiError(403,'permission-denied','Bu testi silemezsin.');
        await deleteRecord('tests',testId);
        const { error } = await service.from('education_test_answer_keys').delete().eq('test_id',testId);
        if (error) throw new ApiError(500,error.code || 'delete_failed','Test cevap anahtarı silinemedi.');
        output = { success:true }; break;
      }
      case 'migrateLegacyTests': {
        requireAdmin(profile);
        const rows = await safeRows('tests'); let migrated = 0;
        for (const row of rows) {
          const questions = asArray(row.data.questions);
          if (!questions.some((q: any) => Number.isInteger(q?.correctAnswer))) continue;
          const answers = questions.map((q: any) => Number(q.correctAnswer));
          const cleaned = questions.map((q: any) => { const { correctAnswer: _answer, ...publicQuestion } = q; return publicQuestion; });
          const { error } = await service.from('education_test_answer_keys').upsert({ test_id: row.id, answers, created_by: row.data.teacherId || uid }, { onConflict: 'test_id' });
          if (error) throw new ApiError(500,error.code || 'migration_failed','Cevap anahtarı taşınamadı.');
          await writeRecord('tests',row.id,{ ...row.data, questions:cleaned }); migrated++;
        }
        output = { success:true,updated:migrated }; break;
      }
      case 'seedCurriculum': {
        requireAdmin(profile);
        const seed = curriculumSeed as any;
        const items: Array<{collection_name:string; id:string; data:Record<string,any>}> = [];
        for (const c of asArray(seed.courses)) items.push(recordRow('courses',String(c.id),{ ...c,createdAt:timestamp() }));
        for (const l of asArray(seed.lessons)) items.push(recordRow('lessons',String(l.id),{ ...l,createdAt:timestamp() }));
        for (const t of asArray(seed.tests)) {
          const { questions, ...rest } = t as any;
          const publicQuestions = asArray(questions).map((q: any) => { const { correctAnswer: _answer, ...safe } = q; return safe; });
          items.push(recordRow('tests',String(t.id),{ ...rest, questions:publicQuestions,createdAt:timestamp() }));
        }
        for (let i=0;i<items.length;i+=100) {
          const { error } = await service.from('education_records').upsert(items.slice(i,i+100),{ onConflict:'collection_name,id' });
          if (error) throw new ApiError(500,error.code || 'seed_failed',error.message || 'Müfredat kayıtları yazılamadı.');
        }
        const keys = asArray(seed.testAnswers).map((a: any) => ({ test_id:String(a.testId || a.id),answers:asArray(a.answers),created_by:uid }));
        for (let i=0;i<keys.length;i+=100) {
          const { error } = await service.from('education_test_answer_keys').upsert(keys.slice(i,i+100),{ onConflict:'test_id' });
          if (error) throw new ApiError(500,error.code || 'seed_failed','Müfredat cevap anahtarları yazılamadı.');
        }
        output = { courses:asArray(seed.courses).length, lessons:asArray(seed.lessons).length, tests:asArray(seed.tests).length }; break;
      }
      case 'searchStudents': {
        requireStudent(profile);
        const raw = clean(body.query,40); if (raw.length < 2) throw new ApiError(400,'invalid-argument','Aramak için en az iki karakter yaz.');
        const rows = await safeRows('users'); const q = raw.toLocaleLowerCase('tr-TR');
        const results = rows.filter((r) => r.id !== uid && r.data.role === 'student').map((r) => publicStudent(r.id,r.data))
          .filter((p) => p.usernameLower.includes(raw.toLowerCase()) || p.name.toLocaleLowerCase('tr-TR').includes(q))
          .sort((a,b) => (a.usernameLower === raw.toLowerCase() ? 0 : 1) - (b.usernameLower === raw.toLowerCase() ? 0 : 1) || a.usernameLower.localeCompare(b.usernameLower,'tr')).slice(0,25);
        output = { results }; break;
      }
      case 'requestFollow': {
        requireStudent(profile);
        const targetUid = clean(body.targetUid,160); if (!targetUid || targetUid === uid) throw new ApiError(400,'invalid-argument','Kendini takip edemezsin.');
        const target = await getRecord('users',targetUid); if (!target || target.data.role !== 'student') throw new ApiError(404,'not-found','Öğrenci bulunamadı.');
        const friendshipId = [uid,targetUid].sort().join('__'), requestId = `${uid}_${targetUid}`;
        const friend = await getRecord('friendships',friendshipId), oldRequest = await getRecord('followRequests',requestId);
        if (friend) throw new ApiError(409,'already-exists','Bu öğrenciyle zaten arkadaşsınız.');
        if (oldRequest?.data.status === 'pending') throw new ApiError(409,'already-exists','Takip isteğin zaten gönderilmiş.');
        await writeRecord('followRequests',requestId,{ fromUid:uid,toUid:targetUid,status:'pending',fromName:profile.name || 'Öğrenci',toName:target.data.name || 'Öğrenci',createdAt:timestamp(),updatedAt:timestamp() });
        const actor = publicStudent(uid,profile);
        await notify(targetUid,'Yeni takip isteği',`${actor.username || actor.name} Öğrenci seni takip etmek istiyor.`,'follow-request',{ actorUid:uid,relatedId:requestId });
        output = { success:true }; break;
      }
      case 'respondFollow': {
        requireStudent(profile);
        const requestId = clean(body.requestId,300), decision = clean(body.decision,20), reqRow = await getRecord('followRequests',requestId);
        if (!reqRow) throw new ApiError(404,'not-found','Takip isteği bulunamadı.');
        if (reqRow.data.toUid !== uid) throw new ApiError(403,'permission-denied','Bu takip isteği sana ait değil.');
        if (reqRow.data.status !== 'pending' || !['accept','reject'].includes(decision)) throw new ApiError(412,'failed-precondition','Bu istek artık yanıtlanamıyor.');
        const fromUid = String(reqRow.data.fromUid || ''), accepted = decision === 'accept';
        await writeRecord('followRequests',requestId,{ ...reqRow.data,status:accepted?'accepted':'rejected',updatedAt:timestamp() });
        if (accepted) { const friendshipId = [uid,fromUid].sort().join('__'); await writeRecord('friendships',friendshipId,{ members:[uid,fromUid].sort(),userA:[uid,fromUid].sort()[0],userB:[uid,fromUid].sort()[1],createdAt:timestamp() }); }
        const actor = publicStudent(uid,profile);
        await notify(fromUid,accepted?'Takip isteğin kabul edildi':'Takip isteğin reddedildi',`${actor.username || actor.name} takip isteğine ${accepted?'olumlu':'olumsuz'} yanıt verdi.`,accepted?'follow-accepted':'follow-rejected',{ actorUid:uid,relatedId:requestId });
        output = { success:true,status:accepted?'accepted':'rejected' }; break;
      }
      case 'getStudentSocial': {
        requireStudent(profile);
        const [reqRows,friendRows,transferRows] = await Promise.all([safeRows('followRequests'),safeRows('friendships'),safeRows('pointTransfers')]);
        const incomingRows = reqRows.filter((r) => r.data.toUid === uid && r.data.status === 'pending');
        const outgoingRows = reqRows.filter((r) => r.data.fromUid === uid && r.data.status === 'pending');
        const friendUids = friendRows.filter((r) => asArray(r.data.members).includes(uid)).map((r) => asArray(r.data.members).find((x) => x !== uid)).filter(Boolean) as string[];
        const ids = [...new Set([...incomingRows.map((r) => String(r.data.fromUid)),...outgoingRows.map((r) => String(r.data.toUid)),...friendUids])].filter((id) => id !== uid);
        const profiles = new Map<string,any>();
        for (const otherId of ids) { const other = await getRecord('users',otherId); if (other) profiles.set(otherId,publicStudent(otherId,other.data)); }
        const incoming = incomingRows.map((r) => ({ id:r.id,...r.data,student:profiles.get(String(r.data.fromUid)) || { uid:r.data.fromUid,name:r.data.fromName || 'Öğrenci' } }));
        const outgoing = outgoingRows.map((r) => ({ id:r.id,...r.data,student:profiles.get(String(r.data.toUid)) || { uid:r.data.toUid,name:r.data.toName || 'Öğrenci' } }));
        const friends = friendUids.map((id) => profiles.get(id)).filter(Boolean).sort((a,b) => a.name.localeCompare(b.name,'tr'));
        const transfers = transferRows.filter((r) => r.data.fromUid === uid || r.data.toUid === uid).sort((a,b) => Number(b.data.createdAt?.seconds || 0) - Number(a.data.createdAt?.seconds || 0)).slice(0,40).map((r) => {
          const direction = r.data.fromUid === uid ? 'out' : 'in', otherId = direction === 'out' ? r.data.toUid : r.data.fromUid;
          return { id:r.id,...r.data,direction,other:profiles.get(String(otherId)) || { uid:otherId,name:direction==='out' ? r.data.toName : r.data.fromName } };
        });
        output = { me:publicStudent(uid,profile),incoming,outgoing,friends,transfers }; break;
      }
      case 'sharePoints': {
        requireStudent(profile);
        const targetUid = clean(body.targetUid,160), amount = Number(body.amount);
        if (!targetUid || targetUid === uid || !Number.isInteger(amount) || amount < 20 || amount > 100) throw new ApiError(400,'invalid-argument','20–100 arasında tam sayı puan seç.');
        const { data, error } = await service.rpc('education_share_points',{ p_sender_id:uid,p_target_id:targetUid,p_amount:amount });
        if (error) throw new ApiError(400,error.code || 'share_failed',error.message || 'Puan paylaşılamadı.');
        output = { success:true,amount,senderPoints:Number(data?.senderPoints ?? data?.sender_points ?? 0),receiverPoints:Number(data?.receiverPoints ?? data?.receiver_points ?? 0) }; break;
      }
      case 'markStudentNotificationsRead': {
        requireStudent(profile);
        const rows = (await safeRows('notifications')).filter((r) => r.data.userId === uid && r.data.read !== true).slice(0,100);
        for (const row of rows) await writeRecord('notifications',row.id,{ ...row.data,read:true,readAt:timestamp() });
        output = { success:true,updated:rows.length }; break;
      }
      case 'deleteSelf': {
        // Cleanup is used only if Education registration fails. Protect accounts already linked to Aura X.
        const { data: linked, error: linkedError } = await service.from('users').select('id').filter('data->>authUid','eq',uid).limit(1);
        if (linkedError) throw new ApiError(500,linkedError.code || 'database_error','Aura X bağlantısı doğrulanamadı; hesap güvenli biçimde silinmedi.');
        if (linked?.length) throw new ApiError(409,'account-linked','Bu kimlik Aura X hesabına bağlı; ortak hesap otomatik silinmedi.');
        const profile = await getRecord('users',uid);
        const usernameLower = clean(profile?.data?.usernameLower || profile?.data?.username || '',40).toLowerCase();
        if (usernameLower) {
          const claim = await getRecord('usernameClaims',usernameLower);
          const expectedHash = Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(uid)))).map((b) => b.toString(16).padStart(2,'0')).join('');
          if (claim?.data?.ownerUidHash === expectedHash) await deleteRecord('usernameClaims',usernameLower);
        }
        await deleteRecord('users',uid);
        const { error } = await service.auth.admin.deleteUser(uid);
        if (error) throw new ApiError(500,error.code || 'delete_failed','Hesap temizlenemedi.');
        output = { success:true }; break;
      }
      default:
        throw new ApiError(404,'unsupported-action',`Eğitim işlemi tanınmıyor: ${action || '(boş)'}`);
    }

    return json({ data: output });
  } catch (error) {
    const api = error instanceof ApiError ? error : new ApiError(500, (error as any)?.code || 'internal', (error as any)?.message || 'Beklenmeyen sunucu hatası.');
    console.error('education-actions:', api.code, api.message);
    return json({ error: { code: api.code, message: api.message } }, api.status);
  }
});
