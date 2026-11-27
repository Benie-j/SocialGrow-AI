-- Collecte quotidienne des statistiques de Page auprès de Meta (table page_insights).
-- Une ligne par Page résume la dernière collecte (réussite ou raison de l'échec).

create table if not exists public.page_insights_sync (
  facebook_page_id uuid primary key references public.facebook_pages(id) on delete cascade,
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  last_attempt_at timestamptz not null default now(),
  last_success_at timestamptz,
  last_error text check (last_error is null or char_length(last_error) <= 500),
  metrics_ok text[] not null default '{}'
);

alter table public.page_insights_sync enable row level security;
create policy page_insights_sync_select on public.page_insights_sync
  for select to authenticated using ((select private.is_workspace_member(workspace_id, null)));
grant select on public.page_insights_sync to authenticated;

create or replace function private.run_facebook_insights_sync()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_url text;
  v_secret text;
begin
  if not exists (select 1 from public.facebook_pages where is_active) then return; end if;
  select decrypted_secret into v_url from vault.decrypted_secrets where name = 'project_url';
  select decrypted_secret into v_secret from vault.decrypted_secrets where name = 'cron_secret';
  if coalesce(v_url, '') = '' or coalesce(v_secret, '') = '' then return; end if;
  perform net.http_post(
    url := rtrim(v_url, '/') || '/functions/v1/facebook-sync-insights',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-cron-secret', v_secret),
    body := '{}'::jsonb,
    timeout_milliseconds := 60000
  );
end;
$$;
revoke all on function private.run_facebook_insights_sync() from public, anon, authenticated;

do $$
begin
  perform cron.unschedule('facebook-insights-sync');
exception when others then
  null;
end
$$;

-- Meta actualise la plupart des mesures toutes les 24 h : une collecte par jour suffit.
select cron.schedule('facebook-insights-sync', '30 6 * * *', $cron$ select private.run_facebook_insights_sync(); $cron$);
