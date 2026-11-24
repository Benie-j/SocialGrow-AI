-- Étend public.publication_settings (source unique de vérité des réglages de publication)
-- avec les sections A à G, et ajoute l'historique des sujets pour la gestion des doublons.
-- Migration additive : aucune colonne existante n'est modifiée ni supprimée.

alter table public.publication_settings
  -- A. Fréquence
  add column if not exists posts_per_day integer not null default 1
    check (posts_per_day between 0 and 50),
  add column if not exists min_interval_minutes integer not null default 120
    check (min_interval_minutes between 0 and 1440),
  -- B. Horaires
  add column if not exists allowed_time_windows jsonb not null
    default '[{"start":"07:00","end":"21:00"}]'::jsonb
    check (jsonb_typeof(allowed_time_windows) = 'array'),
  -- C. Contenu
  add column if not exists allowed_categories text[] not null default '{}',
  add column if not exists preferred_topics text[] not null default '{}',
  add column if not exists avoided_topics text[] not null default '{}',
  add column if not exists writing_style text not null default 'conversational'
    check (char_length(writing_style) <= 100),
  add column if not exists max_hashtags integer not null default 3
    check (max_hashtags between 0 and 30),
  -- D. Formats
  add column if not exists format_text_enabled boolean not null default true,
  add column if not exists format_image_enabled boolean not null default true,
  add column if not exists format_video_enabled boolean not null default false,
  -- E. Automatisation
  add column if not exists auto_generate boolean not null default false,
  add column if not exists publishing_paused boolean not null default false,
  add column if not exists max_retries integer not null default 3
    check (max_retries between 0 and 10),
  add column if not exists retry_delay_minutes integer not null default 15
    check (retry_delay_minutes between 1 and 1440),
  -- F. Stratégie
  add column if not exists primary_goal text not null default 'engagement'
    check (primary_goal in ('followers', 'engagement', 'reach', 'sales')),
  add column if not exists target_audience text
    check (target_audience is null or char_length(target_audience) <= 500),
  add column if not exists preferred_content_type text
    check (preferred_content_type is null or char_length(preferred_content_type) <= 100),
  add column if not exists topic_renewal_days integer not null default 14
    check (topic_renewal_days between 0 and 365),
  add column if not exists adapt_to_performance boolean not null default true,
  -- G. Gestion des doublons
  add column if not exists duplicate_detection_enabled boolean not null default true,
  add column if not exists duplicate_similarity_threshold numeric(3,2) not null default 0.80
    check (duplicate_similarity_threshold between 0 and 1),
  add column if not exists topic_reuse_min_days integer not null default 60
    check (topic_reuse_min_days between 0 and 3650),
  add column if not exists block_identical_republish boolean not null default true;

-- Historique des sujets utilisés (détection de doublons)
create table if not exists public.topic_history (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  post_id uuid references public.posts(id) on delete set null,
  topic text not null check (char_length(topic) between 1 and 500),
  content_hash text,
  used_at timestamptz not null default now()
);

create index if not exists topic_history_workspace_used_idx
  on public.topic_history (workspace_id, used_at desc);

-- Interdit la republication d'un contenu identique dans un même espace de travail
create unique index if not exists topic_history_workspace_hash_uidx
  on public.topic_history (workspace_id, content_hash)
  where content_hash is not null;

alter table public.topic_history enable row level security;

create policy topic_history_select_workspace on public.topic_history
  for select to authenticated
  using ((select private.is_workspace_member(workspace_id, null::text[])));

create policy topic_history_insert_workspace on public.topic_history
  for insert to authenticated
  with check ((select private.is_workspace_member(workspace_id, array['owner','admin','editor']::text[])));

create policy topic_history_delete_workspace on public.topic_history
  for delete to authenticated
  using ((select private.is_workspace_member(workspace_id, array['owner','admin']::text[])));
