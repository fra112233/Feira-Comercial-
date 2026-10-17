// Feira Comercial — link bonito de uma loja: www.feira-comercial.com/loja/<id>
// O WhatsApp, o Facebook e o Telegram não correm JavaScript: leem só as etiquetas "og:" desta página.
// Por isso aqui mostramos o logótipo, o nome e o setor da empresa — e quem abre o link
// é levado logo para a montra pública (loja.html). Só dados públicos da montra (sem contactos).
const SUPABASE_URL = 'https://bljnkwrhqnpawclybqrw.supabase.co';
const CHAVE_PUBLICA = 'sb_publishable_qvUvtBjpAKtMevafHRJe8g_W-aUkOb0';
const SITE = 'https://www.feira-comercial.com';
const esc = s => String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

module.exports = async (req, res) => {
  const id = String((req.query && req.query.id) || '').toLowerCase();
  const valido = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(id);
  const destino = valido ? SITE + '/loja.html?id=' + id : SITE + '/';
  let m = null;
  if (valido) {
    try {
      const r = await fetch(SUPABASE_URL + '/rest/v1/rpc/montra_publica', {
        method: 'POST',
        headers: { apikey: CHAVE_PUBLICA, Authorization: 'Bearer ' + CHAVE_PUBLICA, 'Content-Type': 'application/json' },
        body: JSON.stringify({ pid: id }),
      });
      if (r.ok) m = await r.json();
    } catch (e) {}
  }
  const nome = (m && m.nome) || 'Feira Comercial';
  const titulo = m ? nome + ' | Feira Comercial' : 'Feira Comercial';
  const partes = m ? [m.setor, [m.cidade, m.provincia].filter(Boolean).join(', ')].filter(Boolean).join(' · ') : '';
  const estrelas = m && m.avaliacao && m.avaliacao.total > 0 ? ' ⭐ ' + String(m.avaliacao.media).replace('.', ',') + ' (' + m.avaliacao.total + ')' : '';
  const nProd = m && Array.isArray(m.produtos) ? m.produtos.length : 0;
  const descricao = m
    ? (partes ? partes + estrelas + ' — ' : '') + (nProd ? nProd + (nProd === 1 ? ' produto' : ' produtos') + ' com preço. ' : '') + 'Veja a montra e fale com a loja na Feira Comercial.'
    : 'A rede social de pessoas e empresas que chegou a Moçambique.';
  const imagem = m && /^https:\/\//.test(m.logo || '') ? m.logo : SITE + '/images/partilha.png';

  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  res.setHeader('Cache-Control', 'public, s-maxage=600, stale-while-revalidate=3600');
  res.status(m || !valido ? 200 : 404).send(`<!doctype html><html lang="pt"><head><meta charset="utf-8">
<title>${esc(titulo)}</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="description" content="${esc(descricao)}">
<link rel="canonical" href="${esc(destino)}">
<meta property="og:type" content="website">
<meta property="og:site_name" content="Feira Comercial">
<meta property="og:title" content="${esc(titulo)}">
<meta property="og:description" content="${esc(descricao)}">
<meta property="og:image" content="${esc(imagem)}">
<meta property="og:url" content="${esc(SITE + '/loja/' + (valido ? id : ''))}">
<meta property="og:locale" content="pt_PT">
<meta name="twitter:card" content="summary">
<meta http-equiv="refresh" content="0;url=${esc(destino)}">
<style>body{background:#0b0b0d;color:#f4f4f5;font-family:system-ui,sans-serif;display:flex;align-items:center;justify-content:center;min-height:100vh;margin:0;text-align:center}a{color:#f3c64e}</style>
</head><body><p>A abrir <a href="${esc(destino)}">${esc(nome)}</a>…</p>
<script>location.replace(${JSON.stringify(destino)});</script></body></html>`);
};
