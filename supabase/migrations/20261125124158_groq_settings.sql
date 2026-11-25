-- Réglages de génération Groq d'un espace de travail (une ligne par espace).
-- La clé Groq n'est jamais stockée ici : elle vit dans les secrets Supabase.
-- Lecture : tout membre. Écriture : owner, admin, editor ; suppression : owner, admin.

create table public.groq_settings (
  workspace_id uuid primary key references public.workspaces(id) on delete cascade,
  model text not null default 'llama-3.3-70b-versatile'
    check (char_length(model) between 1 and 100 and model ~ '^[A-Za-z0-9._/:-]+$'),
  draft_model text not null default 'llama-3.1-8b-instant'
    check (char_length(draft_model) between 1 and 100 and draft_model ~ '^[A-Za-z0-9._/:-]+$'),
  creativity smallint not null default 7 check (creativity between 0 and 15),
  max_output_tokens integer not null default 500 check (max_output_tokens between 100 and 2000),
  monthly_generation_limit integer not null default 300 check (monthly_generation_limit between 1 and 10000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.groq_settings enable row level security;

create policy groq_settings_select_workspace on public.groq_settings
  for select to authenticated
  using ((select private.is_workspace_member(workspace_id, null)));

create policy groq_settings_insert_workspace on public.groq_settings
  for insert to authenticated
  with check ((select private.is_workspace_member(workspace_id, array['owner','admin','editor'])));

create policy groq_settings_update_workspace on public.groq_settings
  for update to authenticated
  using ((select private.is_workspace_member(workspace_id, array['owner','admin','editor'])))
  with check ((select private.is_workspace_member(workspace_id, array['owner','admin','editor'])));

create policy groq_settings_delete_workspace on public.groq_settings
  for delete to authenticated
  using ((select private.is_workspace_member(workspace_id, array['owner','admin'])));

grant select, insert, update, delete on public.groq_settings to authenticated;

create trigger groq_settings_set_updated_at
  before update on public.groq_settings
  for each row execute function public.set_updated_at();
