-- Publication programmée : un travail planifié (toutes les minutes) appelle la
-- fonction Edge `publish-scheduled-posts` quand au moins une publication est
-- arrivée à échéance. Aucun secret n'est stocké dans ce dépôt : le secret
-- partagé est généré dans le coffre (Vault) de la base, et l'URL du projet y
-- est enregistrée à part (secret `project_url`).

create extension if not exists pg_cron;
create extension if not exists pg_net with schema extensions;

-- Secret partagé entre le travail planifié et la fonction Edge (créé une fois).
do $$
begin
  if not exists (select 1 from vault.secrets where name = 'cron_secret') then
    perform vault.create_secret(
      replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''),
      'cron_secret',
      'Secret partagé pour publish-scheduled-posts'
    );
  end if;
end
$$;

-- Vérification faite côté base : la fonction Edge n'a jamais à connaître le secret.
create or replace function public.verify_cron_secret(_secret text)
returns boolean
language sql
security definer
set search_path = ''
as $$
  select coalesce(_secret, '') <> '' and exists (
    select 1 from vault.decrypted_secrets
    where name = 'cron_secret' and decrypted_secret = _secret
  );
$$;

revoke all on function public.verify_cron_secret(text) from public, anon, authenticated;
grant execute on function public.verify_cron_secret(text) to service_role;

-- Appelle la fonction Edge seulement s'il y a quelque chose à faire :
-- publication échue, ou publication restée bloquée « en cours » depuis 15 min.
create or replace function private.run_scheduled_publishing()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_url text;
  v_secret text;
begin
  if not exists (
    select 1 from public.posts
    where (status = 'scheduled' and scheduled_at <= now())
       or (status = 'publishing' and updated_at < now() - interval '15 minutes')
  ) then
    return;
  end if;

  select decrypted_secret into v_url from vault.decrypted_secrets where name = 'project_url';
  select decrypted_secret into v_secret from vault.decrypted_secrets where name = 'cron_secret';
  if coalesce(v_url, '') = '' or coalesce(v_secret, '') = '' then
    return;
  end if;

  perform net.http_post(
    url := rtrim(v_url, '/') || '/functions/v1/publish-scheduled-posts',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-cron-secret', v_secret),
    body := '{}'::jsonb,
    timeout_milliseconds := 30000
  );
end;
$$;

revoke all on function private.run_scheduled_publishing() from public, anon, authenticated;

do $$
begin
  perform cron.unschedule('publish-scheduled-posts');
exception when others then
  null;
end
$$;

select cron.schedule(
  'publish-scheduled-posts',
  '* * * * *',
  $cron$ select private.run_scheduled_publishing(); $cron$
);
