-- ============================================================
-- Feira Comercial — 039: De onde vêm as contas novas
-- Correr no Supabase: SQL Editor → New query → colar tudo → Run
-- Pode ser corrido mais de uma vez sem problema.
--
-- • Cada conta nova guarda a "origem": o link por onde entrou (ex.: ?o=facebook)
--   ou a resposta a "Como conheceu a Feira Comercial?" no registo.
-- • A pessoa não pode mudar a origem depois (não há permissão de escrita nesta coluna).
-- • Administração → Crescimento mostra quantas contas vieram de cada sítio.
-- ============================================================

alter table public.perfis add column if not exists origem text;

create or replace function public.origem_inicial()
returns trigger language plpgsql security definer set search_path = public, auth as $$
declare o text;
begin
  select lower(btrim(raw_user_meta_data->>'origem')) into o from auth.users where id = new.id;
  if o ~ '^[a-z0-9_-]{1,30}$' then new.origem := o; end if;
  return new;
exception when others then
  return new;   -- nunca impede a criação da conta
end $$;

drop trigger if exists trg_origem_inicial on public.perfis;
create trigger trg_origem_inicial before insert on public.perfis
  for each row execute function public.origem_inicial();

create or replace function public.admin_origens(p_dias int default 30)
returns table (origem text, contas bigint, empresas bigint)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  if not sou_admin() then raise exception 'só o administrador'; end if;
  return query
  select coalesce(p.origem, 'desconhecida'), count(*), count(*) filter (where p.type = 'empresa')
    from perfis p
   where p.created_at > now() - make_interval(days => greatest(1, least(coalesce(p_dias, 30), 365)))
     and p.role not in ('admin', 'equipa')
   group by 1
   order by 2 desc;
end $$;
revoke all on function public.admin_origens(int) from public, anon;
grant execute on function public.admin_origens(int) to authenticated;

-- a origem não muda depois de criada (só o servidor pode corrigir)
create or replace function public.proteger_origem()
returns trigger language plpgsql set search_path = public as $$
begin
  if coalesce(auth.role(), '') <> 'service_role' and current_user not in ('postgres', 'supabase_admin') then
    new.origem := old.origem;
  end if;
  return new;
end $$;
drop trigger if exists trg_proteger_origem on public.perfis;
create trigger trg_proteger_origem before update on public.perfis
  for each row execute function public.proteger_origem();
