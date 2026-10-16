/* ============================================================
   Feira Comercial — primeiros-passos.js
   Cartão "Os seus primeiros passos" na página inicial, para quem chegou há pouco:
   foto, cidade, seguir 3 empresas (com sugestões) e primeira publicação / primeiro gosto.
   Quando tudo estiver feito: parabéns com confetes (uma vez) e o cartão desaparece.
   Precisa da migração 032 (primeiros_passos, sugestoes_seguir). Sem ela, não mostra nada.
   ============================================================ */
(function () {
  var DIAS = 30;          // só para contas com menos de 30 dias
  var uid = null, aberto = false;
  var esc = function (s) { return String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;'); };
  var ls = function (k, v) { try { if (v === undefined) return localStorage.getItem(k); localStorage.setItem(k, v); } catch (e) { return null; } };

  function css() {
    if (document.getElementById('pp-css')) return;
    var s = document.createElement('style'); s.id = 'pp-css';
    s.textContent =
      '.pp{background:var(--bg-card,#242526);border:1px solid rgba(243,198,78,.35);border-radius:14px;padding:16px;margin:0 0 12px;box-shadow:var(--shadow,none);position:relative;overflow:hidden}' +
      '.pp-cab{display:flex;align-items:center;gap:10px;margin-bottom:10px}.pp-cab b{font-size:16px;flex:1}.pp-cab .pp-n{font-size:12.5px;color:var(--text-secondary,#b0b3b8);font-weight:600}' +
      '.pp-x{border:none;background:none;color:var(--text-secondary,#b0b3b8);font-size:18px;cursor:pointer;width:30px;height:30px;border-radius:50%}.pp-x:hover{background:var(--hover-bg,#3a3b3c)}' +
      '.pp-sub{font-size:13px;color:var(--text-secondary,#b0b3b8);margin:-4px 0 10px}' +
      '.pp-barra{height:8px;border-radius:99px;background:var(--hover-bg,#3a3b3c);overflow:hidden;margin-bottom:12px}.pp-barra i{display:block;height:100%;background:linear-gradient(90deg,#f3c64e,#d9a52e);border-radius:99px;transition:width .6s ease}' +
      '.pp-l{list-style:none;margin:0;padding:0;display:grid;gap:6px}' +
      '.pp-l li{display:flex;align-items:center;gap:10px;padding:9px 10px;border-radius:10px;background:var(--hover-bg,rgba(255,255,255,.04));font-size:14px}' +
      '.pp-l li .pp-c{width:24px;height:24px;border-radius:50%;flex-shrink:0;display:flex;align-items:center;justify-content:center;font-size:12px;border:2px solid var(--text-secondary,#8a8d91);color:transparent}' +
      '.pp-l li.ok .pp-c{background:#22c55e;border-color:#22c55e;color:#fff}.pp-l li.ok span.t{text-decoration:line-through;opacity:.6}' +
      '.pp-l li span.t{flex:1}.pp-l li button{border:none;border-radius:999px;padding:6px 14px;font:600 12.5px inherit;font-family:inherit;cursor:pointer;background:linear-gradient(135deg,#f3c64e,#d9a52e);color:#111;white-space:nowrap}' +
      '.pp-sug{margin-top:12px}.pp-sug>b{font-size:13.5px;display:block;margin-bottom:8px}' +
      '.pp-sug .pp-lista{display:flex;gap:8px;overflow-x:auto;padding-bottom:4px;scroll-snap-type:x mandatory}' +
      '.pp-e{flex:0 0 132px;scroll-snap-align:start;border-radius:12px;background:var(--hover-bg,rgba(255,255,255,.04));padding:10px;text-align:center;display:flex;flex-direction:column;align-items:center;gap:4px}' +
      '.pp-e img{width:52px;height:52px;border-radius:50%;object-fit:cover;background:#475569}' +
      '.pp-e a{color:inherit;text-decoration:none;font-weight:700;font-size:13px;line-height:1.25;max-width:100%;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}' +
      '.pp-e small{font-size:11.5px;color:var(--text-secondary,#b0b3b8);max-width:100%;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}' +
      '.pp-e button{margin-top:4px;border:none;border-radius:999px;padding:6px 14px;font:600 12.5px inherit;font-family:inherit;cursor:pointer;background:var(--primary,#f3c64e);color:#fff}' +
      '.pp-e button.feito{background:var(--hover-bg,#3a3b3c);color:var(--text-secondary,#b0b3b8)}' +
      '.pp-fim{text-align:center;padding:8px 4px}.pp-fim .g{font-size:44px}.pp-fim b{display:block;font-size:17px;margin:6px 0 4px}.pp-fim p{margin:0;font-size:13.5px;color:var(--text-secondary,#b0b3b8)}' +
      '.pp-cf{position:absolute;top:-10px;width:8px;height:14px;border-radius:2px;animation:ppcai 2.2s ease-in forwards;pointer-events:none}' +
      '@keyframes ppcai{to{transform:translateY(260px) rotate(540deg);opacity:0}}';
    document.head.appendChild(s);
  }

  function confetes(el) {
    var cores = ['#f3c64e', '#ef4444', '#22c55e', '#3b82f6', '#a855f7'];
    for (var i = 0; i < 40; i++) {
      var c = document.createElement('i'); c.className = 'pp-cf';
      c.style.left = (Math.random() * 100) + '%'; c.style.background = cores[i % cores.length];
      c.style.animationDelay = (Math.random() * .6) + 's';
      el.appendChild(c);
    }
  }

  function lugar() {
    var f = document.getElementById('feed-filtros');
    var card = document.getElementById('pp-card');
    if (!card) { card = document.createElement('div'); card.id = 'pp-card'; card.className = 'pp'; if (f && f.parentNode) f.parentNode.insertBefore(card, f); else return null; }
    return card;
  }

  async function seguir(id, btn) {
    btn.disabled = true;
    var r = await supabaseClient.from('followers').insert({ follower_id: uid, following_id: id, created_at: Date.now() });
    if (r.error && !/duplicate|unique/i.test(r.error.message || '')) { btn.disabled = false; if (window.FC && FC.toast) FC.toast(FC.traduzirErro(r.error)); return; }
    btn.textContent = '✓ A seguir'; btn.classList.add('feito');
    setTimeout(carregar, 600);
  }
  window.FCPassos = { seguir: seguir, recarregar: function () { carregar(); } };

  async function carregar() {
    var card;
    var r = await supabaseClient.rpc('primeiros_passos');
    if (r.error || !r.data) { var c0 = document.getElementById('pp-card'); if (c0) c0.remove(); return; }
    var d = r.data, empresa = d.tipo === 'empresa';
    if (d.criado && (Date.now() - new Date(d.criado).getTime()) > DIAS * 864e5) return;
    var passos = [
      { ok: d.foto, t: 'Pôr uma foto de perfil', b: 'Pôr foto', a: 'FCMenu.editarPerfil()' },
      { ok: d.local, t: 'Indicar a sua cidade', b: 'Indicar', a: 'FCMenu.editarPerfil()' },
      { ok: d.seguindo >= 3, t: 'Seguir 3 empresas (' + Math.min(d.seguindo, 3) + '/3)', b: 'Ver sugestões', a: "document.getElementById('pp-sug').scrollIntoView({behavior:'smooth',block:'center'})" },
      empresa
        ? { ok: d.publicacoes > 0, t: 'Fazer a primeira publicação', b: 'Publicar', a: "(function(){var t=document.getElementById('post-text');if(t){t.scrollIntoView({behavior:'smooth',block:'center'});t.focus();}})()" }
        : { ok: d.gostos > 0, t: 'Gostar de uma publicação', b: 'Ver o feed', a: "(function(){var f=document.getElementById('feed-filtros');if(f)f.scrollIntoView({behavior:'smooth'});})()" }
    ];
    var feitos = passos.filter(function (p) { return p.ok; }).length, todos = feitos === passos.length;
    var chaveFim = 'fc_pp_fim_' + uid, chaveX = 'fc_pp_x_' + uid;

    if (todos) {
      if (ls(chaveFim)) { var c1 = document.getElementById('pp-card'); if (c1) c1.remove(); return; }
      card = lugar(); if (!card) return;
      css();
      card.innerHTML = '<div class="pp-fim"><div class="g">🎉</div><b>Parabéns, o seu perfil está pronto!</b>' +
        '<p>Já faz parte da Feira Comercial. Obrigado por estar connosco 💛</p></div>';
      confetes(card);
      ls(chaveFim, '1');
      setTimeout(function () { card.style.transition = 'opacity .5s'; card.style.opacity = '0'; setTimeout(function () { card.remove(); }, 600); }, 7000);
      return;
    }
    if (ls(chaveX) && Date.now() - Number(ls(chaveX)) < 3 * 864e5) return;   // escondido há menos de 3 dias

    card = lugar(); if (!card) return;
    css();
    var html = '<div class="pp-cab"><b>👋 Os seus primeiros passos</b><span class="pp-n">' + feitos + ' de ' + passos.length + '</span>' +
      '<button class="pp-x" type="button" title="Esconder" aria-label="Esconder" onclick="FCPassos.esconder()">×</button></div>' +
      '<p class="pp-sub">Leva só 2 minutos e ajuda a tirar o melhor da Feira Comercial.</p>' +
      '<div class="pp-barra"><i style="width:' + Math.round(100 * feitos / passos.length) + '%"></i></div><ul class="pp-l">' +
      passos.map(function (p) {
        return '<li class="' + (p.ok ? 'ok' : '') + '"><span class="pp-c">✓</span><span class="t">' + esc(p.t) + '</span>' +
          (p.ok ? '' : '<button type="button" onclick="' + esc(p.a) + '">' + esc(p.b) + '</button>') + '</li>';
      }).join('') + '</ul><div class="pp-sug" id="pp-sug"></div>';
    card.innerHTML = html;

    if (d.seguindo < 3) {
      var s = await supabaseClient.rpc('sugestoes_seguir', { p_limite: 8 });
      var box = document.getElementById('pp-sug');
      if (box && !s.error && s.data && s.data.length) {
        box.innerHTML = '<b>Sugestões para seguir</b><div class="pp-lista">' + s.data.map(function (e) {
          var foto = (window.FC && FC.u && FC.u(e.avatar_url)) || esc('https://ui-avatars.com/api/?name=' + encodeURIComponent(e.full_name || 'E') + '&background=random&color=fff&size=104');
          var onde = e.oficial ? 'Conta oficial' : (e.city || e.province || e.sector || '');
          return '<div class="pp-e"><a href="perfil.html?id=' + encodeURIComponent(e.id) + '"><img src="' + foto + '" alt="" loading="lazy"></a>' +
            '<a href="perfil.html?id=' + encodeURIComponent(e.id) + '" data-selo="' + esc(e.id) + '">' + esc(e.full_name || '') + '</a>' +
            '<small>' + esc(onde) + '</small>' +
            '<button type="button" onclick="FCPassos.seguir(\'' + esc(e.id) + '\', this)">Seguir</button></div>';
        }).join('') + '</div>';
      }
    }
  }
  window.FCPassos.esconder = function () { ls('fc_pp_x_' + uid, String(Date.now())); var c = document.getElementById('pp-card'); if (c) c.remove(); };

  async function iniciar() {
    if (aberto || typeof supabaseClient === 'undefined') return;
    aberto = true;
    var r = await supabaseClient.auth.getSession();
    var s = r && r.data && r.data.session; if (!s) return;
    uid = s.user.id;
    carregar();
    // quando volta à página (ex.: depois de pôr a foto), atualiza
    document.addEventListener('visibilitychange', function () { if (document.visibilityState === 'visible' && document.getElementById('pp-card')) carregar(); });
    // e de vez em quando, enquanto o cartão está à vista (depois de editar o perfil ou publicar)
    setInterval(function () { if (document.visibilityState === 'visible' && document.getElementById('pp-card') && !document.querySelector('.pp-fim')) carregar(); }, 20000);
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', function () { setTimeout(iniciar, 400); });
  else setTimeout(iniciar, 400);
})();
