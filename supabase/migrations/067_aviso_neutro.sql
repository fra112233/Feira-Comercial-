-- ============================================================
-- Feira Comercial — 067: Não dizer ao burlão como foi apanhado
-- Correr no Supabase: SQL Editor → New query → colar tudo → Run
-- Pode ser corrido mais de uma vez sem problema.
-- Precisa da migração 065.
--
-- 1) A conta posta em revisão por causa do aparelho via a frase "esta conta foi
--    aberta num aparelho de uma conta suspensa". Isso ensinava o burlão a trocar de
--    telemóvel. Agora vê só: "Em revisão de segurança. A equipa vai analisar a sua
--    conta em breve." O motivo verdadeiro continua no aviso à equipa (sino e
--    telemóvel), no registo do administrador e no Painel → Contas.
-- 2) registar_aparelho devolve true quando a conta acaba de ficar em revisão, para
--    o site mostrar logo a faixa vermelha (antes só aparecia na página seguinte).
-- ============================================================

create or replace function public.travar_ou_avisar_aparelho(p_conta uuid, p_suspensa uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  c perfis%rowtype;
  nome_s text := coalesce((select full_name from perfis where id = p_suspensa), 'uma conta suspensa');
  ja boolean;
  sistema constant uuid := 'a73d8f73-5b2c-4f03-9deb-17aa890287dd';   -- conta da Equipa Feira Comercial
begin
  select * into c from perfis where id = p_conta;
  if not found or coalesce(c.bloqueado, false) or c.role in ('admin', 'equipa', 'ajudante') then return; end if;
  ja := exists (select 1 from aparelhos_avisos where conta = c.id and criado > now() - interval '7 days');
  insert into aparelhos_avisos (conta, suspensa) values (c.id, p_suspensa) on conflict do nothing;
  if c.created_at > now() - interval '30 days' and c.verificada_em is null and c.revisto_em is null then
    update perfis set bloqueado = true,
           bloqueio_motivo = 'Em revisão de segurança. A equipa vai analisar a sua conta em breve.'   -- neutro: não diz ao burlão como foi apanhado
     where id = c.id;
    insert into registo_admin (admin_id, acao, conta_a, conta_b, motivo)
    values (sistema, 'travao_aparelho', c.id, p_suspensa, 'Aberta no aparelho de uma conta suspensa');
    insert into notificacoes (user_id, autor_id, tipo, texto)
    select p.id, c.id, 'travao', coalesce(c.full_name, 'Uma conta') || ' ficou em revisão: aberta no aparelho de ' || nome_s || ' (suspensa)'
      from perfis p where p.role in ('admin', 'ajudante');
  elsif not ja then
    insert into notificacoes (user_id, autor_id, tipo, texto)
    select p.id, c.id, 'mesmo_aparelho', nome_s from perfis p where p.role = 'admin';
  end if;
end $$;
revoke all on function public.travar_ou_avisar_aparelho(uuid, uuid) from public, anon, authenticated;

-- contas que já tinham a frase antiga
update public.perfis
   set bloqueio_motivo = 'Em revisão de segurança. A equipa vai analisar a sua conta em breve.'
 where bloqueio_motivo like 'Em revisão: esta conta foi aberta num aparelho de uma conta suspensa%';

-- ---------- registar o aparelho: agora diz se a conta acabou de ficar em revisão ----------
drop function if exists public.registar_aparelho(text, text);
create function public.registar_aparelho(p_token text, p_impressao text default null)
returns boolean language plpgsql security definer set search_path = public as $$
declare
  eu perfis%rowtype;
  rede_h text;
  s record;
begin
  select * into eu from perfis where id = auth.uid();
  if not found then return false; end if;
  if coalesce(p_token, '') !~ '^[A-Za-z0-9_-]{16,64}$' then return false; end if;
  if coalesce(p_impressao, '') !~ '^[a-f0-9]{16,64}$' then p_impressao := null; end if;
  -- resumo da rede (primeiro endereço do pedido); o endereço em si não é guardado
  begin
    rede_h := md5('fc-rede:' || nullif(btrim(split_part(coalesce(
      current_setting('request.headers', true)::json ->> 'x-forwarded-for', ''), ',', 1)), ''));
  exception when others then rede_h := null;
  end;

  insert into aparelhos as a (conta, token, impressao, rede)
  values (eu.id, p_token, p_impressao, rede_h)
  on conflict (conta, token) do update
    set ultimo = now(), vezes = a.vezes + 1,
        impressao = coalesce(excluded.impressao, a.impressao),
        rede = coalesce(excluded.rede, a.rede);

  delete from aparelhos where ultimo < now() - interval '1 year';

  if eu.role in ('admin', 'equipa', 'ajudante') or coalesce(eu.bloqueado, false) then return false; end if;

  -- o mesmo aparelho já foi usado por uma conta suspensa?
  select q.id, q.full_name into s
    from aparelhos b join perfis q on q.id = b.conta
   where b.token = p_token and b.conta <> eu.id and coalesce(q.bloqueado, false)
     and not exists (select 1 from aparelhos_avisos v where v.conta = eu.id and v.suspensa = q.id)
   order by b.ultimo desc limit 1;
  if s.id is null then return false; end if;
  perform travar_ou_avisar_aparelho(eu.id, s.id);
  -- true = a conta acabou de ficar em revisão (o site mostra logo a faixa)
  return coalesce((select bloqueado from perfis where id = eu.id), false);
end $$;
revoke all on function public.registar_aparelho(text, text) from public, anon;
grant execute on function public.registar_aparelho(text, text) to authenticated;

-- ver se ficou bem: deve mostrar 1 linha "registar_aparelho | boolean"
select p.proname as funcao, pg_get_function_result(p.oid) as devolve
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname = 'registar_aparelho';
