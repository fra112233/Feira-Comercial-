/* ============================================================
   Feira Comercial — perfil-extra.js
   Separadores "Produtos" (catálogo com preço e encomenda por WhatsApp)
   e "Avaliações" (estrelas de clientes) no perfil das empresas.
   Usa as variáveis do perfil.html: perfilAtual, modoVisita, meuId, alvoId.
   ============================================================ */
window.FCX = (function () {
  const esc = s => String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  const mt = v => v == null || v === '' ? '' : String(Math.round(Number(v))).replace(/\B(?=(\d{3})+(?!\d))/g, ' ') + ' MT';
  const sb = () => (typeof supabaseClient !== 'undefined' ? supabaseClient : window.supabaseClient);
  let empresa = null, dono = false, produtos = [], avaliacoes = [], temProdutos = true, temAvaliacoes = true;
  let produtosLidos = false, avaliacoesLidas = false;

  const css = document.createElement('style');
  css.textContent = `
    .fcx-estrelas{color:#f59e0b;letter-spacing:1px;white-space:nowrap}
    .fcx-estrelas .vazia{color:var(--bg-hover,#475569)}
    .fcx-rating{display:inline-flex;align-items:center;gap:6px;margin:6px 0 0;padding:4px 12px;border-radius:999px;background:rgba(245,158,11,.12);font-size:13px;font-weight:700;cursor:pointer;border:none;color:var(--text-primary);font-family:inherit}
    .fcx-topo{display:flex;align-items:center;justify-content:space-between;gap:10px;margin-bottom:14px;flex-wrap:wrap}
    .fcx-topo h3{font-size:17px;margin:0}
    .fcx-grelha{display:grid;grid-template-columns:repeat(auto-fill,minmax(min(170px,100%),1fr));gap:12px}
    .fcx-prod{background:var(--bg-secondary);border:1px solid var(--border-color);border-radius:var(--radius-lg,14px);overflow:hidden;display:flex;flex-direction:column}
    .fcx-prod.oculto{opacity:.55}
    .fcx-prod .foto{aspect-ratio:1;background:var(--bg-tertiary);display:flex;align-items:center;justify-content:center;color:var(--text-tertiary);font-size:30px}
    .fcx-prod .foto img{width:100%;height:100%;object-fit:cover;display:block}
    .fcx-prod .info{padding:10px 12px;flex:1;display:flex;flex-direction:column;gap:4px}
    .fcx-prod .nome{font-weight:700;font-size:14px;line-height:1.3}
    .fcx-prod .preco{font-weight:800;color:var(--success,#10b981);font-size:15px}
    .fcx-prod .desc{font-size:12.5px;color:var(--text-secondary);line-height:1.4;display:-webkit-box;-webkit-line-clamp:3;-webkit-box-orient:vertical;overflow:hidden}
    .fcx-prod .acoes{display:flex;gap:6px;padding:0 12px 12px;flex-wrap:wrap}
    .fcx-prod .acoes a,.fcx-prod .acoes button{flex:1;display:inline-flex;align-items:center;justify-content:center;gap:5px;padding:8px;border-radius:var(--radius-md,10px);font-weight:600;font-size:12.5px;font-family:inherit;text-decoration:none;cursor:pointer;border:1px solid var(--border-color);background:var(--bg-tertiary);color:var(--text-primary);white-space:nowrap}
    .fcx-prod .acoes .wa{background:#25d366;border-color:#25d366;color:#fff}
    .fcx-vazio{text-align:center;color:var(--text-secondary);padding:36px 16px;font-size:14px;line-height:1.5}
    .fcx-vazio i{font-size:36px;opacity:.35;display:block;margin-bottom:10px}
    .fcx-btn{display:inline-flex;align-items:center;gap:6px;padding:9px 14px;border-radius:var(--radius-md,10px);border:none;background:var(--primary);color:#fff;font-weight:700;font-size:13.5px;font-family:inherit;cursor:pointer}
    .fcx-btn.sec{background:var(--bg-tertiary);color:var(--text-primary)}
    .fcx-campo{margin-bottom:12px}.fcx-campo label{display:block;font-size:13px;font-weight:700;margin-bottom:5px;color:var(--text-secondary)}
    .fcx-campo input,.fcx-campo textarea{width:100%;box-sizing:border-box;padding:10px 12px;border-radius:var(--radius-md,10px);border:1px solid var(--border-color);background:var(--bg-primary);color:var(--text-primary);font:inherit;font-size:14px}
    .fcx-foto-prev{width:96px;height:96px;border-radius:12px;object-fit:cover;background:var(--bg-tertiary);display:block;margin-bottom:8px}
    .fcx-resumo{display:grid;grid-template-columns:auto minmax(0,1fr);gap:18px;align-items:center;background:var(--bg-secondary);border:1px solid var(--border-color);border-radius:var(--radius-lg,14px);padding:16px;margin-bottom:14px}
    .fcx-resumo .media{text-align:center}.fcx-resumo .media b{font-size:38px;line-height:1;display:block}
    .fcx-barra{display:grid;grid-template-columns:16px minmax(0,1fr) 28px;gap:8px;align-items:center;font-size:12px;color:var(--text-secondary);margin:3px 0}
    .fcx-barra span.b{height:7px;border-radius:4px;background:var(--bg-tertiary);overflow:hidden}.fcx-barra span.b i{display:block;height:100%;background:#f59e0b}
    .fcx-form{background:var(--bg-secondary);border:1px solid var(--border-color);border-radius:var(--radius-lg,14px);padding:16px;margin-bottom:14px}
    .fcx-picker{display:flex;gap:4px;margin:6px 0 10px}.fcx-picker button{border:none;background:none;font-size:30px;line-height:1;cursor:pointer;color:var(--bg-hover,#475569);padding:0 2px}
    .fcx-picker button.on{color:#f59e0b}
    .fcx-av{display:flex;gap:12px;padding:14px 0;border-bottom:1px solid var(--border-color)}
    .fcx-av img{width:40px;height:40px;border-radius:50%;object-fit:cover;flex-shrink:0;background:var(--bg-tertiary)}
    .fcx-av .tx{flex:1;min-width:0;font-size:14px;line-height:1.45}.fcx-av .q{font-size:12px;color:var(--text-tertiary)}
    .fcx-av .resp{margin-top:8px;padding:8px 10px;border-left:3px solid var(--primary);background:var(--bg-tertiary);border-radius:0 8px 8px 0;font-size:13px}
    .fcx-av .lnk{border:none;background:none;color:var(--primary);font-weight:600;font-size:12.5px;font-family:inherit;cursor:pointer;padding:4px 0;margin-right:10px}
  `;
  document.head.appendChild(css);

  function estrelas(n, total = 5) {
    const c = Math.round(Number(n) || 0);
    return '<span class="fcx-estrelas">' + '★'.repeat(c) + '<span class="vazia">' + '★'.repeat(Math.max(0, total - c)) + '</span></span>';
  }

  // ---------- arranque (chamado quando o perfil carrega) ----------
  async function iniciar(p) {
    empresa = p; dono = !modoVisita;
    produtosLidos = avaliacoesLidas = false;
    const ehEmp = p && p.type === 'empresa';
    ['tabBtnProdutos', 'tabBtnAvaliacoes'].forEach(id => { const b = document.getElementById(id); if (b) b.style.display = ehEmp ? '' : 'none'; });
    const r = document.getElementById('fcxRating'); if (r) r.remove();
    if (!ehEmp) return;
    resumoNoTopo();
    if (location.hash === '#avaliacoes' || location.hash === '#produtos') {
      const tab = location.hash.slice(1);
      const btn = document.getElementById(tab === 'avaliacoes' ? 'tabBtnAvaliacoes' : 'tabBtnProdutos');
      if (btn && typeof switchTab === 'function') { switchTab(tab, btn); btn.scrollIntoView({ block: 'center', behavior: 'smooth' }); }
    }
  }

  async function resumoNoTopo() {
    const { data, error } = await sb().rpc('resumo_avaliacoes', { ids: [empresa.id] });
    if (error) { temAvaliacoes = false; const b = document.getElementById('tabBtnAvaliacoes'); if (b) b.style.display = 'none'; return; }
    const r = (data || [])[0];
    const alvo = document.getElementById('tipoBadge'); if (!alvo) return;
    const el = document.createElement('button');
    el.id = 'fcxRating'; el.type = 'button'; el.className = 'fcx-rating';
    el.innerHTML = r ? estrelas(r.media) + ' ' + String(r.media).replace('.', ',') + ' <span style="font-weight:500;color:var(--text-secondary)">(' + r.total + ' avaliaç' + (r.total == 1 ? 'ão' : 'ões') + ')</span>'
                     : '<span class="fcx-estrelas">☆</span> ' + (dono ? 'Ainda sem avaliações' : 'Seja o primeiro a avaliar');
    el.onclick = () => { const b = document.getElementById('tabBtnAvaliacoes'); if (b) { switchTab('avaliacoes', b); b.scrollIntoView({ block: 'center', behavior: 'smooth' }); } };
    alvo.after(el);
  }

  // ---------- PRODUTOS ----------
  async function carregarProdutos(forcar) {
    const box = document.getElementById('produtosLista'); if (!box || !empresa) return;
    if (produtosLidos && !forcar) return;
    box.innerHTML = '<div class="fcx-vazio">A carregar…</div>';
    const { data, error } = await sb().from('produtos').select('*').eq('user_id', empresa.id)
      .order('ordem', { ascending: true }).order('criado', { ascending: false }).limit(100);
    if (error) { temProdutos = false; box.innerHTML = '<div class="fcx-vazio">O catálogo ainda não está disponível.</div>'; return; }
    produtosLidos = true; produtos = data || [];
    desenharProdutos();
  }

  function desenharProdutos() {
    const box = document.getElementById('produtosLista');
    const wa = (window.FCP && FCP.numeroWhatsApp) ? FCP.numeroWhatsApp(empresa.whatsapp || empresa.phone) : '';
    const topo = '<div class="fcx-topo"><h3>' + (dono ? 'Os meus produtos' : 'Produtos') + ' <span style="color:var(--text-tertiary);font-weight:500;font-size:14px">(' + produtos.filter(p => p.disponivel || dono).length + ')</span></h3>' +
      (dono ? '<button class="fcx-btn" type="button" onclick="FCX.editarProduto()"><i class="fas fa-plus"></i> Adicionar produto</button>' : '') + '</div>';
    if (!produtos.length) {
      box.innerHTML = topo + '<div class="fcx-vazio"><i class="fas fa-box-open"></i>' +
        (dono ? 'Mostre os seus produtos com foto e preço.<br>Os clientes podem encomendar diretamente pelo WhatsApp.' : 'Esta empresa ainda não tem produtos no catálogo.') + '</div>';
      return;
    }
    box.innerHTML = topo + '<div class="fcx-grelha">' + produtos.map(p => {
      const foto = p.foto_url ? '<img src="' + FC.u(p.foto_url) + '" alt="" loading="lazy">' : '<i class="fas fa-box"></i>';
      const msg = encodeURIComponent('Olá! Vi na Feira Comercial e quero encomendar: ' + p.nome + (p.preco != null ? ' (' + mt(p.preco) + ')' : '') + '.');
      const acoes = dono
        ? '<button type="button" onclick="FCX.editarProduto(' + p.id + ')"><i class="fas fa-pen"></i> Editar</button>' +
          '<button type="button" onclick="FCX.alternarProduto(' + p.id + ')" title="' + (p.disponivel ? 'Esconder' : 'Mostrar') + '"><i class="fas fa-eye' + (p.disponivel ? '-slash' : '') + '"></i></button>' +
          '<button type="button" onclick="FCX.apagarProduto(' + p.id + ')" title="Apagar" style="color:var(--danger)"><i class="fas fa-trash"></i></button>'
        : (wa ? '<a class="wa" href="https://wa.me/' + wa + '?text=' + msg + '" target="_blank" rel="noopener" data-fc-evento="whatsapp" data-empresa="' + esc(empresa.id) + '" data-alvo="produto:' + p.id + '"><i class="fab fa-whatsapp"></i> Encomendar</a>' : '') +
          '<a href="mensagen.html?para=' + encodeURIComponent(empresa.id) + '"><i class="fas fa-comment-dots"></i>' + (wa ? '' : ' Mensagem') + '</a>';
      return '<div class="fcx-prod' + (p.disponivel ? '' : ' oculto') + '"><div class="foto">' + foto + '</div><div class="info">' +
        '<div class="nome">' + esc(p.nome) + (p.disponivel ? '' : ' <small style="color:var(--text-tertiary)">(escondido)</small>') + '</div>' +
        (p.preco != null ? '<div class="preco">' + mt(p.preco) + '</div>' : '<div class="preco" style="color:var(--text-tertiary);font-weight:600;font-size:13px">Preço sob consulta</div>') +
        (p.descricao ? '<div class="desc">' + esc(p.descricao) + '</div>' : '') + '</div><div class="acoes">' + acoes + '</div></div>';
    }).join('') + '</div>';
  }

  function editarProduto(id) {
    const p = produtos.find(x => x.id === id) || {};
    let m = document.getElementById('fcxModalProduto');
    if (!m) { m = document.createElement('div'); m.id = 'fcxModalProduto'; m.className = 'modal'; document.body.appendChild(m);
      m.addEventListener('click', e => { if (e.target === m) m.classList.remove('active'); }); }
    m.innerHTML = '<div class="modal-content" style="max-width:480px"><div class="modal-header"><h2 class="modal-title">' + (p.id ? 'Editar produto' : 'Novo produto') + '</h2>' +
      '<button class="modal-close" type="button" onclick="document.getElementById(\'fcxModalProduto\').classList.remove(\'active\')"><i class="fas fa-times"></i></button></div>' +
      '<div class="modal-body">' +
      '<div class="fcx-campo"><label>Foto</label><img class="fcx-foto-prev" id="fcxFotoPrev" src="' + (p.foto_url ? FC.u(p.foto_url) : 'data:,') + '" alt="" style="' + (p.foto_url ? '' : 'display:none') + '">' +
        '<input type="file" id="fcxFoto" accept="image/*"></div>' +
      '<div class="fcx-campo"><label for="fcxNome">Nome do produto</label><input id="fcxNome" maxlength="80" value="' + esc(p.nome || '') + '" placeholder="Ex.: Ténis Nike Air, tamanho 42"></div>' +
      '<div class="fcx-campo"><label for="fcxPreco">Preço (MT) — deixe vazio para "sob consulta"</label><input id="fcxPreco" type="number" inputmode="numeric" min="0" step="1" value="' + (p.preco != null ? Math.round(p.preco) : '') + '"></div>' +
      '<div class="fcx-campo"><label for="fcxDesc">Descrição (opcional)</label><textarea id="fcxDesc" rows="3" maxlength="500" placeholder="Tamanhos, cores, entrega…">' + esc(p.descricao || '') + '</textarea></div>' +
      '<button class="fcx-btn" type="button" id="fcxGuardar" style="width:100%;justify-content:center;padding:12px"><i class="fas fa-check"></i> Guardar</button>' +
      '</div></div>';
    m.classList.add('active');
    let ficheiro = null;
    m.querySelector('#fcxFoto').onchange = e => {
      ficheiro = e.target.files[0] || null;
      if (ficheiro && !ficheiro.type.startsWith('image/')) { alert('Escolha uma fotografia.'); ficheiro = null; e.target.value = ''; return; }
      const prev = m.querySelector('#fcxFotoPrev');
      if (ficheiro) { prev.src = URL.createObjectURL(ficheiro); prev.style.display = ''; }
    };
    m.querySelector('#fcxGuardar').onclick = async () => {
      const nome = m.querySelector('#fcxNome').value.trim();
      const precoTxt = m.querySelector('#fcxPreco').value.trim();
      if (!nome) { alert('Escreva o nome do produto.'); return; }
      const btn = m.querySelector('#fcxGuardar'); btn.disabled = true; btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> A guardar…';
      try {
        let foto = p.foto_url || null;
        if (ficheiro) {
          const r = await FCMedia.enviarMedia(sb(), meuId, ficheiro, { etiqueta: 'A otimizar a foto…' });
          foto = r.url;
        }
        const dados = { nome, preco: precoTxt === '' ? null : Number(precoTxt), descricao: m.querySelector('#fcxDesc').value.trim() || null, foto_url: foto };
        const { error } = p.id
          ? await sb().from('produtos').update(dados).eq('id', p.id)
          : await sb().from('produtos').insert(Object.assign({ user_id: meuId }, dados));
        if (error) throw error;
        m.classList.remove('active');
        if (typeof showToast === 'function') showToast(p.id ? 'Produto atualizado' : 'Produto adicionado ao catálogo');
        carregarProdutos(true);
      } catch (err) {
        alert('Não foi possível guardar: ' + (/row-level security/i.test(err.message || '') ? 'só empresas com a mensalidade em dia podem adicionar produtos.' : FC.traduzirErro(err)));
        btn.disabled = false; btn.innerHTML = '<i class="fas fa-check"></i> Guardar';
      }
    };
  }

  async function alternarProduto(id) {
    const p = produtos.find(x => x.id === id); if (!p) return;
    const { error } = await sb().from('produtos').update({ disponivel: !p.disponivel }).eq('id', id);
    if (error) { alert('Erro: ' + FC.traduzirErro(error)); return; }
    p.disponivel = !p.disponivel; desenharProdutos();
  }

  async function apagarProduto(id) {
    if (!confirm('Apagar este produto do catálogo?')) return;
    const { error } = await sb().from('produtos').delete().eq('id', id);
    if (error) { alert('Erro: ' + FC.traduzirErro(error)); return; }
    produtos = produtos.filter(x => x.id !== id); desenharProdutos();
  }

  // ---------- AVALIAÇÕES ----------
  let estrelasEscolhidas = 0;
  async function carregarAvaliacoes(forcar) {
    const box = document.getElementById('avaliacoesLista'); if (!box || !empresa) return;
    if (avaliacoesLidas && !forcar) return;
    box.innerHTML = '<div class="fcx-vazio">A carregar…</div>';
    const { data, error } = await sb().from('avaliacoes')
      .select('empresa_id, user_id, estrelas, comentario, resposta, criado, atualizado, autor:perfis!avaliacoes_user_id_fkey(full_name, avatar_url)')
      .eq('empresa_id', empresa.id).order('atualizado', { ascending: false }).limit(200);
    if (error) { box.innerHTML = '<div class="fcx-vazio">As avaliações ainda não estão disponíveis.</div>'; return; }
    avaliacoesLidas = true; avaliacoes = data || [];
    desenharAvaliacoes();
  }

  function desenharAvaliacoes() {
    const box = document.getElementById('avaliacoesLista');
    const total = avaliacoes.length;
    const media = total ? avaliacoes.reduce((s, a) => s + a.estrelas, 0) / total : 0;
    const minha = avaliacoes.find(a => a.user_id === meuId);
    let html = '';
    if (total) {
      html += '<div class="fcx-resumo"><div class="media"><b>' + media.toFixed(1).replace('.', ',') + '</b>' + estrelas(media) +
        '<div style="font-size:12px;color:var(--text-secondary);margin-top:4px">' + total + ' avaliaç' + (total === 1 ? 'ão' : 'ões') + '</div></div><div>' +
        [5, 4, 3, 2, 1].map(n => { const c = avaliacoes.filter(a => a.estrelas === n).length;
          return '<div class="fcx-barra"><span>' + n + '★</span><span class="b"><i style="width:' + (c / total * 100) + '%"></i></span><span>' + c + '</span></div>'; }).join('') +
        '</div></div>';
    }
    if (!dono && meuId && meuId !== empresa.id) {
      estrelasEscolhidas = minha ? minha.estrelas : 0;
      html += '<div class="fcx-form"><b style="font-size:15px">' + (minha ? 'A sua avaliação' : 'Avalie ' + esc(empresa.full_name || 'esta empresa')) + '</b>' +
        '<div class="fcx-picker" id="fcxPicker">' + [1, 2, 3, 4, 5].map(n => '<button type="button" data-n="' + n + '" aria-label="' + n + ' estrelas">★</button>').join('') + '</div>' +
        '<div class="fcx-campo" style="margin-bottom:10px"><textarea id="fcxComentario" rows="2" maxlength="500" placeholder="Conte como foi (opcional): atendimento, qualidade, entrega…">' + esc(minha ? minha.comentario || '' : '') + '</textarea></div>' +
        '<button class="fcx-btn" type="button" onclick="FCX.guardarAvaliacao()"><i class="fas fa-paper-plane"></i> ' + (minha ? 'Atualizar' : 'Publicar avaliação') + '</button>' +
        (minha ? ' <button class="fcx-btn sec" type="button" onclick="FCX.apagarAvaliacao()">Apagar</button>' : '') + '</div>';
    }
    if (!total) {
      html += '<div class="fcx-vazio"><i class="fas fa-star"></i>' + (dono ? 'Ainda não tem avaliações.<br>Peça aos seus clientes satisfeitos que o avaliem: dá confiança a quem ainda não o conhece.' : 'Ainda ninguém avaliou esta empresa.') + '</div>';
    } else {
      html += avaliacoes.map(a => {
        const autor = a.autor || {}, nome = autor.full_name || 'Cliente';
        const foto = autor.avatar_url || ('https://ui-avatars.com/api/?name=' + encodeURIComponent(nome) + '&background=random&color=fff&size=80');
        return '<div class="fcx-av"><img src="' + FC.u(foto) + '" alt="" loading="lazy"><div class="tx">' +
          '<b>' + esc(nome) + '</b> ' + estrelas(a.estrelas) + '<div class="q">' + (FC.haQuanto ? FC.haQuanto(a.atualizado) : '') + '</div>' +
          (a.comentario ? '<div style="margin-top:4px">' + esc(a.comentario) + '</div>' : '') +
          (a.resposta ? '<div class="resp"><b>Resposta da empresa:</b> ' + esc(a.resposta) + '</div>' : '') +
          (dono ? '<button class="lnk" type="button" onclick="FCX.responder(\'' + esc(a.user_id) + '\')">' + (a.resposta ? 'Editar resposta' : 'Responder') + '</button>' : '') +
          '</div></div>';
      }).join('');
    }
    box.innerHTML = html;
    const picker = document.getElementById('fcxPicker');
    if (picker) {
      const pintar = n => picker.querySelectorAll('button').forEach(b => b.classList.toggle('on', Number(b.dataset.n) <= n));
      pintar(estrelasEscolhidas);
      picker.querySelectorAll('button').forEach(b => {
        b.onclick = () => { estrelasEscolhidas = Number(b.dataset.n); pintar(estrelasEscolhidas); };
        b.onmouseenter = () => pintar(Number(b.dataset.n));
      });
      picker.onmouseleave = () => pintar(estrelasEscolhidas);
    }
  }

  async function guardarAvaliacao() {
    if (!estrelasEscolhidas) { alert('Escolha de 1 a 5 estrelas.'); return; }
    const comentario = (document.getElementById('fcxComentario').value || '').trim() || null;
    const ja = avaliacoes.find(a => a.user_id === meuId);
    const { error } = ja
      ? await sb().from('avaliacoes').update({ estrelas: estrelasEscolhidas, comentario }).eq('empresa_id', empresa.id).eq('user_id', meuId)
      : await sb().from('avaliacoes').insert({ empresa_id: empresa.id, user_id: meuId, estrelas: estrelasEscolhidas, comentario });
    if (error) { alert('Não foi possível guardar: ' + FC.traduzirErro(error)); return; }
    if (typeof showToast === 'function') showToast('Obrigado pela sua avaliação! ⭐');
    await carregarAvaliacoes(true);
    const r = document.getElementById('fcxRating'); if (r) r.remove(); resumoNoTopo();
  }

  async function apagarAvaliacao() {
    if (!confirm('Apagar a sua avaliação?')) return;
    const { error } = await sb().from('avaliacoes').delete().eq('empresa_id', empresa.id).eq('user_id', meuId);
    if (error) { alert('Erro: ' + FC.traduzirErro(error)); return; }
    await carregarAvaliacoes(true);
    const r = document.getElementById('fcxRating'); if (r) r.remove(); resumoNoTopo();
  }

  async function responder(userId) {
    const a = avaliacoes.find(x => x.user_id === userId); if (!a) return;
    const txt = prompt('Resposta pública a ' + ((a.autor && a.autor.full_name) || 'este cliente') + ':', a.resposta || '');
    if (txt === null) return;
    const { error } = await sb().from('avaliacoes').update({ resposta: txt.trim().slice(0, 500) || null }).eq('empresa_id', empresa.id).eq('user_id', userId);
    if (error) { alert('Erro: ' + FC.traduzirErro(error)); return; }
    carregarAvaliacoes(true);
  }

  return { iniciar, carregarProdutos, editarProduto, alternarProduto, apagarProduto,
           carregarAvaliacoes, guardarAvaliacao, apagarAvaliacao, responder, estrelas };
})();
