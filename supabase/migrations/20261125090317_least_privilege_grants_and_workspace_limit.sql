-- 1. Privilèges minimaux : la RLS filtre les lignes, les GRANT limitent les opérations.
-- Retire les droits par défaut de Supabase (dont TRUNCATE, qui contourne la RLS).
revoke all on all tables in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;

-- Les futurs objets du schéma public n'auront aucun droit implicite :
-- chaque migration doit accorder explicitement ce qui est nécessaire.
alter default privileges for role postgres in schema public revoke all on tables from anon, authenticated;
alter default privileges for role postgres in schema public revoke all on sequences from anon, authenticated;
alter default privileges for role postgres in schema public revoke execute on functions from public, anon, authenticated;

-- Matrice alignée sur les politiques RLS existantes.
grant select, insert, update on public.profiles to authenticated;
grant select, update, delete on public.workspaces to authenticated;
grant select on public.workspace_members to authenticated;
grant select on public.workspace_invitations to authenticated;
grant select, insert, update, delete on public.facebook_pages to authenticated;
grant select, insert, update, delete on public.publication_settings to authenticated;
grant select, insert, update, delete on public.posts to authenticated;
grant select, insert, update, delete on public.ai_generation_logs to authenticated;
grant select, insert, update, delete on public.page_insights to authenticated;
grant select, insert, update, delete on public.editorial_opportunities to authenticated;
grant select, insert, delete on public.topic_history to authenticated;

-- 2. Fonctions : plus d'exécution par le rôle anonyme.
revoke all on function private.is_workspace_member(uuid, text[]) from public, anon;
grant execute on function private.is_workspace_member(uuid, text[]) to authenticated;
revoke all on function public.set_updated_at() from public, anon, authenticated;

-- 3. create_workspace : limite par utilisateur contre la création en masse.
-- Le compteur inclut l'espace créé à l'inscription. Limite modifiable ici.
create or replace function public.create_workspace(_name text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  new_workspace_id uuid;
  cleaned_name text := trim(coalesce(_name, ''));
  owned_count integer;
  max_workspaces constant integer := 5;
begin
  if caller_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;

  if char_length(cleaned_name) < 1 or char_length(cleaned_name) > 120 then
    raise exception 'Workspace name must contain 1 to 120 characters' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(caller_id::text, 0));

  select count(*) into owned_count
  from public.workspaces
  where created_by = caller_id;

  if owned_count >= max_workspaces then
    raise exception 'Workspace limit reached (%)', max_workspaces using errcode = '53400';
  end if;

  insert into public.workspaces (name, created_by)
  values (cleaned_name, caller_id)
  returning id into new_workspace_id;

  insert into public.workspace_members (workspace_id, user_id, role)
  values (new_workspace_id, caller_id, 'owner');

  insert into public.publication_settings (workspace_id)
  values (new_workspace_id);

  return new_workspace_id;
end;
$$;

-- 4. Index sur les clés étrangères non couvertes.
create index if not exists ai_generation_logs_user_id_idx on public.ai_generation_logs (user_id);
create index if not exists editorial_opportunities_facebook_page_id_idx on public.editorial_opportunities (facebook_page_id);
create index if not exists editorial_opportunities_generated_post_id_idx on public.editorial_opportunities (generated_post_id);
create index if not exists facebook_pages_connected_by_idx on public.facebook_pages (connected_by);
create index if not exists posts_created_by_idx on public.posts (created_by);
create index if not exists posts_facebook_page_id_idx on public.posts (facebook_page_id);
create index if not exists topic_history_post_id_idx on public.topic_history (post_id);
create index if not exists workspace_invitations_invited_by_idx on public.workspace_invitations (invited_by);
create index if not exists workspaces_created_by_idx on public.workspaces (created_by);
