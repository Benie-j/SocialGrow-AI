-- Brouillons automatiques : au plus 3 fois par jour, un appel planifié demande à
-- l'assistant (Groq compound, avec recherche web) de trouver un thème vérifiable,
-- de le rédiger avec ses sources et de proposer une image libre de droits.
-- Le résultat est TOUJOURS un brouillon à relire : rien n'est publié sans validation.

alter table public.posts
  add column if not exists image_url text
    check (image_url is null or (char_length(image_url) <= 2000 and image_url ~ '^https://')),
  add column if not exists image_credit text
    check (image_credit is null or char_length(image_credit) <= 500),
  add column if not exists source_urls jsonb not null default '[]'::jsonb
    check (jsonb_typeof(source_urls) = 'array');

create table if not exists public.ai_autopost_settings (
  workspace_id uuid primary key references public.workspaces(id) on delete cascade,
  enabled boolean not null default false,
  runs_per_day smallint not null default 3 check (runs_per_day between 1 and 3),
  bold_titles boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.ai_autopost_runs (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  run_date date not null default (now() at time zone 'utc')::date,
  status text not null default 'started' check (status in ('started','drafted','rejected','failed')),
  topic text,
  post_id uuid references public.posts(id) on delete set null,
  error_code text,
  created_at timestamptz not null default now()
);
create index if not exists ai_autopost_runs_ws_day_idx on public.ai_autopost_runs(workspace_id, run_date);

alter table public.ai_autopost_settings enable row level security;
alter table public.ai_autopost_runs enable row level security;

create policy ai_autopost_settings_select on public.ai_autopost_settings
  for select to authenticated using ((select private.is_workspace_member(workspace_id, null)));
create policy ai_autopost_settings_write on public.ai_autopost_settings
  for all to authenticated
  using ((select private.is_workspace_member(workspace_id, array['owner','admin'])))
  with check ((select private.is_workspace_member(workspace_id, array['owner','admin'])));
create policy ai_autopost_runs_select on public.ai_autopost_runs
  for select to authenticated using ((select private.is_workspace_member(workspace_id, null)));

grant select, insert, update on public.ai_autopost_settings to authenticated;
grant select on public.ai_autopost_runs to authenticated;

create trigger ai_autopost_settings_set_updated_at
  before update on public.ai_autopost_settings
  for each row execute function public.set_updated_at();

-- Réserve une exécution du jour (plafond dur, même si le travail planifié est appelé deux fois).
create or replace function public.claim_ai_autopost_run(_workspace_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_limit smallint;
  v_count integer;
  v_id uuid;
begin
  perform pg_advisory_xact_lock(hashtext('ai_autopost:' || _workspace_id::text));
  select runs_per_day into v_limit from public.ai_autopost_settings
    where workspace_id = _workspace_id and enabled;
  if v_limit is null then return null; end if;
  select count(*) into v_count from public.ai_autopost_runs
    where workspace_id = _workspace_id and run_date = (now() at time zone 'utc')::date;
  if v_count >= least(v_limit, 3) then return null; end if;
  insert into public.ai_autopost_runs(workspace_id) values (_workspace_id) returning id into v_id;
  return v_id;
end;
$$;
revoke all on function public.claim_ai_autopost_run(uuid) from public, anon, authenticated;
grant execute on function public.claim_ai_autopost_run(uuid) to service_role;

-- Travail planifié : 3 créneaux par jour (UTC) ; la fonction Edge applique le plafond.
create or replace function private.run_ai_autopost()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_url text;
  v_secret text;
begin
  if not exists (select 1 from public.ai_autopost_settings where enabled) then return; end if;
  select decrypted_secret into v_url from vault.decrypted_secrets where name = 'project_url';
  select decrypted_secret into v_secret from vault.decrypted_secrets where name = 'cron_secret';
  if coalesce(v_url, '') = '' or coalesce(v_secret, '') = '' then return; end if;
  perform net.http_post(
    url := rtrim(v_url, '/') || '/functions/v1/ai-autopost',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-cron-secret', v_secret),
    body := '{}'::jsonb,
    timeout_milliseconds := 120000
  );
end;
$$;
revoke all on function private.run_ai_autopost() from public, anon, authenticated;

do $$
begin
  perform cron.unschedule('ai-autopost');
exception when others then
  null;
end
$$;

select cron.schedule('ai-autopost', '0 7,12,18 * * *', $cron$ select private.run_ai_autopost(); $cron$);
