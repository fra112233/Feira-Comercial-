/* ============================================================
   Feira Comercial — ajuda.js
   Topo e rodapé partilhados das páginas Sobre, Políticas e Reclamações.
   Uso: <header class="topo" data-atual="sobre|politicas|reclamacao"></header>
        <footer class="rodape"></footer>
        <script src="ajuda.js"></script>  (depois de supabase-config.js e menu.js)
   ============================================================ */
(function () {
  var topo = document.querySelector('header.topo');
  var atual = topo ? topo.getAttribute('data-atual') : '';
  function link(id, href, txt) { return '<a href="' + href + '"' + (atual === id ? ' class="atual" aria-current="page"' : '') + '>' + txt + '</a>'; }

  if (topo) {
    topo.innerHTML =
      '<div class="topo-in">' +
        '<a href="index.html" class="fc-marca" title="Feira Comercial"><img src="images/logo-icone.svg" alt="Feira Comercial">' +
          '<span class="fc-marca-txt"><b>Feira Comercial</b><small>Explore, Exiba, Expanda</small></span></a>' +
        '<nav aria-label="Ajuda">' + link('sobre', 'about.html', 'Sobre') + link('politicas', 'politicas.html', 'Termos e privacidade') +
          link('reclamacao', 'reclamacao.html', 'Reclamações') + '</nav>' +
        '<div class="acoes" id="topoAcoes"><a class="entrar" href="Portal.html"><i class="fas fa-right-to-bracket"></i> Entrar</a></div>' +
      '</div>';
  }

  var rodape = document.querySelector('footer.rodape');
  if (rodape) {
    rodape.innerHTML =
      '<div class="rodape-in"><span>© ' + new Date().getFullYear() + ' Feira Comercial · Moçambique</span>' +
      '<nav><a href="about.html">Sobre</a><a href="politicas.html">Termos e privacidade</a><a href="reclamacao.html">Reclamações e sugestões</a>' +
      '<a href="Formulario.html">Criar conta</a></nav></div>';
  }

  // Com sessão iniciada: botão "Início" e menu ☰ em vez de "Entrar"
  window.FCAjuda = { sessao: null, pronto: null };
  window.FCAjuda.pronto = (async function () {
    try {
      if (!window.FC || !FC.getSession) return null;
      var s = await FC.getSession();
      window.FCAjuda.sessao = s || null;
      if (s && document.getElementById('topoAcoes')) {
        document.getElementById('topoAcoes').innerHTML =
          '<a class="entrar" href="index.html"><i class="fas fa-house"></i> Início</a>' +
          (window.FCMenu ? '<button class="menu" style="display:inline-flex;align-items:center;justify-content:center" onclick="FCMenu.abrir()" aria-label="Menu" title="Menu"><i class="fas fa-bars"></i></button>' : '');
      }
      return s;
    } catch (e) { return null; }
  })();
})();
