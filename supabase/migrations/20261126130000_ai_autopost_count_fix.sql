-- Les exécutions échouées (ex. refus de l'API avant toute génération) ne comptent
-- plus dans le plafond de 3 brouillons par jour.
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
    where workspace_id = _workspace_id
      and run_date = (now() at time zone 'utc')::date
      and status <> 'failed';
  if v_count >= least(v_limit, 3) then return null; end if;
  insert into public.ai_autopost_runs(workspace_id) values (_workspace_id) returning id into v_id;
  return v_id;
end;
$$;
revoke all on function public.claim_ai_autopost_run(uuid) from public, anon, authenticated;
grant execute on function public.claim_ai_autopost_run(uuid) to service_role;
