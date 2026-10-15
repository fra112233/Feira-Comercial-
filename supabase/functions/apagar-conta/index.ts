// Feira Comercial — apagar a minha conta (definitivo).
//
// POST {confirmar: "APAGAR", senha: "..."} com a sessão do utilizador (Authorization: Bearer <token>).
// Por segurança confirma a palavra-passe aqui no servidor (uma sessão roubada não chega),
// e não apaga contas da equipa.
// Apaga as fotos/vídeos da pessoa e depois a conta; a base de dados apaga o resto em
// cadeia (publicações, mensagens, gostos…). Os pagamentos ficam (migração 026).
import { createClient } from "jsr:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (d: unknown, s = 200) =>
  new Response(JSON.stringify(d), { status: s, headers: { ...cors, "Content-Type": "application/json" } });

const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false },
});
const BALDES = ["avatars", "media", "ads_media", "videos", "chat-media"];

// confirma a palavra-passe sem tocar na sessão do utilizador
async function senhaCerta(email: string, senha: string) {
  if (!email || !senha) return false;
  const anon = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await anon.auth.signInWithPassword({ email, password: senha });
  if (error || !data.session) return false;
  await anon.auth.signOut({ scope: "local" }).catch(() => {});
  return true;
}

async function apagarPasta(balde: string, uid: string) {
  for (let i = 0; i < 50; i++) {
    const { data, error } = await sb.storage.from(balde).list(uid, { limit: 1000 });
    if (error || !data || !data.length) return;
    const caminhos = data.filter((f) => f.name).map((f) => uid + "/" + f.name);
    if (!caminhos.length) return;
    await sb.storage.from(balde).remove(caminhos);
    if (data.length < 1000) return;
  }
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });
  if (req.method !== "POST") return json({ erro: "método" }, 405);
  try {
    const jwt = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
    const { data: { user }, error } = await sb.auth.getUser(jwt);
    if (error || !user) return json({ erro: "Sessão inválida. Entre outra vez." }, 401);

    const corpo = await req.json().catch(() => ({}));
    if (corpo.confirmar !== "APAGAR") return json({ erro: "Falta a confirmação." }, 400);

    if (!(await senhaCerta(user.email || "", String(corpo.senha || "")))) {
      return json({ erro: "A palavra-passe não está certa." }, 403);
    }

    // sem a migração 026 os pagamentos seriam apagados em cadeia: não avançar
    const { error: e026 } = await sb.from("pagamentos").select("empresa_nome").limit(0);
    if (e026) return json({ erro: "Esta opção ainda não está disponível. Fale com a equipa." }, 503);

    const { data: perfil } = await sb.from("perfis").select("role").eq("id", user.id).maybeSingle();
    if (perfil && (perfil.role === "admin" || perfil.role === "equipa")) {
      return json({ erro: "Contas da equipa não podem ser apagadas aqui." }, 403);
    }

    for (const b of BALDES) { try { await apagarPasta(b, user.id); } catch (e) { console.warn("pasta", b, String(e)); } }
    const { error: e2 } = await sb.auth.admin.deleteUser(user.id);
    if (e2) throw e2;
    return json({ ok: true });
  } catch (e) {
    console.error(e);
    return json({ erro: "Não foi possível apagar a conta. Tente outra vez mais tarde." }, 500);
  }
});
