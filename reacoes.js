/* ============================================================
   Feira Comercial — reacoes.js
   "Quem reagiu": janela com a lista de pessoas que reagiram a uma publicação,
   com separadores por reação (Todas · 👍 · ❤️ · 😂 · 😢 · 😮).
   Quem publicou vê também o botão Mensagem ao lado de cada pessoa — para uma
   empresa, quem reage é um cliente interessado.

   FCReacoes.abrir(postId, { autorId, eu })   — abre a janela (eu = o meu id)
   FCReacoes.EMOJI                         — { Curtir: '👍', … }
   ============================================================ */
(function () {
  var EMOJI = { Curtir: '👍', Amei: '❤️', Haha: '😂', Triste: '😢', Uau: '😮' };
  var ORDEM = ['Curtir', 'Amei', 'Haha', 'Triste', 'Uau'];
  var esc = function (s) { return String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;'); };
  var sb = function () { return window.supabaseClient || (window.FC && FC.sb) || null; };

  function estilos() {
    if (document.getElementById('fc-reacoes-css')) return;
    var s = document.createElement('style');
    s.id = 'fc-reacoes-css';
    s.textContent =
      '.fcr-fundo{position:fixed;inset:0;background:rgba(0,0,0,.55);z-index:10050;display:flex;align-items:flex-end;justify-content:center}' +
      '@media(min-width:640px){.fcr-fundo{align-items:center}}' +
      '.fcr-caixa{width:100%;max-width:440px;max-height:80vh;display:flex;flex-direction:column;border-radius:18px 18px 0 0;overflow:hidden;' +
        'background:var(--bg-card,var(--bg-primary,#fff));color:var(--text-main,var(--text-primary,#111));box-shadow:0 10px 40px rgba(0,0,0,.35);animation:fcrSobe .18s ease-out}' +
      '@media(min-width:640px){.fcr-caixa{border-radius:18px}}' +
      '@keyframes fcrSobe{from{transform:translateY(24px);opacity:0}to{transform:none;opacity:1}}' +
      '.fcr-topo{display:flex;align-items:center;justify-content:space-between;padding:14px 16px 6px}' +
      '.fcr-topo h3{font-size:16px;margin:0}' +
      '.fcr-fechar{background:none;border:none;font-size:22px;line-height:1;cursor:pointer;color:inherit;opacity:.7;padding:4px 8px}' +
      '.fcr-abas{display:flex;gap:4px;padding:4px 12px 8px;overflow-x:auto;border-bottom:1px solid var(--border,var(--border-color,rgba(127,127,127,.25)))}' +
      '.fcr-abas button{flex-shrink:0;border:none;background:none;color:inherit;font:inherit;font-size:14px;font-weight:600;padding:7px 11px;border-radius:20px;cursor:pointer;opacity:.75}' +
      '.fcr-abas button.sel{background:var(--hover-bg,var(--bg-hover,rgba(127,127,127,.15)));opacity:1;color:var(--primary,#e4a11b)}' +
      '.fcr-lista{overflow-y:auto;padding:6px 8px 14px;-webkit-overflow-scrolling:touch}' +
      '.fcr-p{display:flex;align-items:center;gap:12px;padding:8px;border-radius:12px}' +
      '.fcr-p:hover{background:var(--hover-bg,var(--bg-hover,rgba(127,127,127,.1)))}' +
      '.fcr-av{position:relative;flex-shrink:0;cursor:pointer}' +
      '.fcr-av img{width:42px;height:42px;border-radius:50%;object-fit:cover;display:block}' +
      '.fcr-av span{position:absolute;right:-4px;bottom:-3px;font-size:15px}' +
      '.fcr-nome{flex:1;min-width:0;cursor:pointer}' +
      '.fcr-nome b{display:block;font-size:14.5px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}' +
      '.fcr-nome small{color:var(--text-secondary,#777);font-size:12px}' +
      '.fcr-msg{flex-shrink:0;border:1px solid var(--border,var(--border-color,rgba(127,127,127,.3)));background:none;color:inherit;border-radius:20px;padding:6px 12px;font:inherit;font-size:13px;font-weight:600;cursor:pointer;text-decoration:none}' +
      '.fcr-msg:hover{border-color:var(--primary,#e4a11b);color:var(--primary,#e4a11b)}' +
      '.fcr-vazio{text-align:center;color:var(--text-secondary,#777);padding:24px 12px;font-size:14px}';
    document.head.appendChild(s);
  }

  function fechar() {
    var f = document.querySelector('.fcr-fundo');
    if (f) f.remove();
    document.removeEventListener('keydown', teclaEsc);
  }
  function teclaEsc(e) { if (e.key === 'Escape') fechar(); }

  // o meu id: passado em { eu }, ou o currentUser da página (variável global "let", não está em window)
  function eu(o) { if (o.eu) return o.eu; try { return (typeof currentUser !== 'undefined' && currentUser && currentUser.id) || null; } catch (e) { return null; } }

  async function abrir(postId, o) {
    o = o || {};
    var cli = sb();
    if (!cli || !postId) return;
    estilos(); fechar();
    var fundo = document.createElement('div');
    fundo.className = 'fcr-fundo';
    fundo.innerHTML = '<div class="fcr-caixa" role="dialog" aria-modal="true" aria-label="Quem reagiu">' +
      '<div class="fcr-topo"><h3>Quem reagiu</h3><button type="button" class="fcr-fechar" aria-label="Fechar">×</button></div>' +
      '<div class="fcr-abas"></div><div class="fcr-lista"><p class="fcr-vazio">A carregar…</p></div></div>';
    document.body.appendChild(fundo);
    fundo.addEventListener('click', function (e) { if (e.target === fundo || e.target.closest('.fcr-fechar')) fechar(); });
    document.addEventListener('keydown', teclaEsc);

    var r = await cli.from('likes')
      .select('reaction, created_at, user_id, quem:perfis!likes_user_id_fkey(id, full_name, avatar_url, type, city)')
      .eq('post_id', postId).order('created_at', { ascending: false }).limit(500);
    if (!document.body.contains(fundo)) return;
    var lista = fundo.querySelector('.fcr-lista'), abas = fundo.querySelector('.fcr-abas');
    if (r.error) { lista.innerHTML = '<p class="fcr-vazio">Não foi possível carregar. Verifique a ligação e tente outra vez.</p>'; return; }
    var meu = eu(o);
    var todos = (r.data || []).filter(function (l) { return l.quem; });
    var souAutor = !!(meu && o.autorId && meu === o.autorId);
    var conta = {}; todos.forEach(function (l) { conta[l.reaction] = (conta[l.reaction] || 0) + 1; });

    var tabs = [['', 'Todas ' + todos.length]].concat(ORDEM.filter(function (k) { return conta[k]; }).map(function (k) { return [k, EMOJI[k] + ' ' + conta[k]]; }));
    abas.innerHTML = tabs.map(function (t, i) { return '<button type="button" data-r="' + t[0] + '"' + (i ? ' title="' + t[0] + '"' : '') + ' class="' + (i ? '' : 'sel') + '">' + t[1] + '</button>'; }).join('');

    function mostrar(filtro) {
      var v = todos.filter(function (l) { return !filtro || l.reaction === filtro; });
      if (!v.length) { lista.innerHTML = '<p class="fcr-vazio">Ainda ninguém reagiu a esta publicação.</p>'; return; }
      lista.innerHTML = v.map(function (l) {
        var q = l.quem, nome = q.full_name || 'Utilizador';
        var av = q.avatar_url ? (window.FC && FC.u ? FC.u(q.avatar_url) : q.avatar_url)
          : 'https://ui-avatars.com/api/?name=' + encodeURIComponent(nome) + '&background=random&color=fff&size=84';
        var sub = [q.type === 'empresa' ? 'Empresa' : '', q.city || '', window.FC && FC.haQuanto ? FC.haQuanto(l.created_at) : ''].filter(Boolean).join(' · ');
        var msg = souAutor && q.id !== meu ? '<a class="fcr-msg" href="mensagen.html?para=' + encodeURIComponent(q.id) + '"><i class="fas fa-paper-plane"></i> Mensagem</a>' : '';
        return '<div class="fcr-p" data-id="' + esc(q.id) + '"><div class="fcr-av"><img src="' + esc(av) + '" alt="" loading="lazy"><span>' + (EMOJI[l.reaction] || '👍') + '</span></div>' +
          '<div class="fcr-nome"><b data-no-i18n>' + esc(nome) + '</b>' + (sub ? '<small>' + esc(sub) + '</small>' : '') + '</div>' + msg + '</div>';
      }).join('');
    }
    mostrar('');
    abas.addEventListener('click', function (e) {
      var b = e.target.closest('button'); if (!b) return;
      abas.querySelectorAll('button').forEach(function (x) { x.classList.toggle('sel', x === b); });
      mostrar(b.dataset.r);
    });
    lista.addEventListener('click', function (e) {
      if (e.target.closest('.fcr-msg')) return;
      var p = e.target.closest('.fcr-p'); if (!p) return;
      var id = p.dataset.id;
      location.href = id === meu ? 'perfil.html' : 'perfil.html?id=' + encodeURIComponent(id);
    });
  }

  window.FCReacoes = { abrir: abrir, fechar: fechar, EMOJI: EMOJI, ORDEM: ORDEM };
})();
