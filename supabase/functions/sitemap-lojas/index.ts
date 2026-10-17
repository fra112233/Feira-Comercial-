// Feira Comercial — mapa do site com as montras públicas das empresas (para o Google).
// Servido em https://www.feira-comercial.com/sitemap-lojas.xml (o vercel.json reencaminha para aqui).
// Só leitura. Só lista empresas visíveis e não suspensas — as mesmas que a montra pública mostra.
import { createClient } from "jsr:@supabase/supabase-js@2";

const SITE = "https://www.feira-comercial.com";
const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false },
});
const dia = (d: string | null) => (d ? new Date(d).toISOString().slice(0, 10) : null);

Deno.serve(async () => {
  try {
    const [{ data: empresas, error }, { data: posts }] = await Promise.all([
      sb.from("perfis").select("id, created_at, bloqueado, visibility").eq("type", "empresa").limit(45000),
      sb.from("posts").select("user_id, created_at").order("created_at", { ascending: false }).limit(5000),
    ]);
    if (error) throw error;
    const ultima: Record<string, string> = {};
    (posts || []).forEach((p) => { if (!ultima[p.user_id]) ultima[p.user_id] = p.created_at; });
    const urls = (empresas || [])
      .filter((e) => !e.bloqueado && (e.visibility || "publico") === "publico")
      .map((e) => {
        const mod = dia(ultima[e.id] || e.created_at);
        return `  <url><loc>${SITE}/loja.html?id=${e.id}</loc>${mod ? `<lastmod>${mod}</lastmod>` : ""}<changefreq>weekly</changefreq><priority>0.7</priority></url>`;
      });
    const xml = `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${urls.join("\n")}\n</urlset>\n`;
    return new Response(xml, {
      headers: { "Content-Type": "application/xml; charset=utf-8", "Cache-Control": "public, max-age=3600" },
    });
  } catch (e) {
    console.error(e);
    return new Response(`<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"></urlset>\n`, {
      status: 503, headers: { "Content-Type": "application/xml; charset=utf-8", "Cache-Control": "no-store", "Retry-After": "600" },
    });
  }
});
