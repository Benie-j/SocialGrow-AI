-- Notifications push (Firebase Cloud Messaging) : appareils enregistrés et
-- déclencheur d'envoi à chaque nouvelle notification.

-- 1. Appareils qui reçoivent les push. L'écriture passe par l'Edge Function
--    `register-push-token` (elle déplace un jeton d'un compte à l'autre si un
--    téléphone change d'utilisateur) : le client ne peut que lire les siens.
create table public.device_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  token text not null unique check (char_length(token) between 20 and 4096),
  platform text not null default 'android' check (platform in ('android')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index device_tokens_user_id_idx on public.device_tokens (user_id);

alter table public.device_tokens enable row level security;

revoke all on public.device_tokens from anon, authenticated;
grant select (id, user_id, platform, created_at, updated_at)
  on public.device_tokens to authenticated;

create policy device_tokens_select on public.device_tokens
  for select to authenticated
  using (user_id = (select auth.uid()));

-- 2. Une notification n'est poussée qu'une seule fois : l'Edge Function la
--    « réclame » de façon atomique. Les notifications existantes ne sont pas
--    renvoyées.
alter table public.notifications add column push_claimed_at timestamptz;

update public.notifications
   set push_claimed_at = created_at
 where push_claimed_at is null;

-- 3. À chaque nouvelle notification, on appelle l'Edge Function d'envoi.
--    L'appel est asynchrone (pg_net) et ne bloque jamais l'insertion.
create or replace function private.notify_push()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  begin
    perform net.http_post(
      url := 'https://ismatpttxrsbqtravgkr.supabase.co/functions/v1/send-push',
      headers := jsonb_build_object('Content-Type', 'application/json'),
      body := jsonb_build_object('notification_id', new.id),
      timeout_milliseconds := 5000
    );
  exception when others then
    null;
  end;
  return new;
end;
$$;

revoke all on function private.notify_push() from public, anon, authenticated;

create trigger notifications_push
  after insert on public.notifications
  for each row execute function private.notify_push();
