-- Stratégie éditoriale d'un espace de travail : activité, phrase de marque,
-- piliers de contenu pondérés, voix de marque et formules à bannir.
-- Une ligne par espace (comme publication_settings). Lecture : tout membre.
-- Écriture : owner, admin, editor ; suppression : owner, admin.

create table public.editorial_strategy (
  workspace_id uuid primary key references public.workspaces(id) on delete cascade,
  business_description text not null default '' check (char_length(business_description) <= 600),
  brand_tagline text not null default '' check (char_length(brand_tagline) <= 160),
  pillar_weights jsonb not null default '{"educate":3,"inspire":2,"sell":1,"engage":2,"behind":1}'::jsonb
    check (jsonb_typeof(pillar_weights) = 'object'),
  voice_formality smallint not null default 5 check (voice_formality between 0 and 10),
  voice_warmth smallint not null default 5 check (voice_warmth between 0 and 10),
  banned_phrases text[] not null default '{}'
    check (coalesce(array_length(banned_phrases, 1), 0) <= 20),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.editorial_strategy enable row level security;

create policy editorial_strategy_select_workspace on public.editorial_strategy
  for select to authenticated
  using ((select private.is_workspace_member(workspace_id, null)));

create policy editorial_strategy_insert_workspace on public.editorial_strategy
  for insert to authenticated
  with check ((select private.is_workspace_member(workspace_id, array['owner','admin','editor'])));

create policy editorial_strategy_update_workspace on public.editorial_strategy
  for update to authenticated
  using ((select private.is_workspace_member(workspace_id, array['owner','admin','editor'])))
  with check ((select private.is_workspace_member(workspace_id, array['owner','admin','editor'])));

create policy editorial_strategy_delete_workspace on public.editorial_strategy
  for delete to authenticated
  using ((select private.is_workspace_member(workspace_id, array['owner','admin'])));

grant select, insert, update, delete on public.editorial_strategy to authenticated;

create trigger editorial_strategy_set_updated_at
  before update on public.editorial_strategy
  for each row execute function public.set_updated_at();
