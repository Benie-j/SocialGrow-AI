-- Remplace les sous-requêtes d'appartenance par private.is_workspace_member()
-- (security definer) pour éviter la récursion RLS et accélérer les politiques.
-- Restitué à l'identique depuis l'historique de migrations du serveur Supabase.

create or replace function private.is_workspace_member(_workspace_id uuid, _allowed_roles text[] default null)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.workspace_members m
    where m.workspace_id = _workspace_id
      and m.user_id = (select auth.uid())
      and (_allowed_roles is null or m.role = any(_allowed_roles))
  );
$$;
grant usage on schema private to authenticated;
grant execute on function private.is_workspace_member(uuid, text[]) to authenticated;

drop policy if exists "workspaces_select_members" on public.workspaces;
drop policy if exists "workspaces_update_admins" on public.workspaces;
drop policy if exists "workspaces_delete_owner" on public.workspaces;
create policy "workspaces_select_members" on public.workspaces for select to authenticated
using ((select private.is_workspace_member(id, null)));
create policy "workspaces_update_admins" on public.workspaces for update to authenticated
using ((select private.is_workspace_member(id, array['owner','admin'])))
with check ((select private.is_workspace_member(id, array['owner','admin'])));
create policy "workspaces_delete_owner" on public.workspaces for delete to authenticated
using ((select private.is_workspace_member(id, array['owner'])));

drop policy if exists "members_select_self" on public.workspace_members;
drop policy if exists "members_insert_owner_or_creator" on public.workspace_members;
drop policy if exists "members_update_admins" on public.workspace_members;
drop policy if exists "members_delete_admins" on public.workspace_members;
create policy "members_select_self_or_admin" on public.workspace_members for select to authenticated
using (user_id = (select auth.uid()) or (select private.is_workspace_member(workspace_id, array['owner','admin'])));
create policy "members_insert_owner_or_admin" on public.workspace_members for insert to authenticated
with check (
  (user_id = (select auth.uid()) and role = 'owner'
   and exists (select 1 from public.workspaces w where w.id = workspace_id and w.created_by = (select auth.uid())))
  or (select private.is_workspace_member(workspace_id, array['owner','admin']))
);
create policy "members_update_admins" on public.workspace_members for update to authenticated
using ((select private.is_workspace_member(workspace_id, array['owner','admin'])))
with check ((select private.is_workspace_member(workspace_id, array['owner','admin'])));
create policy "members_delete_admins" on public.workspace_members for delete to authenticated
using ((select private.is_workspace_member(workspace_id, array['owner','admin'])));

drop policy if exists "facebook_pages_select_workspace" on public.facebook_pages;
drop policy if exists "facebook_pages_insert_workspace" on public.facebook_pages;
drop policy if exists "facebook_pages_update_workspace" on public.facebook_pages;
drop policy if exists "facebook_pages_delete_workspace" on public.facebook_pages;
drop policy if exists "publication_settings_select_workspace" on public.publication_settings;
drop policy if exists "publication_settings_insert_workspace" on public.publication_settings;
drop policy if exists "publication_settings_update_workspace" on public.publication_settings;
drop policy if exists "publication_settings_delete_workspace" on public.publication_settings;
drop policy if exists "posts_select_workspace" on public.posts;
drop policy if exists "posts_insert_workspace" on public.posts;
drop policy if exists "posts_update_workspace" on public.posts;
drop policy if exists "posts_delete_workspace" on public.posts;
drop policy if exists "ai_generation_logs_select_workspace" on public.ai_generation_logs;
drop policy if exists "ai_generation_logs_insert_workspace" on public.ai_generation_logs;
drop policy if exists "ai_generation_logs_update_workspace" on public.ai_generation_logs;
drop policy if exists "ai_generation_logs_delete_workspace" on public.ai_generation_logs;
drop policy if exists "page_insights_select_workspace" on public.page_insights;
drop policy if exists "page_insights_insert_workspace" on public.page_insights;
drop policy if exists "page_insights_update_workspace" on public.page_insights;
drop policy if exists "page_insights_delete_workspace" on public.page_insights;
drop policy if exists "editorial_opportunities_select_workspace" on public.editorial_opportunities;
drop policy if exists "editorial_opportunities_insert_workspace" on public.editorial_opportunities;
drop policy if exists "editorial_opportunities_update_workspace" on public.editorial_opportunities;
drop policy if exists "editorial_opportunities_delete_workspace" on public.editorial_opportunities;

do $$
declare t text;
begin
  foreach t in array array['facebook_pages','publication_settings','posts','ai_generation_logs','page_insights','editorial_opportunities']
  loop
    execute format('create policy %I on public.%I for select to authenticated using ((select private.is_workspace_member(workspace_id, null)));', t || '_select_workspace', t);
    execute format('create policy %I on public.%I for insert to authenticated with check ((select private.is_workspace_member(workspace_id, array[''owner'',''admin'',''editor''])));', t || '_insert_workspace', t);
    execute format('create policy %I on public.%I for update to authenticated using ((select private.is_workspace_member(workspace_id, array[''owner'',''admin'',''editor'']))) with check ((select private.is_workspace_member(workspace_id, array[''owner'',''admin'',''editor''])));', t || '_update_workspace', t);
    execute format('create policy %I on public.%I for delete to authenticated using ((select private.is_workspace_member(workspace_id, array[''owner'',''admin''])));', t || '_delete_workspace', t);
  end loop;
end $$;
