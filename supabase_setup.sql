-- ══════════════════════════════════════════════════════════
--  SUVITA — Setup completo do banco de dados Supabase
--  Execute este SQL no painel: Supabase → SQL Editor → Run
-- ══════════════════════════════════════════════════════════

-- ── 1. PROFILES (criado automaticamente ao cadastrar) ─────
create table if not exists public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  nome        text,
  avatar_url  text,
  plano       text default 'gratuito',
  is_admin    boolean default false,
  status      text default 'ativo',
  created_at  timestamptz default now()
);

-- Trigger: cria perfil automaticamente quando usuário se cadastra
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, nome)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'nome', new.raw_user_meta_data->>'full_name', split_part(new.email, '@', 1))
  )
  on conflict (id) do nothing;
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- ── 2. METAS ──────────────────────────────────────────────
create table if not exists public.metas (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid references auth.users(id) on delete cascade,
  titulo      text not null,
  prazo       text,
  pct         integer default 0,
  categoria   text default 'financeiro',
  created_at  timestamptz default now()
);

-- ── 3. TAREFAS ────────────────────────────────────────────
create table if not exists public.tarefas (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid references auth.users(id) on delete cascade,
  texto       text not null,
  categoria   text default 'outro',
  done        boolean default false,
  created_at  timestamptz default now()
);

-- ── 4. ROTINA ─────────────────────────────────────────────
create table if not exists public.rotina (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid references auth.users(id) on delete cascade,
  hora        text,
  titulo      text not null,
  descricao   text default '',
  categoria   text default 'trabalho',
  created_at  timestamptz default now()
);

-- ── 5. LEMBRETES ──────────────────────────────────────────
create table if not exists public.lembretes (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid references auth.users(id) on delete cascade,
  texto       text not null,
  hora        text,
  recorrencia text default 'todos',
  created_at  timestamptz default now()
);

-- ── 6. TRANSACOES ─────────────────────────────────────────
create table if not exists public.transacoes (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid references auth.users(id) on delete cascade,
  tipo        text not null,
  descricao   text not null,
  valor       numeric(12,2) not null,
  categoria   text default 'outro',
  data        date default current_date,
  created_at  timestamptz default now()
);

-- ── 7. PLANILHAS DO USUÁRIO ───────────────────────────────
create table if not exists public.user_planilhas (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid references auth.users(id) on delete cascade,
  nome        text not null,
  cols        text default '[]',
  created_at  timestamptz default now()
);

-- ── 8. LINHAS DAS PLANILHAS ───────────────────────────────
create table if not exists public.sh_linhas (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid references auth.users(id) on delete cascade,
  planilha_id  uuid references public.user_planilhas(id) on delete cascade,
  mes          text,
  data         text,
  cols_data    text default '{}',
  receita      numeric(12,2) default 0,
  despesa      numeric(12,2) default 0,
  created_at   timestamptz default now()
);

-- ── 9. HISTÓRICO DE MESES ─────────────────────────────────
create table if not exists public.historico_meses (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid references auth.users(id) on delete cascade,
  mes          text not null,
  dados        text default '{}',
  resumo       text default '{}',
  created_at   timestamptz default now()
);

-- ── 10. PLANILHA APP (legado) ─────────────────────────────
create table if not exists public.planilha_app (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid references auth.users(id) on delete cascade,
  mes         text,
  dados       text default '{}',
  created_at  timestamptz default now()
);

-- ── 11. PLANILHA RUA (legado) ─────────────────────────────
create table if not exists public.planilha_rua (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid references auth.users(id) on delete cascade,
  mes         text,
  dados       text default '{}',
  created_at  timestamptz default now()
);

-- ══════════════════════════════════════════════════════════
--  ROW LEVEL SECURITY — cada usuário vê apenas seus dados
-- ══════════════════════════════════════════════════════════

alter table public.profiles       enable row level security;
alter table public.metas          enable row level security;
alter table public.tarefas        enable row level security;
alter table public.rotina         enable row level security;
alter table public.lembretes      enable row level security;
alter table public.transacoes     enable row level security;
alter table public.user_planilhas enable row level security;
alter table public.sh_linhas      enable row level security;
alter table public.historico_meses enable row level security;
alter table public.planilha_app   enable row level security;
alter table public.planilha_rua   enable row level security;

-- Políticas: usuário só acessa seus próprios dados
do $$ declare t text; begin
  foreach t in array array[
    'metas','tarefas','rotina','lembretes','transacoes',
    'user_planilhas','sh_linhas','historico_meses',
    'planilha_app','planilha_rua'
  ] loop
    execute format('
      drop policy if exists "user_only" on public.%I;
      create policy "user_only" on public.%I
        for all using (auth.uid() = user_id)
        with check (auth.uid() = user_id);
    ', t, t);
  end loop;
end $$;

-- Política especial para profiles (acesso pelo próprio id)
drop policy if exists "user_own_profile" on public.profiles;
create policy "user_own_profile" on public.profiles
  for all using (auth.uid() = id)
  with check (auth.uid() = id);

-- ══════════════════════════════════════════════════════════
--  STORAGE — bucket para avatares
-- ══════════════════════════════════════════════════════════

insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do nothing;

drop policy if exists "avatar_upload" on storage.objects;
create policy "avatar_upload" on storage.objects
  for insert with check (bucket_id = 'avatars' and auth.uid()::text = (storage.foldername(name))[1]);

drop policy if exists "avatar_read" on storage.objects;
create policy "avatar_read" on storage.objects
  for select using (bucket_id = 'avatars');

drop policy if exists "avatar_update" on storage.objects;
create policy "avatar_update" on storage.objects
  for update using (bucket_id = 'avatars' and auth.uid()::text = (storage.foldername(name))[1]);

-- ══════════════════════════════════════════════════════════
--  PRONTO! Todas as tabelas e políticas criadas com sucesso.
-- ══════════════════════════════════════════════════════════
