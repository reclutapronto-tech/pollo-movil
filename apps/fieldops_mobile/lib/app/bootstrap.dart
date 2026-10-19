import 'dart:async';

import 'package:fieldops_mobile/app/app.dart';
import 'package:fieldops_mobile/core/config/fieldops_environment.dart';
import 'package:fieldops_mobile/core/observability/fieldops_provider_observer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Friendly error widget in release — avoids the "red screen of death" for
  // field workers if a widget subtree throws during build.
  if (kReleaseMode) {
    ErrorWidget.builder = (FlutterErrorDetails details) {
      return const Material(
        color: Color(0xFF1F2D3D),
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Something went wrong.\nPlease restart the app.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
        ),
      );
    };
  }

  // Capture uncaught async errors regardless of Sentry configuration. When
  // Sentry is active it installs its own FlutterError.onError handler; we
  // still forward PlatformDispatcher errors to it so nothing is lost.
  PlatformDispatcher.instance.onError = (error, stack) {
    Sentry.captureException(error, stackTrace: stack);
    debugPrint('Platform error: $error\n$stack');
    return true;
  };

  final environment = FieldOpsEnvironment.fromDartDefine();

  if (environment.isConfigured) {
    await Supabase.initialize(
      url: environment.supabaseUrl,
      anonKey: environment.supabaseAnonKey,
    );
  }

  final container = ProviderContainer(
    overrides: [fieldOpsEnvironmentProvider.overrideWithValue(environment)],
    observers: [FieldOpsProviderObserver()],
  );

  // Error reporting is opt-in per Pollo Móvil deployment; never inherit a
  // third-party project's telemetry endpoint or capture operational screens.
  const sentryDsn = String.fromEnvironment('SENTRY_DSN');

  final app = UncontrolledProviderScope(
    container: container,
    child: const FieldOpsApp(),
  );

  if (sentryDsn.isNotEmpty) {
    try {
      await SentryFlutter.init(
        (options) {
          options.dsn = sentryDsn;
          options.tracesSampleRate = kReleaseMode ? 0.2 : 1.0;
          options.environment = kReleaseMode ? 'production' : 'development';
          // Identify this product without attaching screenshots or view trees.
          // ignore: deprecated_member_use
          Sentry.configureScope((scope) => scope.setTag('app', 'pollo-movil-mobile'));
          options.beforeSend = (event, hint) {
            final breadcrumbs = event.breadcrumbs?.map((b) {
              final data = b.data;
              if (data != null && data.containsKey('url')) {
                final raw = data['url']?.toString() ?? '';
                final uri = Uri.tryParse(raw);
                if (uri != null && uri.hasQuery) {
                  final sanitized = uri.replace(query: '').toString();
                  final sanitizedData = Map<String, dynamic>.from(data)
                    ..['url'] = sanitized;
                  return b.copyWith(data: sanitizedData);
                }
              }
              return b;
            }).toList();
            return event.copyWith(breadcrumbs: breadcrumbs);
          };
        },
        appRunner: () async {
          runApp(app);
        },
      );
    } on Object catch (e, stack) {
      debugPrint('Sentry init failed, running without error tracking: $e\n$stack');
      runApp(app);
    }
  } else {
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      debugPrint('Flutter error: ${details.exceptionAsString()}');
    };

    runApp(app);
  }
}
