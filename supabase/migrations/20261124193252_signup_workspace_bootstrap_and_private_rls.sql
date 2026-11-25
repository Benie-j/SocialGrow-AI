-- Verrouille le magasin d'identifiants privés, supprime les politiques client
-- d'écriture sur workspace_members (anti-escalade de rôle), crée le déclencheur
-- d'inscription (profil + espace + owner + réglages), create_workspace et les invitations.
-- Restitué à l'identique depuis l'historique de migrations du serveur Supabase.

-- Lock down the private credential store. Backend service-role operations bypass RLS;
-- browser/mobile roles receive no direct privileges.
alter table private.facebook_credentials enable row level security;
revoke all on table private.facebook_credentials from public, anon, authenticated;

-- Prevent direct client-side role escalation. Membership changes will go through
-- trusted backend workflows / narrowly scoped RPCs.
drop policy if exists "members_insert_owner_or_admin" on public.workspace_members;
drop policy if exists "members_update_admins" on public.workspace_members;
drop policy if exists "members_delete_admins" on public.workspace_members;

-- Create the user's profile and first private workspace at account creation.
create or replace function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  new_workspace_id uuid;
  display_name_value text;
begin
  display_name_value := coalesce(
    nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''),
    nullif(trim(new.raw_user_meta_data ->> 'name'), ''),
    split_part(coalesce(new.email, 'Utilisateur'), '@', 1)
  );

  insert into public.profiles (id, display_name, avatar_url)
  values (
    new.id,
    display_name_value,
    nullif(new.raw_user_meta_data ->> 'avatar_url', '')
  )
  on conflict (id) do nothing;

  insert into public.workspaces (name, created_by)
  values ('Mon espace', new.id)
  returning id into new_workspace_id;

  insert into public.workspace_members (workspace_id, user_id, role)
  values (new_workspace_id, new.id, 'owner')
  on conflict (workspace_id, user_id) do nothing;

  insert into public.publication_settings (workspace_id)
  values (new_workspace_id)
  on conflict (workspace_id) do nothing;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created_socialgrow on auth.users;
create trigger on_auth_user_created_socialgrow
after insert on auth.users
for each row execute function private.handle_new_user();

-- Allow authenticated users to create additional workspaces safely.
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
begin
  if caller_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;

  if char_length(cleaned_name) < 1 or char_length(cleaned_name) > 120 then
    raise exception 'Workspace name must contain 1 to 120 characters' using errcode = '22023';
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
revoke all on function public.create_workspace(text) from public, anon;
grant execute on function public.create_workspace(text) to authenticated;

-- Add an invitation ledger; actual invitations will be sent by a server-side
-- Edge Function using Supabase Auth Admin, never by exposing service_role.
create table if not exists public.workspace_invitations (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  email text not null check (char_length(trim(email)) between 3 and 320),
  role text not null default 'viewer' check (role in ('admin','editor','viewer')),
  invited_by uuid not null references auth.users(id) on delete restrict,
  status text not null default 'pending' check (status in ('pending','accepted','revoked','expired')),
  expires_at timestamptz not null default (now() + interval '7 days'),
  created_at timestamptz not null default now(),
  unique (workspace_id, email)
);
alter table public.workspace_invitations enable row level security;
drop policy if exists "invitations_select_admins" on public.workspace_invitations;
create policy "invitations_select_admins" on public.workspace_invitations
for select to authenticated
using ((select private.is_workspace_member(workspace_id, array['owner','admin'])));
revoke insert, update, delete on public.workspace_invitations from anon, authenticated;
