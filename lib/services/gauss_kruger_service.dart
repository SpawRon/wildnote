import 'package:dart_crs/dart_crs.dart';
import 'package:proj4dart/proj4dart.dart' show Point;

class GaussKrugerResult {
  final double x;
  final double y;
  final int zone;
  final String crsCode;
  final String crsName;

  const GaussKrugerResult({
    required this.x,
    required this.y,
    required this.zone,
    required this.crsCode,
    required this.crsName,
  });
}

class GaussKrugerService {
  static const String sourceCrs = 'EPSG:4326';
  static const String targetCrs = 'EPSG:20906'; // GSK-2011 / Gauss-Kruger zone 6

  int calculateZone(double longitude) {
    return ((longitude + 180) / 6).floor() + 1;
  }

  Future<GaussKrugerResult> transform({
    required double latitude,
    required double longitude,
  }) async {
    final transform = await CRSFactory.createCoordinateTransformFromCodes(
      sourceCrs,
      targetCrs,
    );

    final point = Point(x: longitude, y: latitude);
    final result = transform.transform(point);

    if (result == null) {
      throw Exception('Не удалось преобразовать координаты');
    }

    // proj4dart возвращает:
    // result.x = Easting
    // result.y = Northing
    //
    // В БД сохраняем в геодезической записи:
    // gauss_x = северная координата
    // gauss_y = восточная координата

    return GaussKrugerResult(
      x: result.y,
      y: result.x,
      zone: 6, // только Мурманск
      crsCode: targetCrs,
      crsName: 'GSK-2011 / Gauss-Kruger zone 6',
    );
  }
}
