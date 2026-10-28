-- ============================================================
-- Feira Comercial — 060: Ajudantes com dois passos
-- Correr no Supabase: SQL Editor → New query → colar tudo → Run
-- Pode ser corrido mais de uma vez sem problema.
--
-- AJUDANTES SÓ COM VERIFICAÇÃO EM DOIS PASSOS
--    • Só se pode tornar Ajudante quem já ativou os dois passos.
--    • O Ajudante só consegue usar as ferramentas da equipa se entrou com o código.
--    Assim, se roubarem a palavra-passe de um Ajudante, não chega para entrar.
--    (O administrador continua como estava: com dois passos se os tiver ativos.)
-- ============================================================

-- ---------- Ajudantes com dois passos ----------

create or replace function public.sou_suporte()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.perfis p
     where p.id = auth.uid()
       and (
         -- administrador: como antes (código pedido se tiver os dois passos ativos)
         (p.role = 'admin'
           and (coalesce(auth.jwt() ->> 'aal', 'aal1') = 'aal2'
                or not exists (select 1 from auth.mfa_factors f where f.user_id = auth.uid() and f.status = 'verified')))
         -- ajudante: tem sempre de ter entrado com o código
         or (p.role = 'ajudante' and coalesce(auth.jwt() ->> 'aal', 'aal1') = 'aal2')
       ));
$$;
revoke all on function public.sou_suporte() from public, anon;
grant execute on function public.sou_suporte() to authenticated;

create or replace function public.admin_definir_ajudante(p_uid uuid, p_sim boolean)
returns void language plpgsql security definer set search_path = public as $$
declare r text;
begin
  if not sou_admin() then raise exception 'só o administrador'; end if;
  select role into r from perfis where id = p_uid;
  if not found then raise exception 'conta não encontrada'; end if;
  if r in ('admin', 'equipa') then raise exception 'esta conta já é da equipa'; end if;
  if p_sim and not exists (select 1 from auth.mfa_factors f where f.user_id = p_uid and f.status = 'verified') then
    raise exception 'Esta pessoa ainda não ativou a verificação em dois passos. Peça-lhe para ativar em Menu → Privacidade e segurança, e tente outra vez.';
  end if;
  update perfis set role = case when p_sim then 'ajudante' else 'user' end where id = p_uid;
  insert into registo_admin (admin_id, acao, conta_a, conta_b, motivo)
    values (auth.uid(), case when p_sim then 'ajudante_sim' else 'ajudante_nao' end, p_uid, null, null);
end $$;
revoke all on function public.admin_definir_ajudante(uuid, boolean) from public, anon;
grant execute on function public.admin_definir_ajudante(uuid, boolean) to authenticated;

-- Para saber se o ajudante tem de ativar os dois passos (o painel mostra o aviso)
create or replace function public.ajudante_precisa_2passos()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from perfis where id = auth.uid() and role = 'ajudante')
     and coalesce(auth.jwt() ->> 'aal', 'aal1') <> 'aal2';
$$;
revoke all on function public.ajudante_precisa_2passos() from public, anon;
grant execute on function public.ajudante_precisa_2passos() to authenticated;
