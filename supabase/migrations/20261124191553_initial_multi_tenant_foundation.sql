-- Fondation multi-tenant : profils, espaces de travail, Pages Facebook, réglages,
-- publications, journaux IA, statistiques, opportunités éditoriales.
-- Restitué à l'identique depuis l'historique de migrations du serveur Supabase.

create extension if not exists pgcrypto;

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create or replace function public.set_updated_at()
returns trigger language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.workspaces (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(trim(name)) between 1 and 120),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.workspace_members (
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'viewer' check (role in ('owner','admin','editor','viewer')),
  joined_at timestamptz not null default now(),
  primary key (workspace_id, user_id)
);
create index workspace_members_user_idx on public.workspace_members(user_id);

create table public.facebook_pages (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  meta_page_id text not null,
  page_name text not null,
  category text,
  picture_url text,
  is_active boolean not null default true,
  connected_by uuid references auth.users(id) on delete set null,
  connected_at timestamptz not null default now(),
  unique(workspace_id, meta_page_id)
);
create index facebook_pages_workspace_idx on public.facebook_pages(workspace_id);

create table public.publication_settings (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null unique references public.workspaces(id) on delete cascade,
  timezone text not null default 'Africa/Abidjan',
  language text not null default 'fr',
  frequency_per_week integer not null default 5 check (frequency_per_week between 0 and 50),
  preferred_days smallint[] not null default array[1,2,3,4,5]::smallint[],
  preferred_times time[] not null default array['08:00'::time,'12:00'::time,'18:00'::time],
  auto_publish boolean not null default false,
  require_approval boolean not null default true,
  default_tone text not null default 'professional',
  default_length text not null default 'medium' check (default_length in ('short','medium','long')),
  hashtags_enabled boolean not null default true,
  cta_enabled boolean not null default true,
  daily_post_limit integer not null default 3 check (daily_post_limit between 0 and 50),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.posts (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  facebook_page_id uuid references public.facebook_pages(id) on delete set null,
  created_by uuid references auth.users(id) on delete set null,
  title text,
  body text not null,
  content_type text not null default 'text' check (content_type in ('text','image','video','link','carousel')),
  status text not null default 'draft' check (status in ('draft','pending_approval','scheduled','publishing','published','failed','cancelled')),
  scheduled_at timestamptz,
  published_at timestamptz,
  meta_post_id text,
  error_message text,
  source text not null default 'manual' check (source in ('manual','ai','opportunity','recycled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index posts_workspace_status_idx on public.posts(workspace_id,status);
create index posts_schedule_idx on public.posts(scheduled_at) where status = 'scheduled';

create table public.ai_generation_logs (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  user_id uuid references auth.users(id) on delete set null,
  provider text not null default 'groq',
  model text,
  task_type text not null,
  input_tokens integer not null default 0 check (input_tokens >= 0),
  output_tokens integer not null default 0 check (output_tokens >= 0),
  latency_ms integer check (latency_ms is null or latency_ms >= 0),
  success boolean not null default true,
  error_code text,
  created_at timestamptz not null default now()
);
create index ai_logs_workspace_created_idx on public.ai_generation_logs(workspace_id,created_at desc);

create table public.page_insights (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  facebook_page_id uuid not null references public.facebook_pages(id) on delete cascade,
  metric_date date not null,
  metric_name text not null,
  metric_value numeric not null default 0,
  dimensions jsonb not null default '{}'::jsonb,
  collected_at timestamptz not null default now(),
  unique(facebook_page_id,metric_date,metric_name,dimensions)
);
create index page_insights_workspace_date_idx on public.page_insights(workspace_id,metric_date desc);

create table public.editorial_opportunities (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  facebook_page_id uuid references public.facebook_pages(id) on delete cascade,
  title text not null,
  rationale text,
  suggested_angle text,
  confidence numeric(5,2) check (confidence is null or confidence between 0 and 100),
  status text not null default 'new' check (status in ('new','accepted','dismissed','used')),
  generated_post_id uuid references public.posts(id) on delete set null,
  created_at timestamptz not null default now()
);
create index opportunities_workspace_status_idx on public.editorial_opportunities(workspace_id,status);

-- Every exposed table is protected by RLS.
alter table public.profiles enable row level security;
alter table public.workspaces enable row level security;
alter table public.workspace_members enable row level security;
alter table public.facebook_pages enable row level security;
alter table public.publication_settings enable row level security;
alter table public.posts enable row level security;
alter table public.ai_generation_logs enable row level security;
alter table public.page_insights enable row level security;
alter table public.editorial_opportunities enable row level security;

create policy "profiles_select_self" on public.profiles for select to authenticated using ((select auth.uid()) = id);
create policy "profiles_insert_self" on public.profiles for insert to authenticated with check ((select auth.uid()) = id);
create policy "profiles_update_self" on public.profiles for update to authenticated using ((select auth.uid()) = id) with check ((select auth.uid()) = id);

create policy "workspaces_select_members" on public.workspaces for select to authenticated
using (exists (select 1 from public.workspace_members m where m.workspace_id = id and m.user_id = (select auth.uid())));
create policy "workspaces_insert_creator" on public.workspaces for insert to authenticated
with check (created_by = (select auth.uid()));
create policy "workspaces_update_admins" on public.workspaces for update to authenticated
using (exists (select 1 from public.workspace_members m where m.workspace_id = id and m.user_id = (select auth.uid()) and m.role in ('owner','admin')))
with check (exists (select 1 from public.workspace_members m where m.workspace_id = id and m.user_id = (select auth.uid()) and m.role in ('owner','admin')));
create policy "workspaces_delete_owner" on public.workspaces for delete to authenticated
using (exists (select 1 from public.workspace_members m where m.workspace_id = id and m.user_id = (select auth.uid()) and m.role = 'owner'));

-- A user can see their own membership. Owners/admins can manage memberships within their workspace.
create policy "members_select_self" on public.workspace_members for select to authenticated
using (user_id = (select auth.uid()));
create policy "members_insert_owner_or_creator" on public.workspace_members for insert to authenticated
with check (
  (user_id = (select auth.uid()) and exists (select 1 from public.workspaces w where w.id = workspace_id and w.created_by = (select auth.uid()) and role = 'owner'))
  or exists (select 1 from public.workspace_members m where m.workspace_id = workspace_id and m.user_id = (select auth.uid()) and m.role in ('owner','admin'))
);
create policy "members_update_admins" on public.workspace_members for update to authenticated
using (exists (select 1 from public.workspace_members m where m.workspace_id = workspace_id and m.user_id = (select auth.uid()) and m.role in ('owner','admin')))
with check (exists (select 1 from public.workspace_members m where m.workspace_id = workspace_id and m.user_id = (select auth.uid()) and m.role in ('owner','admin')));
create policy "members_delete_admins" on public.workspace_members for delete to authenticated
using (exists (select 1 from public.workspace_members m where m.workspace_id = workspace_id and m.user_id = (select auth.uid()) and m.role in ('owner','admin')));

do $$
declare t text;
begin
  foreach t in array array['facebook_pages','publication_settings','posts','ai_generation_logs','page_insights','editorial_opportunities']
  loop
    execute format('create policy %I on public.%I for select to authenticated using (exists (select 1 from public.workspace_members m where m.workspace_id = workspace_id and m.user_id = (select auth.uid())));', t || '_select_workspace', t);
    execute format('create policy %I on public.%I for insert to authenticated with check (exists (select 1 from public.workspace_members m where m.workspace_id = workspace_id and m.user_id = (select auth.uid()) and m.role in (''owner'',''admin'',''editor'')));', t || '_insert_workspace', t);
    execute format('create policy %I on public.%I for update to authenticated using (exists (select 1 from public.workspace_members m where m.workspace_id = workspace_id and m.user_id = (select auth.uid()) and m.role in (''owner'',''admin'',''editor''))) with check (exists (select 1 from public.workspace_members m where m.workspace_id = workspace_id and m.user_id = (select auth.uid()) and m.role in (''owner'',''admin'',''editor'')));', t || '_update_workspace', t);
    execute format('create policy %I on public.%I for delete to authenticated using (exists (select 1 from public.workspace_members m where m.workspace_id = workspace_id and m.user_id = (select auth.uid()) and m.role in (''owner'',''admin'')));', t || '_delete_workspace', t);
  end loop;
end $$;

create trigger profiles_set_updated_at before update on public.profiles for each row execute function public.set_updated_at();
create trigger workspaces_set_updated_at before update on public.workspaces for each row execute function public.set_updated_at();
create trigger publication_settings_set_updated_at before update on public.publication_settings for each row execute function public.set_updated_at();
create trigger posts_set_updated_at before update on public.posts for each row execute function public.set_updated_at();

-- The browser/mobile client must never read or write provider credentials.
create table private.facebook_credentials (
  facebook_page_id uuid primary key references public.facebook_pages(id) on delete cascade,
  access_token_ciphertext text not null,
  token_expires_at timestamptz,
  updated_at timestamptz not null default now()
);
revoke all on private.facebook_credentials from public, anon, authenticated;
