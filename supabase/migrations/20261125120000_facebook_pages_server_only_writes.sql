-- Pages Facebook : seul le serveur peut en créer ou en modifier.
-- Avant : un éditeur pouvait insérer une fausse Page (INSERT/UPDATE/DELETE accordés
-- au rôle authenticated). Désormais le client ne fait que lire ; la connexion passe
-- par l'Edge Function facebook-connect-page, qui vérifie auprès de Meta que
-- l'utilisateur gère bien la Page, et la déconnexion par une fonction dédiée.

-- 1. Le client n'a plus aucun droit d'écriture sur la table.
revoke insert, update, delete on public.facebook_pages from authenticated;

drop policy if exists "facebook_pages_insert_workspace" on public.facebook_pages;
drop policy if exists "facebook_pages_update_workspace" on public.facebook_pages;
drop policy if exists "facebook_pages_delete_workspace" on public.facebook_pages;
-- La politique de lecture (facebook_pages_select_workspace) est conservée.

-- 2. Connexion d'une Page : réservée au serveur (rôle service_role).
create or replace function public.connect_facebook_page(
  _workspace_id uuid,
  _user_id uuid,
  _meta_page_id text,
  _page_name text,
  _category text,
  _picture_url text,
  _token_ciphertext text,
  _token_expires_at timestamptz default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  page_row_id uuid;
begin
  if _user_id is null
     or coalesce(trim(_meta_page_id), '') = ''
     or coalesce(trim(_page_name), '') = ''
     or coalesce(_token_ciphertext, '') = '' then
    raise exception 'Invalid Facebook page data' using errcode = '22023';
  end if;

  -- Seuls les propriétaires et administrateurs connectent une Page.
  if not exists (
    select 1
    from public.workspace_members m
    where m.workspace_id = _workspace_id
      and m.user_id = _user_id
      and m.role in ('owner', 'admin')
  ) then
    raise exception 'Not allowed to connect a Facebook page' using errcode = '42501';
  end if;

  insert into public.facebook_pages
    (workspace_id, meta_page_id, page_name, category, picture_url, is_active, connected_by, connected_at)
  values
    (_workspace_id, trim(_meta_page_id), trim(_page_name), nullif(trim(coalesce(_category, '')), ''),
     nullif(trim(coalesce(_picture_url, '')), ''), true, _user_id, now())
  on conflict (workspace_id, meta_page_id) do update
    set page_name = excluded.page_name,
        category = excluded.category,
        picture_url = excluded.picture_url,
        is_active = true,
        connected_by = excluded.connected_by,
        connected_at = now()
  returning id into page_row_id;

  insert into private.facebook_credentials
    (facebook_page_id, access_token_ciphertext, token_expires_at, updated_at)
  values
    (page_row_id, _token_ciphertext, _token_expires_at, now())
  on conflict (facebook_page_id) do update
    set access_token_ciphertext = excluded.access_token_ciphertext,
        token_expires_at = excluded.token_expires_at,
        updated_at = now();

  return page_row_id;
end;
$$;

revoke all on function public.connect_facebook_page(uuid, uuid, text, text, text, text, text, timestamptz)
  from public, anon, authenticated;
grant execute on function public.connect_facebook_page(uuid, uuid, text, text, text, text, text, timestamptz)
  to service_role;

-- 3. Déconnexion : propriétaires et administrateurs. La Page est désactivée
-- (l'historique des publications est conservé) et son jeton est supprimé.
create or replace function public.disconnect_facebook_page(_page_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_workspace uuid;
begin
  select workspace_id into target_workspace
  from public.facebook_pages
  where id = _page_id;

  if target_workspace is null
     or not (select private.is_workspace_member(target_workspace, array['owner', 'admin'])) then
    raise exception 'Not allowed to disconnect this Facebook page' using errcode = '42501';
  end if;

  delete from private.facebook_credentials where facebook_page_id = _page_id;
  update public.facebook_pages set is_active = false where id = _page_id;
end;
$$;

revoke all on function public.disconnect_facebook_page(uuid) from public, anon;
grant execute on function public.disconnect_facebook_page(uuid) to authenticated;
