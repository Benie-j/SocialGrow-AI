-- Pages Facebook : écriture réservée au backend.
--
-- Avant : un éditeur pouvait insérer/modifier/supprimer des lignes de
-- public.facebook_pages directement depuis le client (donc y créer une fausse Page).
-- Après : le client ne peut que LIRE. Toute connexion/déconnexion passe par les
-- Edge Functions (service_role) via deux fonctions SQL qu'aucun rôle client ne peut appeler.

-- 1. Le client ne peut plus écrire dans facebook_pages.
drop policy if exists "facebook_pages_insert_workspace" on public.facebook_pages;
drop policy if exists "facebook_pages_update_workspace" on public.facebook_pages;
drop policy if exists "facebook_pages_delete_workspace" on public.facebook_pages;
revoke insert, update, delete on public.facebook_pages from anon, authenticated;
-- La lecture reste ouverte aux membres de l'espace (politique « facebook_pages_select_workspace »).

-- 2. Connexion d'une Page (atomique) : une seule Page active par espace de travail.
--    Appelée uniquement par l'Edge Function facebook-connect-page.
create or replace function public.connect_facebook_page(
  p_workspace_id uuid,
  p_user_id uuid,
  p_meta_page_id text,
  p_page_name text,
  p_category text,
  p_picture_url text,
  p_token_ciphertext text,
  p_token_expires_at timestamptz
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_page_id uuid;
begin
  -- Défense en profondeur : l'appelant doit être propriétaire, admin ou éditeur.
  if not exists (
    select 1 from public.workspace_members m
    where m.workspace_id = p_workspace_id
      and m.user_id = p_user_id
      and m.role in ('owner', 'admin', 'editor')
  ) then
    raise exception 'Droits insuffisants pour connecter une Page' using errcode = '42501';
  end if;

  if coalesce(trim(p_meta_page_id), '') = '' or coalesce(trim(p_page_name), '') = '' then
    raise exception 'Page invalide' using errcode = '22023';
  end if;

  if coalesce(p_token_ciphertext, '') = '' then
    raise exception 'Jeton manquant' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_workspace_id::text, 1));

  -- Les autres Pages de l'espace sont désactivées et leurs identifiants effacés.
  delete from private.facebook_credentials c
  using public.facebook_pages p
  where c.facebook_page_id = p.id
    and p.workspace_id = p_workspace_id
    and p.meta_page_id <> p_meta_page_id;

  update public.facebook_pages
  set is_active = false
  where workspace_id = p_workspace_id
    and meta_page_id <> p_meta_page_id
    and is_active;

  insert into public.facebook_pages
    (workspace_id, meta_page_id, page_name, category, picture_url, is_active, connected_by, connected_at)
  values
    (p_workspace_id, p_meta_page_id, p_page_name, p_category, p_picture_url, true, p_user_id, now())
  on conflict (workspace_id, meta_page_id) do update
    set page_name = excluded.page_name,
        category = excluded.category,
        picture_url = excluded.picture_url,
        is_active = true,
        connected_by = excluded.connected_by,
        connected_at = now()
  returning id into v_page_id;

  insert into private.facebook_credentials
    (facebook_page_id, access_token_ciphertext, token_expires_at, updated_at)
  values
    (v_page_id, p_token_ciphertext, p_token_expires_at, now())
  on conflict (facebook_page_id) do update
    set access_token_ciphertext = excluded.access_token_ciphertext,
        token_expires_at = excluded.token_expires_at,
        updated_at = now();

  return v_page_id;
end;
$$;

-- 3. Déconnexion : désactive la Page active et efface ses identifiants.
create or replace function public.disconnect_facebook_page(
  p_workspace_id uuid,
  p_user_id uuid
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if not exists (
    select 1 from public.workspace_members m
    where m.workspace_id = p_workspace_id
      and m.user_id = p_user_id
      and m.role in ('owner', 'admin', 'editor')
  ) then
    raise exception 'Droits insuffisants pour déconnecter la Page' using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_workspace_id::text, 1));

  delete from private.facebook_credentials c
  using public.facebook_pages p
  where c.facebook_page_id = p.id
    and p.workspace_id = p_workspace_id;

  update public.facebook_pages
  set is_active = false
  where workspace_id = p_workspace_id
    and is_active;
  get diagnostics v_count = row_count;

  return v_count;
end;
$$;

-- 4. Seul le backend (service_role) peut appeler ces fonctions.
revoke all on function public.connect_facebook_page(uuid, uuid, text, text, text, text, text, timestamptz)
  from public, anon, authenticated;
revoke all on function public.disconnect_facebook_page(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.connect_facebook_page(uuid, uuid, text, text, text, text, text, timestamptz)
  to service_role;
grant execute on function public.disconnect_facebook_page(uuid, uuid)
  to service_role;
