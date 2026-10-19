import 'package:flutter_riverpod/flutter_riverpod.dart';

final fieldOpsEnvironmentProvider = Provider<FieldOpsEnvironment>(
  (_) => FieldOpsEnvironment.fromDartDefine(),
);

class FieldOpsEnvironment {
  const FieldOpsEnvironment({
    required this.supabaseUrl,
    required this.supabaseAnonKey,
  });

  factory FieldOpsEnvironment.fromDartDefine() {
    return const FieldOpsEnvironment(
      supabaseUrl: String.fromEnvironment('SUPABASE_URL'),
      supabaseAnonKey: String.fromEnvironment('SUPABASE_ANON_KEY'),
    );
  }

  final String supabaseUrl;
  final String supabaseAnonKey;

  bool get isConfigured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
