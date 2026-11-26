-- Notifications dans l'app : préférences par membre + historique des alertes.
-- Les alertes sont créées par des déclencheurs (publication réussie/échouée,
-- brouillon IA prêt, problème de collecte Facebook), jamais par l'app.

create table if not exists public.notification_preferences (
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  publish_success boolean not null default true,
  publish_failure boolean not null default true,
  ai_draft_ready boolean not null default true,
  facebook_issue boolean not null default true,
  updated_at timestamptz not null default now(),
  primary key (workspace_id, user_id)
);

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null check (kind in ('publish_success','publish_failure','ai_draft_ready','facebook_issue')),
  title text not null check (char_length(title) <= 120),
  body text check (body is null or char_length(body) <= 300),
  post_id uuid references public.posts(id) on delete set null,
  created_at timestamptz not null default now(),
  read_at timestamptz
);
create index if not exists notifications_user_created_idx on public.notifications(user_id, created_at desc);

alter table public.notification_preferences enable row level security;
alter table public.notifications enable row level security;

create policy notification_preferences_select on public.notification_preferences
  for select to authenticated
  using (user_id = (select auth.uid()) and (select private.is_workspace_member(workspace_id, null)));
create policy notification_preferences_insert on public.notification_preferences
  for insert to authenticated
  with check (user_id = (select auth.uid()) and (select private.is_workspace_member(workspace_id, null)));
create policy notification_preferences_update on public.notification_preferences
  for update to authenticated
  using (user_id = (select auth.uid()) and (select private.is_workspace_member(workspace_id, null)))
  with check (user_id = (select auth.uid()) and (select private.is_workspace_member(workspace_id, null)));

create policy notifications_select on public.notifications
  for select to authenticated using (user_id = (select auth.uid()));
create policy notifications_update on public.notifications
  for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

grant select, insert, update on public.notification_preferences to authenticated;
grant select on public.notifications to authenticated;
grant update (read_at) on public.notifications to authenticated;

create trigger notification_preferences_set_updated_at
  before update on public.notification_preferences
  for each row execute function public.set_updated_at();

-- Une alerte par membre (owner, admin, editor) dont la préférence l'autorise.
create or replace function private.notify_workspace(
  _workspace_id uuid, _kind text, _title text, _body text, _post_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.notifications(workspace_id, user_id, kind, title, body, post_id)
  select m.workspace_id, m.user_id, _kind, left(_title, 120), left(_body, 300), _post_id
  from public.workspace_members m
  left join public.notification_preferences np
    on np.workspace_id = m.workspace_id and np.user_id = m.user_id
  where m.workspace_id = _workspace_id
    and m.role in ('owner', 'admin', 'editor')
    and case _kind
      when 'publish_success' then coalesce(np.publish_success, true)
      when 'publish_failure' then coalesce(np.publish_failure, true)
      when 'ai_draft_ready' then coalesce(np.ai_draft_ready, true)
      when 'facebook_issue' then coalesce(np.facebook_issue, true)
      else false
    end;
end;
$$;
revoke all on function private.notify_workspace(uuid, text, text, text, uuid) from public, anon, authenticated;

create or replace function private.trg_notify_post_status()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status is not distinct from old.status then return new; end if;
  if new.status = 'published' then
    perform private.notify_workspace(new.workspace_id, 'publish_success',
      'Publication envoyée', coalesce(nullif(new.title, ''), 'Ta publication est en ligne.'), new.id);
  elsif new.status = 'failed' then
    perform private.notify_workspace(new.workspace_id, 'publish_failure',
      'Publication échouée', coalesce(nullif(new.error_message, ''), 'La publication n''a pas pu partir.'), new.id);
  end if;
  return new;
end;
$$;
revoke all on function private.trg_notify_post_status() from public, anon, authenticated;

create trigger posts_notify_status
  after update of status on public.posts
  for each row execute function private.trg_notify_post_status();

create or replace function private.trg_notify_ai_draft()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status = 'drafted' and old.status is distinct from 'drafted' then
    perform private.notify_workspace(new.workspace_id, 'ai_draft_ready',
      'Nouveau brouillon prêt', coalesce(nullif(new.topic, ''), 'Relis-le dans le Studio avant de publier.'), new.post_id);
  end if;
  return new;
end;
$$;
revoke all on function private.trg_notify_ai_draft() from public, anon, authenticated;

create trigger ai_autopost_runs_notify_draft
  after update of status on public.ai_autopost_runs
  for each row execute function private.trg_notify_ai_draft();

-- Problème de collecte des statistiques : une alerte seulement quand le message change.
create or replace function private.trg_notify_insights_issue()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.last_error is null or new.last_error like 'Meta n''a renvoyé aucune donnée%' then return new; end if;
  if tg_op = 'UPDATE' and new.last_error is not distinct from old.last_error then return new; end if;
  perform private.notify_workspace(new.workspace_id, 'facebook_issue',
    'Statistiques Facebook indisponibles', new.last_error, null);
  return new;
end;
$$;
revoke all on function private.trg_notify_insights_issue() from public, anon, authenticated;

create trigger page_insights_sync_notify_issue
  after insert or update of last_error on public.page_insights_sync
  for each row execute function private.trg_notify_insights_issue();

-- Historique conservé 60 jours.
do $$
begin
  perform cron.unschedule('notifications-purge');
exception when others then
  null;
end
$$;
select cron.schedule('notifications-purge', '15 3 * * *',
  $cron$ delete from public.notifications where created_at < now() - interval '60 days' $cron$);
