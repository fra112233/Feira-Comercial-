// Configuração Supabase (Preparado para Vercel)
// Em produção, estas chaves devem vir de variáveis de ambiente no Vercel
const SB_URL = ''; // Adicionar URL do projeto Supabase
const SB_KEY = ''; // Adicionar Chave Anônima do Supabase

// Fallback para localStorage se Supabase não estiver configurado
let posts = JSON.parse(localStorage.getItem('fb_posts')) || [];
let stories = JSON.parse(localStorage.getItem('fb_stories')) || [];
let tempPostMedia = [];
let sTimer, activeIdx = 0;

// Variáveis para Lightbox
let imagensGrelha = [];
let indiceAtual = 0;

window.onload = () => { 
    renderPosts(); 
    renderStories(); 
    initRollingFeed();
    configurarEventosModal();
};

function toggleDarkMode() {
    const body = document.body;
    const current = body.getAttribute('data-theme');
    body.setAttribute('data-theme', current === 'dark' ? 'light' : 'dark');
}

function toggleDropdown(e) { 
    e.stopPropagation(); 
    document.getElementById("myDropdown").classList.toggle("show"); 
}

window.onclick = () => {
    const dropdown = document.getElementById("myDropdown");
    if (dropdown) dropdown.classList.remove("show");
};

// --- STORIES LOGIC ---
function addStory(event) {
    const file = event.target.files[0];
    if (!file) return;
    const reader = new FileReader();
    reader.onload = (e) => {
        stories.push({ 
            id: Date.now(),
            data: e.target.result, 
            type: file.type.startsWith('video') ? 'video' : 'image',
            timestamp: Date.now()
        });
        saveStories();
    };
    reader.readAsDataURL(file);
}

function saveStories() { 
    localStorage.setItem('fb_stories', JSON.stringify(stories)); 
    renderStories(); 
}

function renderStories() {
    const list = document.getElementById('stories-list');
    if (!list) return;
    list.innerHTML = `
        <div class="story-circle add" onclick="document.getElementById('up-story-input').click()">
            <i class="fas fa-plus"></i>
            <input type="file" id="up-story-input" hidden onchange="addStory(event)">
        </div>`;
    stories.forEach((s, i) => {
        const div = document.createElement('div');
        div.className = 'story-circle';
        div.onclick = () => openStory(i);
        div.innerHTML = s.type === 'video' ? `<video src="${s.data}"></video>` : `<img src="${s.data}">`;
        list.appendChild(div);
    });
}

function openStory(i) {
    activeIdx = i;
    const modal = document.getElementById('storyModal');
    const bar = document.getElementById('storyBarFill');
    if (!modal || !bar) return;
    
    modal.style.display = 'flex';
    const s = stories[i];
    const viewer = document.getElementById('storyViewer');
    
    const content = s.type === 'video' 
        ? `<video src="${s.data}" autoplay style="width:100%;height:100%;object-fit:contain"></video>` 
        : `<img src="${s.data}" style="width:100%;height:100%;object-fit:contain">`;
    
    const profileHeader = `
        <div style="position:absolute; top:25px; left:15px; right:15px; display:flex; align-items:center; gap:12px; z-index:15;">
            <div style="width:40px; height:40px; border-radius:50%; background:#ddd; display:flex; align-items:center; justify-content:center; color:white;"><i class="fas fa-user"></i></div>
            <div style="color:white; text-shadow: 1px 1px 2px black;">
                <div style="font-weight:bold;">Você</div>
                <div style="font-size:12px; opacity:0.8;">Agora</div>
            </div>
        </div>
    `;
    
    viewer.innerHTML = profileHeader + content;
    
    let w = 0; clearInterval(sTimer);
    sTimer = setInterval(() => {
        w += 1; bar.style.width = w + '%';
        if(w >= 100) { 
            activeIdx < stories.length - 1 ? openStory(activeIdx + 1) : closeStory(); 
        }
    }, 50);
}

function closeStory() { 
    document.getElementById('storyModal').style.display = 'none'; 
    clearInterval(sTimer); 
}

// --- POSTS LOGIC ---
function previewPostMedia(event) {
    tempPostMedia = Array.from(event.target.files);
    document.getElementById('post-preview-area').innerHTML = `<p style="padding:10px; color:var(--text-secondary);">${tempPostMedia.length} mídia(s) selecionada(s)</p>`;
}

async function publishPost() {
    const textInput = document.getElementById('post-text');
    const text = textInput.value.trim();
    if (!text && tempPostMedia.length === 0) return;

    const mediaPromises = tempPostMedia.map(file => {
        return new Promise(resolve => {
            const reader = new FileReader();
            reader.onload = (e) => resolve({ data: e.target.result, type: file.type.startsWith('video') ? 'video' : 'image' });
            reader.readAsDataURL(file);
        });
    });

    const mediaData = await Promise.all(mediaPromises);
    posts.unshift({ 
        id: Date.now(), 
        text, 
        media: mediaData, 
        reactType: 'Curtir', 
        reactCount: 0, 
        comments: [] 
    });
    
    savePosts();
    textInput.value = "";
    document.getElementById('post-preview-area').innerHTML = "";
    tempPostMedia = [];
}

