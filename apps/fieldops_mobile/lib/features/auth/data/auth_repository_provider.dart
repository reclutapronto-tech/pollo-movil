import 'package:fieldops_mobile/core/config/fieldops_environment.dart';
import 'package:fieldops_mobile/features/auth/data/supabase_auth_repository.dart';
import 'package:fieldops_mobile/features/auth/data/unconfigured_auth_repository.dart';
import 'package:fieldops_mobile/features/auth/domain/auth_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final environment = ref.watch(fieldOpsEnvironmentProvider);
  if (!environment.isConfigured) {
    return const UnconfiguredAuthRepository();
  }

  return SupabaseAuthRepository(Supabase.instance.client);
});
