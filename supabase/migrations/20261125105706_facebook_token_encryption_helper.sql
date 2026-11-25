-- Chiffrement d'un jeton de Page avec la clé du Vault, dans le même format que celui
-- attendu par public.connect_facebook_page et lu par public.get_facebook_page_token
-- (base64 de pgp_sym_encrypt). La clé ne quitte jamais la base de données.
-- Appelable uniquement par le backend (service_role).
-- Restitué à l'identique depuis l'historique de migrations du serveur Supabase.
create or replace function public.encrypt_facebook_token(_plain text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  encryption_key text := private.facebook_token_key();
begin
  if encryption_key is null then
    raise exception 'Encryption key is not configured' using errcode = '55000';
  end if;

  if coalesce(trim(_plain), '') = '' then
    raise exception 'Empty token' using errcode = '22023';
  end if;

  return encode(extensions.pgp_sym_encrypt(_plain, encryption_key), 'base64');
end;
$$;

revoke all on function public.encrypt_facebook_token(text) from public, anon, authenticated;
grant execute on function public.encrypt_facebook_token(text) to service_role;
