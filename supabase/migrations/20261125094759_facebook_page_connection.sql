-- Connexion d'une Page Facebook : les jetons de Page sont chiffrés côté base
-- (clé dans Supabase Vault) et écrits uniquement par le serveur (Edge Function).
-- Restitué à l'identique depuis l'historique de migrations du serveur Supabase.

-- 1. Clé de chiffrement, générée dans la base : jamais dans Git ni dans une conversation.
do $$
begin
  if not exists (select 1 from vault.secrets where name = 'facebook_token_key') then
    perform vault.create_secret(
      encode(extensions.gen_random_bytes(32), 'hex'),
      'facebook_token_key',
      'Clé de chiffrement des jetons de Pages Facebook'
    );
  end if;
end $$;

create or replace function private.facebook_token_key()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select decrypted_secret from vault.decrypted_secrets where name = 'facebook_token_key' limit 1;
$$;
revoke all on function private.facebook_token_key() from public, anon, authenticated;

-- 2. Enregistrement d'une Page et de son jeton (appelé uniquement par l'Edge Function).
create or replace function public.store_facebook_page(
  _workspace_id uuid,
  _meta_page_id text,
  _page_name text,
  _category text,
  _picture_url text,
  _connected_by uuid,
  _access_token text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  page_id uuid;
  encryption_key text := private.facebook_token_key();
begin
  if encryption_key is null then
    raise exception 'Encryption key is not configured' using errcode = '55000';
  end if;

  if coalesce(trim(_access_token), '') = ''
     or coalesce(trim(_meta_page_id), '') = ''
     or coalesce(trim(_page_name), '') = '' then
    raise exception 'Invalid page data' using errcode = '22023';
  end if;

  if not exists (
    select 1
    from public.workspace_members m
    where m.workspace_id = _workspace_id
      and m.user_id = _connected_by
      and m.role in ('owner', 'admin')
  ) then
    raise exception 'Not allowed to connect a page to this workspace' using errcode = '42501';
  end if;

  insert into public.facebook_pages
    (workspace_id, meta_page_id, page_name, category, picture_url, is_active, connected_by, connected_at)
  values
    (_workspace_id, trim(_meta_page_id), trim(_page_name), nullif(trim(coalesce(_category, '')), ''),
     nullif(trim(coalesce(_picture_url, '')), ''), true, _connected_by, now())
  on conflict (workspace_id, meta_page_id) do update
    set page_name = excluded.page_name,
        category = excluded.category,
        picture_url = excluded.picture_url,
        is_active = true,
        connected_by = excluded.connected_by,
        connected_at = now()
  returning id into page_id;

  insert into private.facebook_credentials
    (facebook_page_id, access_token_ciphertext, token_expires_at, updated_at)
  values
    (page_id, encode(extensions.pgp_sym_encrypt(_access_token, encryption_key), 'base64'), null, now())
  on conflict (facebook_page_id) do update
    set access_token_ciphertext = excluded.access_token_ciphertext,
        token_expires_at = null,
        updated_at = now();

  return page_id;
end;
$$;
revoke all on function public.store_facebook_page(uuid, text, text, text, text, uuid, text)
  from public, anon, authenticated;
grant execute on function public.store_facebook_page(uuid, text, text, text, text, uuid, text)
  to service_role;

-- 3. Lecture du jeton déchiffré (futur module de publication, côté serveur uniquement).
create or replace function public.get_facebook_page_token(_facebook_page_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  encryption_key text := private.facebook_token_key();
  ciphertext text;
begin
  if encryption_key is null then
    raise exception 'Encryption key is not configured' using errcode = '55000';
  end if;

  select c.access_token_ciphertext into ciphertext
  from private.facebook_credentials c
  join public.facebook_pages p on p.id = c.facebook_page_id
  where c.facebook_page_id = _facebook_page_id and p.is_active;

  if ciphertext is null then
    return null;
  end if;

  return extensions.pgp_sym_decrypt(decode(ciphertext, 'base64'), encryption_key);
end;
$$;
revoke all on function public.get_facebook_page_token(uuid) from public, anon, authenticated;
grant execute on function public.get_facebook_page_token(uuid) to service_role;

-- 4. Le client ne peut plus créer ni modifier une Page : seules les fonctions serveur le font.
-- La lecture et la déconnexion (suppression par un admin, jeton supprimé en cascade) restent permises.
revoke insert, update on public.facebook_pages from authenticated;