function getGridLayout(count) {
    if (count === 1) return 'single';
    if (count === 2) return 'double';
    if (count === 3) return 'triple';
    return 'quad';
}

function renderPosts() {
    const feed = document.getElementById('feed');
    if (!feed) return;
    feed.innerHTML = posts.map(p => `
        <div class="post-card">
            <i class="fas fa-trash btn-delete" onclick="deletePost(${p.id})"></i>
            <div style="display:flex; gap:12px; align-items:center;">
                <i class="fas fa-user-circle fa-2x" style="color:#1877f2"></i>
                <div><b>Você</b><br><small style="color:var(--text-secondary)">Agora</small></div>
            </div>
            ${p.text ? `<p style="margin-top:15px; line-height:1.4; color:var(--text-main);">${p.text}</p>` : ''}
            
            ${p.media.length > 0 ? `
                <div class="gallery-preview">
                    <div class="gallery-grid ${getGridLayout(p.media.length)}">
                        ${p.media.slice(0, 4).map(m => 
                            m.type === 'video' ? 
                            `<video src="${m.data}" class="media-item" muted autoplay loop></video>` : 
                            `<img src="${m.data}" class="media-item" onclick="openLightbox(event)">`
                        ).join('')}
                    </div>
                </div>
            ` : ''}

            <div class="post-actions">
                <div class="btn-action">
                    <i class="fas fa-thumbs-up"></i> <span>${p.reactType}</span> (${p.reactCount})
                    <div class="reactions-box">
                        <span class="react-icon" onclick="setReact(${p.id}, 'Curtir')">👍</span>
                        <span class="react-icon" onclick="setReact(${p.id}, 'Amei')">❤️</span>
                        <span class="react-icon" onclick="setReact(${p.id}, 'Haha')">😂</span>
                        <span class="react-icon" onclick="setReact(${p.id}, 'Triste')">😢</span>
                    </div>
                </div>
                <div class="btn-action" onclick="toggleComm(${p.id})"><i class="fas fa-comment"></i> Comentar (${countAllComments(p.comments)})</div>
            </div>

            <div id="comm-${p.id}" class="comment-section">
                <div id="comment-list-${p.id}">
                    ${renderComments(p.comments, p.id)}
                </div>
                <div class="comment-input-container">
                    <input type="text" id="input-${p.id}" class="comment-input" placeholder="Escreva um comentário..." onkeypress="handleCommKeyPress(event, ${p.id})">
                    <button class="comment-btn-send" onclick="addComm(${p.id})">
                        <i class="fas fa-paper-plane"></i>
                    </button>
                </div>
            </div>
        </div>
    `).join('');
}

function countAllComments(comments) {
    let count = comments.length;
    comments.forEach(c => {
        if (c.replies) count += c.replies.length;
    });
    return count;
}

function renderComments(comments, postId, isReply = false) {
    return comments.map(c => `
        <div class="comment-item" id="comment-${c.id}">
            <div class="comment-main">
                <div class="comment-avatar"></div>
                <div class="comment-content">
                    <b>Usuário</b><br>${c.text}
                    <div class="reply-btn" onclick="showReplyInput(${postId}, ${c.id})">Responder</div>
                </div>
            </div>
            <div class="comment-replies" id="replies-${c.id}">
                ${c.replies ? renderComments(c.replies, postId, true) : ''}
            </div>
            <div id="reply-input-container-${c.id}" style="display:none; margin-left:40px; margin-top:5px;">
                <div class="comment-input-container">
                    <input type="text" id="reply-input-${c.id}" class="comment-input" placeholder="Escreva uma resposta..." onkeypress="handleReplyKeyPress(event, ${postId}, ${c.id})">
                    <button class="comment-btn-send" onclick="addReply(${postId}, ${c.id})">
                        <i class="fas fa-paper-plane"></i>
                    </button>
                </div>
            </div>
        </div>
    `).join('');
}

function showReplyInput(postId, commentId) {
    const container = document.getElementById(`reply-input-container-${commentId}`);
    container.style.display = container.style.display === 'none' ? 'flex' : 'none';
    if (container.style.display === 'flex') {
        document.getElementById(`reply-input-${commentId}`).focus();
    }
}

function handleCommKeyPress(e, id) {
    if(e.key === 'Enter') addComm(id);
}

function handleReplyKeyPress(e, postId, commentId) {
    if(e.key === 'Enter') addReply(postId, commentId);
}

function addComm(id) {
    const input = document.getElementById(`input-${id}`);
    const text = input.value.trim();
    if(!text) return;
    
    const post = posts.find(p => p.id === id);
    post.comments.push({ 
        id: Date.now(),
        text: text,
        replies: []
    });
    
    savePosts();
    input.value = "";
}

function addReply(postId, commentId) {
    const input = document.getElementById(`reply-input-${commentId}`);
    const text = input.value.trim();
    if(!text) return;
    
    const post = posts.find(p => p.id === postId);
    const comment = findComment(post.comments, commentId);
    
    if (comment) {
        if (!comment.replies) comment.replies = [];
        comment.replies.push({
            id: Date.now(),
            text: text,
            replies: []
        });
        savePosts();
    }
}

