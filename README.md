# Social App - Guia de Lançamento (Vercel + Supabase)

Este projeto foi melhorado para suportar funcionalidades avançadas e está pronto para ser lançado.

## Melhorias Implementadas

1.  **Comentários Estilo Facebook**: Agora é possível responder a comentários específicos, criando conversas em árvore.
2.  **Botão de Enviar**: Adicionado um botão de "Avião" para enviar comentários e respostas manualmente.
3.  **Correção de Modo Escuro**: Todos os campos de texto, avatares e textos agora são perfeitamente visíveis tanto no modo claro quanto no escuro.
4.  **Coluna Direita Dinâmica**: Implementado um feed de fotos/vídeos aleatórios que desliza a cada 7 segundos.
5.  **Segurança de Chaves**: O código está preparado para usar variáveis de ambiente, evitando que suas chaves fiquem expostas no código-fonte.

## Como Lançar no Vercel

Para manter suas chaves seguras, siga estes passos:

1.  **Suba para o GitHub**: Crie um repositório privado e suba estes arquivos.
2.  **Conecte ao Vercel**: No painel do Vercel, importe o repositório.
3.  **Configure Variáveis de Ambiente**:
    *   No Vercel, vá em `Settings` > `Environment Variables`.
    *   Adicione `SUPABASE_URL` com o valor da sua URL.
    *   Adicione `SUPABASE_ANON_KEY` com sua Publishable Key.
4.  **Ajuste no Código**: No arquivo `script.js`, as variáveis `SB_URL` e `SB_KEY` podem ser preenchidas diretamente se o repositório for **privado**, mas o ideal é usar um pequeno script de backend ou o `Supabase Auth` para maior segurança.

## Suas Chaves Supabase
Para sua referência (mantenha estas chaves seguras e não as compartilhe):
- **Publishable Key**: `sb_publisha**8g_W-aUkOb0`
- **Secret Key**: `sb_**sA_lK19t74g` (Nunca use a Secret Key no frontend!)

---
*Desenvolvido para alta performance e experiência do usuário.*
