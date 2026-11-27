-- Les tables statistiques sont déjà activées sur le projet Supabase.
-- Ce fichier conserve la trace de cette configuration dans le dépôt.
do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'posts'
  ) then
    alter publication supabase_realtime add table public.posts;
  end if;

  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'facebook_pages'
  ) then
    alter publication supabase_realtime add table public.facebook_pages;
  end if;

  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'page_insights'
  ) then
    alter publication supabase_realtime add table public.page_insights;
  end if;
end $$;
