import 'package:flutter_test/flutter_test.dart';
import 'package:wildnote/services/gauss_kruger_service.dart';

void main() {
  group('GaussKrugerService.calculateZone', () {
    final service = GaussKrugerService();

    test('returns expected zone for western hemisphere edge', () {
      expect(service.calculateZone(-180), 1);
      expect(service.calculateZone(-174.1), 1);
    });

    test('returns expected zone for central longitudes', () {
      expect(service.calculateZone(0), 31);
      expect(service.calculateZone(30), 36);
    });

    test('returns expected zone near eastern edge', () {
      expect(service.calculateZone(179.9), 60);
    });
  });
}
