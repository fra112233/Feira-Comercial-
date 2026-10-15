// Feira Comercial — notificações push (mensagens novas e atividade do sino 🔔).
//
// GET                 → devolve a chave pública (o navegador precisa dela para se registar).
//                       Na primeira chamada cria as chaves VAPID e guarda-as em push_segredo.
// POST {mensagem: id} → chamado pela base de dados quando chega uma mensagem nova
//                       (com o cabeçalho x-push-token); envia o aviso a todos os
//                       aparelhos do destinatário e apaga os que já não existem.
// POST {notificacao: id} → chamado quando há um aviso novo no sino (gosto, comentário,
//                       seguidor, publicação/vídeo/Live de quem segue).
import * as webpush from "jsr:@negrel/webpush@0.5.0";
import { createClient } from "jsr:@supabase/supabase-js@2";

const CONTACTO = "mailto:suporte@feira-comercial.com";
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};
const json = (d: unknown, s = 200) =>
  new Response(JSON.stringify(d), { status: s, headers: { ...cors, "Content-Type": "application/json" } });

const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false },
});

let cache: { token: string; chaves: CryptoKeyPair; publica: string; servidor: webpush.ApplicationServer } | null = null;

async function carregar() {
  if (cache) return cache;
  let { data: seg, error } = await sb.from("push_segredo").select("token, vapid").eq("id", 1).maybeSingle();
  if (error || !seg) throw new Error("push_segredo em falta: " + (error?.message ?? "corra a migração 015"));
  if (!seg.vapid) {
    // primeira vez: criar as chaves (só grava se ainda ninguém gravou)
    const novas = await webpush.generateVapidKeys({ extractable: true });
    const exportadas = await webpush.exportVapidKeys(novas);
    await sb.from("push_segredo").update({ vapid: exportadas }).eq("id", 1).is("vapid", null);
    ({ data: seg } = await sb.from("push_segredo").select("token, vapid").eq("id", 1).maybeSingle());
  }
  const chaves = await webpush.importVapidKeys(seg!.vapid, { extractable: false });
  const publica = await webpush.exportApplicationServerKey(chaves);
  const servidor = await webpush.ApplicationServer.new({ contactInformation: CONTACTO, vapidKeys: chaves });
  cache = { token: seg!.token, chaves, publica, servidor };
  return cache;
}

function resumo(m: { content: string | null; media_type: string | null; file_url: string | null }) {
  const t = (m.content || "").trim();
  if (t) return t.length > 110 ? t.slice(0, 107) + "…" : t;
  const tipo = (m.media_type || "").toLowerCase();
  if (tipo.startsWith("image")) return "📷 Foto";
  if (tipo.startsWith("video")) return "🎥 Vídeo";
  if (tipo.startsWith("audio")) return "🎤 Mensagem de voz";
  if (m.file_url) return "📎 Ficheiro";
  return "Nova mensagem";
}

const TEXTOS: Record<string, string> = {
  gosto: "gostou da sua publicação",
  comentario: "comentou a sua publicação",
  resposta: "respondeu ao seu comentário",
  seguir: "começou a segui-lo",
  publicacao: "fez uma publicação nova",
  video: "publicou um vídeo novo",
  gosto_video: "gostou do seu vídeo",
  comentario_video: "comentou o seu vídeo",
  live: "está em direto agora 🔴",
};

type Sub = { id: number; endpoint: string; p256dh: string; auth: string };
type Cfg = Awaited<ReturnType<typeof carregar>>;

async function enviar(cfg: Cfg, subs: Sub[], aviso: string) {
  let enviados = 0;
  const mortos: number[] = [];
  await Promise.all(subs.map(async (s) => {
    try {
      const sub = cfg.servidor.subscribe({ endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } });
      await sub.pushTextMessage(aviso, { urgency: webpush.Urgency.High, ttl: 86400 });
      enviados++;
    } catch (e) {
      if (e instanceof webpush.PushMessageError && (e.isGone() || e.response.status === 404)) mortos.push(s.id);
      else console.warn("push falhou", String(e));
    }
  }));
  if (mortos.length) await sb.from("push_subscricoes").delete().in("id", mortos);
  return { enviados, removidos: mortos.length };
}