function findComment(comments, id) {
    for (let c of comments) {
        if (c.id === id) return c;
        if (c.replies && c.replies.length > 0) {
            let found = findComment(c.replies, id);
            if (found) return found;
        }
    }
    return null;
}

function setReact(id, type) { 
    const p = posts.find(x => x.id === id); 
    p.reactType = type; 
    p.reactCount++; 
    savePosts(); 
}

function deletePost(id) { 
    if(confirm("Deseja realmente apagar esta publicação?")) { 
        posts = posts.filter(p => p.id !== id); 
        savePosts(); 
    } 
}

function toggleComm(id) { 
    const el = document.getElementById(`comm-${id}`); 
    el.style.display = el.style.display === 'block' ? 'none' : 'block'; 
}

function savePosts() { 
    try { 
        localStorage.setItem('fb_posts', JSON.stringify(posts)); 
        renderPosts(); 
    } catch(e) { 
        alert("Memória local cheia!"); 
    }
}

// --- ROLLING FEED (RIGHT COLUMN) ---
let rollingIdx = 0;
function initRollingFeed() {
    const container = document.getElementById('rolling-feed');
    if (!container) return;
    
    // Gerar dados aleatórios se não houver posts
    const sampleData = posts.length > 0 ? posts.filter(p => p.media.length > 0) : [];
    
    function updateRolling() {
        if (posts.length === 0) {
            container.innerHTML = '<p style="padding:20px; text-align:center; color:var(--text-secondary);">Publique algo para ver aqui!</p>';
            return;
        }
        
        const mediaPosts = posts.filter(p => p.media.length > 0);
        if (mediaPosts.length === 0) return;
        
        const p = mediaPosts[Math.floor(Math.random() * mediaPosts.length)];
        const m = p.media[0];
        
        const item = document.createElement('div');
        item.className = 'rolling-item active';
        item.onclick = () => alert('Levando ao perfil do autor...');
        
        const mediaHtml = m.type === 'video' 
            ? `<video src="${m.data}" class="rolling-media" muted autoplay loop></video>` 
            : `<img src="${m.data}" class="rolling-media">`;
            
        item.innerHTML = `
            ${mediaHtml}
            <div class="rolling-info">
                <i class="fas fa-user-circle fa-lg" style="color:#1877f2"></i>
                <div>
                    <b>Usuário Aleatório</b><br>
                    <small style="color:var(--text-secondary)"><i class="fas fa-heart"></i> ${p.reactCount} curtidas</small>
                </div>
            </div>
        `;
        
        const oldItem = container.querySelector('.rolling-item.active');
        if (oldItem) {
            oldItem.classList.remove('active');
            oldItem.classList.add('prev');
            setTimeout(() => oldItem.remove(), 800);
        }
        
        container.appendChild(item);
    }
    
    updateRolling();
    setInterval(updateRolling, 7000);
}

// --- LIGHTBOX MODAL ---
function configurarEventosModal() {
    const modal = document.getElementById('janelaModal');
    if (!modal) return;
    
    document.getElementById('modalFechar').addEventListener('click', () => modal.style.display = 'none');
    modal.addEventListener('click', (e) => {
        if (e.target === modal) modal.style.display = 'none';
    });

    document.getElementById('modalPrev').addEventListener('click', (e) => {
        e.stopPropagation();
        mudarImagem(-1);
    });

    document.getElementById('modalNext').addEventListener('click', (e) => {
        e.stopPropagation();
        mudarImagem(1);
    });

    document.addEventListener('keydown', (e) => {
        if (modal.style.display === 'flex') {
            if (e.key === 'ArrowRight') mudarImagem(1);
            if (e.key === 'ArrowLeft') mudarImagem(-1);
            if (e.key === 'Escape') modal.style.display = 'none';
        }
    });
}

function openLightbox(evento) {
    const modal = document.getElementById('janelaModal');
    const imagemGrande = document.getElementById('fotoExpandida');
    const containerGrelha = evento.target.closest('.gallery-grid');
    
    imagensGrelha = Array.from(containerGrelha.querySelectorAll('img'));
    indiceAtual = imagensGrelha.indexOf(evento.target);

    if (modal && imagemGrande && indiceAtual !== -1) {
        imagemGrande.src = evento.target.src;
        modal.style.display = 'flex';
        
        const exibicaoBotoes = imagensGrelha.length > 1 ? 'block' : 'none';
        document.getElementById('modalPrev').style.display = exibicaoBotoes;
        document.getElementById('modalNext').style.display = exibicaoBotoes;
    }
}

function mudarImagem(direcao) {
    if (imagensGrelha.length <= 1) return;
    indiceAtual += direcao;
    if (indiceAtual >= imagensGrelha.length) indiceAtual = 0;
    if (indiceAtual < 0) indiceAtual = imagensGrelha.length - 1;
    document.getElementById('fotoExpandida').src = imagensGrelha[indiceAtual].src;
}
