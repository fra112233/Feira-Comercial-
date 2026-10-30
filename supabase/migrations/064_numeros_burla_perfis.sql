-- ============================================================
-- Feira Comercial — 064: Números de burlões nos perfis
-- Correr no Supabase: SQL Editor → New query → colar tudo → Run
-- Pode ser corrido mais de uma vez sem problema.
-- Precisa das migrações 051 (números proibidos) e 061 (verificar número).
--
-- Um burlão suspenso pode tentar voltar com outra conta e o MESMO número.
--  1) BLOQUEAR: ninguém cria conta nem põe no perfil (telefone/WhatsApp) um
--     número da lista de burlas. Quem já tinha o número antes de ele entrar na
--     lista não fica impedido de mudar o resto do perfil.
--  2) AVISAR A EQUIPA: o administrador recebe aviso no sino quando
--       • alguém tenta pôr no perfil (ou criar conta com) um número da lista;
--       • um número entra na lista e já está no perfil de OUTRA conta.
--  3) AVISO NO PERFIL E NO CHAT: contas_numero_burla() diz que contas têm no
--     perfil um número da lista (para o aviso vermelho a quem visita).
-- A equipa pode sempre tirar um número da lista (Painel → Suspeitos).
-- Para pôr um número da lista num perfil pelo SQL Editor (caso raro):
--   set local fc.permitir_numero = '1';  antes do update, na mesma transação.
-- ============================================================

-- novo tipo de aviso no sino: "número da lista de burlas num perfil"
alter table public.notificacoes drop constraint if exists notificacoes_tipo_check;
alter table public.notificacoes add constraint notificacoes_tipo_check check (tipo in (
  'gosto','comentario','resposta','seguir','publicacao','video','gosto_video','comentario_video','live',
  'avaliacao','resposta_avaliacao','convite_aceite','convite_premio',
  'marco_publicacao','marco_seguidor','marco_mensagem','gratis_fim','mensalidade_fim',
  'oferta_guardado','oferta_loja','resumo_semanal','lojas_hoje','travao','numero_proibido','cobranca',
  'gosto_story','numero_denunciado','numero_no_perfil'));

-- números (9 dígitos) do telefone e do WhatsApp de um perfil
create or replace function public.numeros_do_perfil(p_phone text, p_whatsapp text)
returns text[] language sql immutable set search_path = public as $$
  select numeros_em(coalesce(p_phone, '') || ' ' || coalesce(p_whatsapp, ''));
$$;

-- ---------- 1) Bloquear números da lista no perfil ----------
create or replace function public.impedir_numero_burla()
returns trigger language plpgsql security definer set search_path = public as $$
declare novos text[];
begin
  if coalesce(auth.role(), '') = 'service_role' then return new; end if;
  if coalesce(current_setting('fc.permitir_numero', true), '') = '1' then return new; end if;
  if new.role in ('admin', 'equipa') then return new; end if;
  novos := numeros_do_perfil(new.phone, new.whatsapp);
  if tg_op = 'UPDATE' then
    -- só os números que entram agora (quem já os tinha não fica preso)
    novos := array(select unnest(novos) except select unnest(numeros_do_perfil(old.phone, old.whatsapp)));
  end if;
  if coalesce(array_length(novos, 1), 0) > 0 and exists (
       select 1 from numeros_proibidos np where np.numero = any (novos) and np.conta is distinct from new.id) then
    raise exception 'Este número está na lista de burlas da Feira Comercial. Use outro número ou fale com a equipa.'
      using errcode = 'P0001', hint = 'numero_burla';
  end if;
  return new;
end $$;
revoke all on function public.impedir_numero_burla() from public, anon, authenticated;
drop trigger if exists trg_impedir_numero_burla on public.perfis;
create trigger trg_impedir_numero_burla before insert or update of phone, whatsapp on public.perfis
  for each row execute function public.impedir_numero_burla();

-- ---------- 2a) Avisar a equipa: tentativa recusada ----------
-- O site chama isto quando o perfil (ou a conta nova) é recusado por causa do número.
-- Só avisa se o número estiver mesmo na lista; no máximo um aviso por número e por dia.
create or replace function public.avisar_tentativa_numero(p_numero text, p_criar_conta boolean default false)
returns void language plpgsql security definer set search_path = public as $$
declare n text := (numeros_em(p_numero))[1]; eu uuid := auth.uid();
begin
  if n is null then return; end if;
  if not exists (select 1 from numeros_proibidos where numero = n and conta is distinct from eu) then return; end if;
  if exists (select 1 from notificacoes where tipo = 'numero_no_perfil' and texto like '%' || n || '%'
              and criado > now() - interval '1 day') then return; end if;
  insert into notificacoes (user_id, autor_id, tipo, texto)
  select a.id, eu, 'numero_no_perfil',
         case when p_criar_conta or eu is null then 'tentou criar conta com o número ' || n
              else 'tentou pôr no perfil o número ' || n end
    from perfis a where a.role = 'admin';
end $$;
revoke all on function public.avisar_tentativa_numero(text, boolean) from public;
grant execute on function public.avisar_tentativa_numero(text, boolean) to anon, authenticated;

-- ---------- 2b) Avisar a equipa: número entra na lista e já está noutro perfil ----------
create or replace function public.avisar_perfis_com_numero()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into notificacoes (user_id, autor_id, tipo, texto)
  select a.id, p.id, 'numero_no_perfil', 'tem no perfil o número ' || new.numero || ', que entrou agora na lista'
    from perfis p
    join perfis a on a.role = 'admin'
   where p.id is distinct from new.conta
     and coalesce(p.role, '') not in ('admin', 'equipa')
     and new.numero = any (numeros_do_perfil(p.phone, p.whatsapp));
  return new;
end $$;
revoke all on function public.avisar_perfis_com_numero() from public, anon, authenticated;
drop trigger if exists trg_avisar_perfis_com_numero on public.numeros_proibidos;
create trigger trg_avisar_perfis_com_numero after insert on public.numeros_proibidos
  for each row execute function public.avisar_perfis_com_numero();

-- ---------- 3) Que contas têm no perfil um número da lista ----------
-- Para o aviso vermelho no perfil e no topo do chat. Não mostra o número nem a lista.
create or replace function public.contas_numero_burla(p_ids uuid[])
returns table (id uuid)
language sql stable security definer set search_path = public as $$
  select p.id from perfis p
   where p.id = any (p_ids[1:300])
     and coalesce(p.role, '') not in ('admin', 'equipa')
     and exists (select 1 from numeros_proibidos np
                  where np.numero = any (numeros_do_perfil(p.phone, p.whatsapp)));
$$;
revoke all on function public.contas_numero_burla(uuid[]) from public;
grant execute on function public.contas_numero_burla(uuid[]) to anon, authenticated;

-- ver se ficou bem: deve mostrar 4 linhas
select p.proname as funcao from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname in ('impedir_numero_burla', 'avisar_tentativa_numero', 'avisar_perfis_com_numero', 'contas_numero_burla')
 order by 1;