async function avisoAtividade(cfg: Cfg, id: number) {
  const { data: n } = await sb.from("notificacoes")
    .select("id, user_id, autor_id, tipo, post_id, video_id, live_id, texto, lida")
    .eq("id", id).maybeSingle();
  if (!n || n.lida) return json({ ok: true, ignorado: "sem aviso" });
  const [{ data: subs }, { data: autor }, { count }] = await Promise.all([
    sb.from("push_subscricoes").select("id, endpoint, p256dh, auth").eq("user_id", n.user_id),
    sb.from("perfis").select("full_name, avatar_url").eq("id", n.autor_id).maybeSingle(),
    sb.from("notificacoes").select("id", { count: "exact", head: true }).eq("user_id", n.user_id).eq("lida", false),
  ]);
  if (!subs || !subs.length) return json({ ok: true, enviados: 0 });
  const nome = autor?.full_name || "Alguém";
  const url = n.post_id ? "/index.html?post=" + n.post_id
    : n.video_id ? "/videos.html?v=" + n.video_id
    : n.live_id ? "/live.html?id=" + n.live_id
    : "/perfil.html?id=" + n.autor_id;
  const extra = (n.texto || "").trim();
  const aviso = JSON.stringify({
    title: nome + " " + (TEXTOS[n.tipo] || ""),
    body: extra ? (extra.length > 110 ? extra.slice(0, 107) + "…" : extra) : "Toque para ver.",
    icon: autor?.avatar_url || "/images/icone-192.png",
    // gostos na mesma publicação substituem-se uns aos outros (não enchem o telemóvel)
    tag: n.tipo + "-" + (n.post_id ?? n.video_id ?? n.live_id ?? n.autor_id),
    url,
    count: count ?? 1,
  });
  return json({ ok: true, ...(await enviar(cfg, subs as Sub[], aviso)) });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });
  try {
    const cfg = await carregar();

    if (req.method === "GET") return json({ chave: cfg.publica });

    if (req.method !== "POST") return json({ erro: "método" }, 405);
    if (req.headers.get("x-push-token") !== cfg.token) return json({ erro: "não autorizado" }, 401);

    const corpo = await req.json();
    if (corpo.notificacao) return await avisoAtividade(cfg, corpo.notificacao);
    const { mensagem } = corpo;
    const { data: m } = await sb.from("messages")
      .select("id, sender_id, receiver_id, content, media_type, file_url, deleted")
      .eq("id", mensagem).maybeSingle();
    if (!m || m.deleted) return json({ ok: true, ignorado: "sem mensagem" });

    const [{ data: subs }, { data: autor }, { count }] = await Promise.all([
      sb.from("push_subscricoes").select("id, endpoint, p256dh, auth").eq("user_id", m.receiver_id),
      sb.from("perfis").select("full_name, avatar_url").eq("id", m.sender_id).maybeSingle(),
      sb.from("messages").select("id", { count: "exact", head: true })
        .eq("receiver_id", m.receiver_id).is("read_at", null).eq("deleted", false).eq("cleared_by_receiver", false),
    ]);
    if (!subs || !subs.length) return json({ ok: true, enviados: 0 });

    const aviso = JSON.stringify({
      title: autor?.full_name || "Feira Comercial",
      body: resumo(m),
      icon: autor?.avatar_url || "/images/icone-192.png",
      tag: "msg-" + m.sender_id,
      url: "/mensagen.html?para=" + m.sender_id,
      count: count ?? 1,
    });

    return json({ ok: true, ...(await enviar(cfg, subs as Sub[], aviso)) });
  } catch (e) {
    console.error(e);
    return json({ ok: false, erro: String(e) }, 500);
  }
});
