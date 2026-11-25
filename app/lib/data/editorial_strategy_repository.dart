import 'package:supabase_flutter/supabase_flutter.dart';

import 'editorial_strategy.dart';

abstract class EditorialStrategyRepository {
  /// Stratégie de l'espace, ou valeurs par défaut si elle n'existe pas encore.
  Future<EditorialStrategy> load(String workspaceId);

  Future<EditorialStrategy> save(String workspaceId, EditorialStrategy value);
}

class SupabaseEditorialStrategyRepository implements EditorialStrategyRepository {
  SupabaseEditorialStrategyRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<EditorialStrategy> load(String workspaceId) async {
    final row = await _client
        .from('editorial_strategy')
        .select()
        .eq('workspace_id', workspaceId)
        .maybeSingle();
    return row == null ? EditorialStrategy() : EditorialStrategy.fromMap(row);
  }

  @override
  Future<EditorialStrategy> save(
    String workspaceId,
    EditorialStrategy value,
  ) async {
    final row = await _client
        .from('editorial_strategy')
        .upsert(
          {...value.toMap(), 'workspace_id': workspaceId},
          onConflict: 'workspace_id',
        )
        .select()
        .single();
    return EditorialStrategy.fromMap(row);
  }
}
