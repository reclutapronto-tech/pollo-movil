import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Forwards Riverpod provider errors to the error reporting system.
base class FieldOpsProviderObserver extends ProviderObserver {
  @override
  void providerDidFail(
    ProviderObserverContext context,
    Object error,
    StackTrace stackTrace,
  ) {
    final providerName =
        context.provider.name ?? context.provider.runtimeType.toString();
    Sentry.captureException(
      error,
      stackTrace: stackTrace,
      withScope: (scope) {
        scope.setTag('provider', providerName);
      },
    );
    debugPrint('[FieldOps] Provider $providerName failed: $error\n$stackTrace');
  }
}
