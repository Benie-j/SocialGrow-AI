import 'package:supabase_flutter/supabase_flutter.dart';

import 'groq_settings.dart';

abstract class GroqSettingsRepository {
  /// Réglages de l'espace, ou valeurs par défaut s'ils n'existent pas encore.
  Future<GroqSettings> load(String workspaceId);

  Future<GroqSettings> save(String workspaceId, GroqSettings value);

  /// Consommation depuis [since] (début du mois en cours).
  Future<GroqUsage> loadUsage(String workspaceId, DateTime since);
}

class SupabaseGroqSettingsRepository implements GroqSettingsRepository {
  SupabaseGroqSettingsRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<GroqSettings> load(String workspaceId) async {
    final row = await _client
        .from('groq_settings')
        .select()
        .eq('workspace_id', workspaceId)
        .maybeSingle();
    return row == null ? GroqSettings() : GroqSettings.fromMap(row);
  }

  @override
  Future<GroqSettings> save(String workspaceId, GroqSettings value) async {
    final row = await _client
        .from('groq_settings')
        .upsert(
          {...value.toMap(), 'workspace_id': workspaceId},
          onConflict: 'workspace_id',
        )
        .select()
        .single();
    return GroqSettings.fromMap(row);
  }

  @override
  Future<GroqUsage> loadUsage(String workspaceId, DateTime since) async {
    final rows = await _client
        .from('ai_generation_logs')
        .select('input_tokens, output_tokens, latency_ms, success')
        .eq('workspace_id', workspaceId)
        .gte('created_at', since.toUtc().toIso8601String())
        .limit(5000);
    return GroqUsage.fromRows([
      for (final row in rows) Map<String, dynamic>.from(row),
    ]);
  }
}
