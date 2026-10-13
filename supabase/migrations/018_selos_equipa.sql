-- ============================================================
-- Feira Comercial — 018: Selos oficiais (Administrador / Equipa Feira Comercial)
-- Correr no Supabase: SQL Editor → New query → colar tudo → Run
-- Pode ser corrido mais de uma vez sem problema.
-- ============================================================

-- Lista das contas oficiais e o selo de cada uma (só id e texto do selo; nada privado)
create or replace function public.selos()
returns table (id uuid, selo text) language sql stable security definer set search_path = public as $$
  select p.id,
         case p.role when 'admin' then 'Administrador' when 'equipa' then 'Equipa Feira Comercial' end
  from perfis p
  where p.role in ('admin', 'equipa');
$$;
revoke all on function public.selos() from public;
grant execute on function public.selos() to anon, authenticated;

-- A sua conta de administrador: cidade Maputo e telefone (o telefone de pessoas
-- nunca aparece a outros utilizadores — só o dono e o administrador o veem)
update public.perfis
set city = 'Maputo', province = 'Maputo Cidade', phone = '+258 877663748'
where id = 'ede042b6-964f-46fb-a361-0432ef30715e';
