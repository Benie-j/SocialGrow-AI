
from pathlib import Path
import shutil
import sys

repo = Path.cwd()

repository = repo / "app/lib/data/stats_repository.dart"
page = repo / "app/lib/features/stats/presentation/stats_page.dart"
migration = repo / "supabase/migrations/20261127220804_enable_realtime_for_stats.sql"

for f in (repository, page):
    if not f.is_file():
        sys.exit(f"Fichier introuvable : {f}")

backup_repo = repository.with_suffix(".dart.backup_realtime_stats")
backup_page = page.with_suffix(".dart.backup_realtime_stats")

if backup_repo.exists() or backup_page.exists():
    sys.exit("Une sauvegarde existe déjà. Arrêt pour ne rien écraser.")

repo_text = repository.read_text()
page_text = page.read_text()

# 1. Ajouter l'écoute Realtime au repository.
old_interface = """abstract class StatsRepository {
  Future<StatsData> load();
}"""

new_interface = """abstract class StatsRepository {
  Future<StatsData> load();

  /// Émet un événement lorsqu'une donnée statistique change dans Supabase.
  Stream<void> watch();
}"""

if repo_text.count(old_interface) != 1:
    sys.exit("Interface StatsRepository différente : aucune modification effectuée.")

repo_text = repo_text.replace(old_interface, new_interface)

if not repo_text.startswith("import 'package:supabase_flutter/supabase_flutter.dart';"):
    sys.exit("Import Supabase inattendu : aucune modification effectuée.")

repo_text = repo_text.replace(
    "import 'package:supabase_flutter/supabase_flutter.dart';",
    "import 'dart:async';\n\nimport 'package:supabase_flutter/supabase_flutter.dart';",
    1,
)

anchor = """  @override
  Future<StatsData> load() async {"""

watch_code = """  @override
  Stream<void> watch() async* {
    final access =
        await SupabasePublicationSettingsRepository(_client).loadAccess();

    final controller = StreamController<void>();
    final channel = _client.channel('stats:${access.workspaceId}');

    void onChange(PostgresChangePayload payload) {
      if (!controller.isClosed) controller.add(null);
    }

    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'posts',
          callback: onChange,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'facebook_pages',
          callback: onChange,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'page_insights',
          callback: onChange,
        )
        .subscribe((status, error) {
          if (status == RealtimeSubscribeStatus.subscribed) {
            if (!controller.isClosed) controller.add(null);
          } else if (status == RealtimeSubscribeStatus.channelError ||
              status == RealtimeSubscribeStatus.timedOut) {
            if (!controller.isClosed) {
              controller.addError(
                error ?? StateError('Connexion Realtime interrompue.'),
              );
            }
          }
        });

    try {
      yield* controller.stream;
    } finally {
      await _client.removeChannel(channel);
      await controller.close();
    }
  }

  @override
  Future<StatsData> load() async {"""

if repo_text.count(anchor) != 1:
    sys.exit("Point d'insertion du repository introuvable : aucune modification effectuée.")

repo_text = repo_text.replace(anchor, watch_code, 1)

# 2. Ajouter l'abonnement dans l'écran Statistiques.
import_anchor = "import 'package:material_ui/material_ui.dart';"
if page_text.count(import_anchor) != 1:
    sys.exit("Import de stats_page.dart inattendu : aucune modification effectuée.")

page_text = page_text.replace(
    import_anchor,
    "import 'dart:async';\n\n" + import_anchor,
    1,
)

old_fields = """  StatsData? _data;
  String? _error;
  bool _loading = false;"""

new_fields = """  StatsData? _data;
  String? _error;
  bool _loading = false;
  StreamSubscription<void>? _changesSubscription;
  Timer? _refreshTimer;"""

if page_text.count(old_fields) != 1:
    sys.exit("Champs de StatsPage introuvables : aucune modification effectuée.")

page_text = page_text.replace(old_fields, new_fields, 1)

old_init = """    _load();
  }

  Future<void> _load() async {"""

new_init = """    _load();
    _subscribeToChanges();
  }

  void _subscribeToChanges() {
    final repo = widget.repository;
    if (repo == null) return;

    _changesSubscription = repo.watch().listen(
      (_) {
        _refreshTimer?.cancel();
        _refreshTimer = Timer(const Duration(milliseconds: 250), () {
          if (mounted) _load();
        });
      },
      onError: (Object error) {
        if (!mounted || _data != null) return;
        setState(() {
          _error = describeError(error);
        });
      },
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _changesSubscription?.cancel();
    super.dispose();
  }

  Future<void> _load() async {"""

if page_text.count(old_init) != 1:
    sys.exit("Initialisation de StatsPage introuvable : aucune modification effectuée.")

page_text = page_text.replace(old_init, new_init, 1)

old_subtitle = "subtitle: 'Ce que tu publies, et ce que ta Page en retire.',"
new_subtitle = (
    "subtitle: 'Publications actualisées en direct ; "
    "données Facebook selon leur disponibilité chez Meta.',"
)

if page_text.count(old_subtitle) != 1:
    sys.exit("Sous-titre de StatsPage introuvable : aucune modification effectuée.")

page_text = page_text.replace(old_subtitle, new_subtitle, 1)

# Toutes les vérifications sont terminées : sauvegarder puis écrire.
shutil.copy2(repository, backup_repo)
shutil.copy2(page, backup_page)

repository.write_text(repo_text)
page.write_text(page_text)

migration.parent.mkdir(parents=True, exist_ok=True)
if not migration.exists():
    migration.write_text("""-- Les tables statistiques sont déjà activées sur le projet Supabase.
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
""")

print("Correctif appliqué.")
print(f"Sauvegarde : {backup_repo}")
print(f"Sauvegarde : {backup_page}")
print(f"Migration : {migration}")

