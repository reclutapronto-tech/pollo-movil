import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('restaurant attendance location is optional and one-shot', () {
    final clockSource = File(
      'lib/features/restaurant_ops/presentation/restaurant_clock_tab.dart',
    ).readAsStringSync();

    expect(clockSource, contains('if (!requireGps) return null;'));
    expect(
      RegExp(r'Geolocator\.getCurrentPosition')
          .allMatches(clockSource)
          .length,
      1,
    );
    expect(clockSource, isNot(contains('Geolocator.getPositionStream')));
  });

  test('native apps do not request background location access', () {
    final androidManifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    expect(androidManifest, isNot(contains('ACCESS_BACKGROUND_LOCATION')));

    final iosInfo = File('ios/Runner/Info.plist').readAsStringSync();
    final backgroundModes = RegExp(
      r'<key>UIBackgroundModes</key>\s*<array>(.*?)</array>',
      dotAll: true,
    ).firstMatch(iosInfo)?.group(1);
    expect(backgroundModes, isNotNull);
    expect(backgroundModes, isNot(contains('<string>location</string>')));
  });
}
