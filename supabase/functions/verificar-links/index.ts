// Feira Comercial — verificação de links perigosos (Google Web Risk).
//
// Chamada pela base de dados (pg_net) quando alguém envia uma mensagem ou publica
// um anúncio com um link. Pergunta à Google se o link é de burla (phishing),
// vírus ou programas indesejados:
//   • mensagem com link perigoso → fica marcada (alerta = 'link_perigoso') e quem a
//     recebe vê um aviso vermelho no chat;
//   • anúncio com link perigoso → fica escondido para revisão da Equipa e a empresa
//     recebe um aviso no sino.
// Cada link é perguntado à Google no máximo uma vez por dia (tabela links_verificados).
// Sem a chave WEB_RISK_KEY (Supabase → Edge Functions → Secrets) não faz nada.
// Só aceita pedidos com o cabeçalho x-links-token (o mesmo segredo dos avisos push).
import { createClient } from "jsr:@supabase/supabase-js@2";

const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false },
});
const CHAVE = Deno.env.get("WEB_RISK_KEY") ?? "";
const MAX_LINKS = 5;
const UM_DIA = 24 * 3600 * 1000;

const json = (dados: unknown, estado = 200) =>
  new Response(JSON.stringify(dados), { status: estado, headers: { "Content-Type": "application/json" } });

// links do texto (http(s)://… e www.…), sem os da própria Feira Comercial
function linksEm(texto: string): string[] {
  const achados = String(texto ?? "").match(/\bhttps?:\/\/[^\s<>"']+|\bwww\.[^\s<>"']+/gi) ?? [];
  const fora = /(^|\.)(feira-comercial\.com|supabase\.co)$/i;
  const lista: string[] = [];
  for (let l of achados) {
    l = l.replace(/[.,;:!?)\]}»]+$/, "");
    if (!/^https?:\/\//i.test(l)) l = "http://" + l;
    try {
      const u = new URL(l);
      if (fora.test(u.hostname)) continue;
      const n = u.toString();
      if (!lista.includes(n)) lista.push(n);
    } catch { /* não é um link válido */ }
    if (lista.length >= MAX_LINKS) break;
  }
  return lista;
}

// devolve o tipo de ameaça (ou null se o link é seguro)
async function ameacaDe(url: string): Promise<string | null> {
  const { data: c } = await sb.from("links_verificados").select("ameaca, verificado").eq("url", url).maybeSingle();
  if (c && Date.now() - Date.parse(c.verificado) < UM_DIA) return c.ameaca;
  const q = new URLSearchParams({ uri: url, key: CHAVE });
  for (const t of ["MALWARE", "SOCIAL_ENGINEERING", "UNWANTED_SOFTWARE"]) q.append("threatTypes", t);
  const r = await fetch("https://webrisk.googleapis.com/v1/uris:search?" + q.toString());
  if (!r.ok) throw new Error("Web Risk " + r.status + ": " + (await r.text()).slice(0, 200));
  const d = await r.json();
  const ameaca: string | null = d?.threat?.threatTypes?.[0] ?? null;
  await sb.from("links_verificados").upsert({ url, ameaca, verificado: new Date().toISOString() });
  return ameaca;
}

async function perigosos(texto: string) {
  const res: { url: string; ameaca: string }[] = [];
  for (const url of linksEm(texto)) {
    const a = await ameacaDe(url);
    if (a) res.push({ url, ameaca: a });
  }
  return res;
}

Deno.serve(async (req: Request) => {
  const { data: seg } = await sb.from("push_segredo").select("token").eq("id", 1).maybeSingle();
  if (!seg?.token || req.headers.get("x-links-token") !== seg.token) return json({ erro: "não autorizado" }, 401);
  if (!CHAVE) return json({ ok: true, ativo: false, motivo: "falta a chave WEB_RISK_KEY" });

  let corpo: { mensagem?: number; anuncio?: string; testar?: string } = {};
  try { corpo = await req.json(); } catch { /* corpo vazio */ }

  try {
    // teste manual: {"testar": "https://..."}
    if (corpo.testar) return json({ ok: true, ativo: true, links: linksEm(corpo.testar), perigosos: await perigosos(corpo.testar) });

    if (corpo.mensagem) {
      const { data: m } = await sb.from("messages").select("id, content, alerta, deleted").eq("id", corpo.mensagem).maybeSingle();
      if (!m || m.deleted) return json({ ok: true, ignorado: "mensagem não existe" });
      const p = await perigosos(m.content);
      if (p.length && !m.alerta) await sb.from("messages").update({ alerta: "link_perigoso" }).eq("id", m.id).is("alerta", null);
      return json({ ok: true, ativo: true, perigosos: p });
    }

    if (corpo.anuncio) {
      const { data: a } = await sb.from("vagas_anuncios").select("id, empresa_id, titulo, descricao, link, em_revisao").eq("id", corpo.anuncio).maybeSingle();
      if (!a) return json({ ok: true, ignorado: "anúncio não existe" });
      // o campo "link" pode vir sem http:// (ex.: loja.co.mz)
      const link = String(a.link ?? "").trim();
      const linkUrl = link && !/^(https?:\/\/|www\.)/i.test(link) && /^[^\s]+\.[a-z]{2,}(\/\S*)?$/i.test(link) ? "http://" + link : link;
      const p = await perigosos([linkUrl, a.titulo, a.descricao].filter(Boolean).join(" "));
      if (p.length && !a.em_revisao) {
        await sb.from("vagas_anuncios").update({ em_revisao: true }).eq("id", a.id);
        await sb.from("notificacoes").insert({
          user_id: a.empresa_id, autor_id: a.empresa_id, tipo: "anuncio_revisao",
          texto: "Anúncio «" + String(a.titulo ?? "").slice(0, 60) + "»: link marcado como perigoso pela Google",
        });
      }
      return json({ ok: true, ativo: true, perigosos: p });
    }
    return json({ ok: false, erro: "pedido sem mensagem, anúncio ou teste" }, 400);
  } catch (e) {
    return json({ ok: false, erro: String((e as Error).message ?? e) }, 500);
  }
});
