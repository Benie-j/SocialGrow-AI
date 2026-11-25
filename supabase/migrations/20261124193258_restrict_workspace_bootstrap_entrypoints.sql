-- Supprime l'insertion directe d'espaces par le client et interdit l'appel
-- direct du déclencheur d'inscription.
-- Restitué à l'identique depuis l'historique de migrations du serveur Supabase.

drop policy if exists "workspaces_insert_creator" on public.workspaces;
revoke all on function private.handle_new_user() from public, anon, authenticated;
