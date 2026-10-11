// Feira Comercial — limpeza automática de conteúdo expirado.
//
// As publicações aparecem no feed durante 4 dias, mas as suas fotos e vídeos
// ficam guardados para sempre no separador "Média" do perfil (histórico).
// Por isso esta função NÃO apaga publicações nem os ficheiros delas.
// Apaga apenas:
//   • stories com mais de 60 horas (visíveis 48 h);
//   • ficheiros do espaço "media" com mais de 60 h que nenhuma publicação
//     (de qualquer data) nem story recente usa — stories expirados, publicações
//     apagadas pelo dono e envios falhados que ficaram perdidos.
// Não toca em fotos de perfil, anúncios, vídeos da página Vídeos, chat nem comprovativos.
//
// ?simular=1 → mostra o que seria apagado, sem apagar nada.
// Corre no máximo uma vez por hora (chamadas a mais são ignoradas).
import { createClient } from "jsr:@supabase/supabase-js@2";

const HORAS_STORY = 60;      // stories: visíveis 48 h → apagados às 60 h
const BALDE = "media";

const json = (dados: unknown, estado = 200) =>
  new Response(JSON.stringify(dados), { status: estado, headers: { "Content-Type": "application/json" } });

function caminhoDe(url: unknown): string | null {
  const m = String(url ?? "").match(/\/object\/public\/media\/([^?#]+)/);
  return m ? decodeURIComponent(m[1]) : null;
}

Deno.serve(async (req: Request) => {
  const simular = new URL(req.url).searchParams.get("simular") === "1";
  const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false },
  });

  // no máximo uma limpeza real por hora
  if (!simular) {
    const { data: ult } = await sb.from("config").select("valor").eq("chave", "limpeza_ultima").maybeSingle();
    if (ult?.valor && Date.now() - Date.parse(ult.valor) < 55 * 60 * 1000) {
      return json({ ok: true, ignorado: "já correu há menos de 1 hora", ultima: ult.valor });
    }
  }

  const limiteStory = new Date(Date.now() - HORAS_STORY * 3600 * 1000).toISOString();

  // 1) ficheiros que ainda são usados (nunca apagar):
  //    todas as publicações (histórico de Média) + stories recentes
  const usar = new Set<string>();
  for (let de = 0; ; de += 1000) {
    const { data, error } = await sb.from("posts").select("media,image_url").order("id").range(de, de + 999);
    if (error) return json({ ok: false, erro: error.message }, 500);
    for (const p of data ?? []) {
      for (const m of (Array.isArray(p.media) ? p.media : [])) { const c = caminhoDe(m?.url); if (c) usar.add(c); }
      const c = caminhoDe(p.image_url); if (c) usar.add(c);
    }
    if (!data || data.length < 1000) break;
  }
  const { data: storiesRecentes, error: e2 } = await sb.from("stories").select("media_url").gte("created_at", limiteStory);
  if (e2) return json({ ok: false, erro: e2.message }, 500);
  for (const s of storiesRecentes ?? []) { const c = caminhoDe(s.media_url); if (c) usar.add(c); }

  // 2) ficheiros antigos do espaço "media" que já ninguém usa
  const apagar: string[] = [];
  let bytes = 0;
  const { data: pastas, error: e3 } = await sb.storage.from(BALDE).list("", { limit: 1000 });
  if (e3) return json({ ok: false, erro: e3.message }, 500);
  for (const pasta of pastas ?? []) {
    if (pasta.id) continue;                       // é ficheiro solto na raiz, não pasta
    let offset = 0;
    for (;;) {
      const { data: fich, error } = await sb.storage.from(BALDE).list(pasta.name, { limit: 1000, offset });
      if (error) return json({ ok: false, erro: error.message }, 500);
      for (const f of fich ?? []) {
        if (!f.id) continue;
        const caminho = `${pasta.name}/${f.name}`;
        const criado = f.created_at ? Date.parse(f.created_at) : Date.now();
        if (criado < Date.parse(limiteStory) && !usar.has(caminho)) {
          apagar.push(caminho);
          bytes += Number(f.metadata?.size ?? 0);
        }
      }
      if (!fich || fich.length < 1000) break;
      offset += 1000;
    }
  }

  // 3) stories antigos
  const { count: nStories } = await sb.from("stories").select("id", { count: "exact", head: true }).lt("created_at", limiteStory);

  const resumo = {
    ok: true, simulacao: simular, limiteStories: limiteStory,
    ficheiros: apagar.length, mb: Math.round(bytes / 1048576 * 10) / 10,
    publicacoes: 0, stories: nStories ?? 0,
  };
  if (simular) return json({ ...resumo, exemplos: apagar.slice(0, 10) });

  // apagar ficheiros em blocos
  for (let i = 0; i < apagar.length; i += 100) {
    const { error } = await sb.storage.from(BALDE).remove(apagar.slice(i, i + 100));
    if (error) return json({ ...resumo, ok: false, erro: "ficheiros: " + error.message }, 500);
  }
  const { error: e5 } = await sb.from("stories").delete().lt("created_at", limiteStory);
  if (e5) return json({ ...resumo, ok: false, erro: e5.message }, 500);

  await sb.from("config").upsert({ chave: "limpeza_ultima", valor: new Date().toISOString(), descricao: "Última limpeza automática de conteúdo expirado" });
  return json(resumo);
});
