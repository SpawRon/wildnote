import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../data/database_helper.dart';

class ObservationPdfRecord {
  final String title;
  final String? description;
  final String ownerLabel;
  final List<String> photos;
  final Map<String, String>? imageHeaders;
  final Map<String, dynamic> attributes;
  final List<MapEntry<String, String>> badges;
  final List<MapEntry<String, String>> technicalRows;

  const ObservationPdfRecord({
    required this.title,
    required this.ownerLabel,
    required this.photos,
    required this.attributes,
    this.description,
    this.imageHeaders,
    this.badges = const [],
    this.technicalRows = const [],
  });
}

class PdfShareService {
  PdfShareService._();

  static final PdfShareService instance = PdfShareService._();

  static const PdfColor _primary = PdfColor(0.36, 0.48, 0.47);
  static const PdfColor _primaryDark = PdfColor(0.09, 0.13, 0.13);
  static const PdfColor _muted = PdfColor(0.46, 0.52, 0.50);
  static const PdfColor _border = PdfColor(0.86, 0.89, 0.86);
  static const PdfColor _soft = PdfColor(0.95, 0.97, 0.94);
  static const PdfColor _surface = PdfColor(1, 1, 1);

  static const Map<String, String> _attributeLabels = <String, String>{
    PlantAttributeKeys.identificationStatus: 'Статус определения',
    PlantAttributeKeys.habitat: 'Местообитание',
    PlantAttributeKeys.soilType: 'Тип почвы',
    PlantAttributeKeys.moisture: 'Увлажнение',
    PlantAttributeKeys.lightCondition: 'Освещенность',
    PlantAttributeKeys.lifeStage: 'Жизненная стадия',
    PlantAttributeKeys.phenophase: 'Фенологическая фаза',
    PlantAttributeKeys.plantCondition: 'Состояние растения',
    PlantAttributeKeys.abundanceCategory: 'Категория численности',
    PlantAttributeKeys.individualCount: 'Количество особей',
    PlantAttributeKeys.areaOccupied: 'Площадь участка, м²',
    PlantAttributeKeys.anthropogenicImpact: 'Антропогенное воздействие',
    PlantAttributeKeys.threatFactor: 'Угрожающий фактор',
    PlantAttributeKeys.protectionStatus: 'Охранный статус',
  };

  static const List<String> _attributeOrder = <String>[
    PlantAttributeKeys.identificationStatus,
    PlantAttributeKeys.habitat,
    PlantAttributeKeys.soilType,
    PlantAttributeKeys.moisture,
    PlantAttributeKeys.lightCondition,
    PlantAttributeKeys.lifeStage,
    PlantAttributeKeys.phenophase,
    PlantAttributeKeys.plantCondition,
    PlantAttributeKeys.abundanceCategory,
    PlantAttributeKeys.individualCount,
    PlantAttributeKeys.areaOccupied,
    PlantAttributeKeys.anthropogenicImpact,
    PlantAttributeKeys.threatFactor,
    PlantAttributeKeys.protectionStatus,
  ];

  Future<File> shareObservationReport(ObservationPdfRecord record) async {
    final file = await createObservationReport(record);

    await SharePlus.instance.share(
      ShareParams(
        files: <XFile>[
          XFile(
            file.path,
            mimeType: 'application/pdf',
            name: _fileNameFromPath(file.path),
          ),
        ],
        text: 'Отчёт WildNote: ${_safeTitle(record.title)}',
        subject: 'Отчёт WildNote',
        title: 'Отчёт WildNote',
      ),
    );

    return file;
  }

  Future<File> shareHistoryReport({
    required String ownerLabel,
    required List<ObservationPdfRecord> observations,
  }) async {
    final file = await createHistoryReport(
      ownerLabel: ownerLabel,
      observations: observations,
    );

    await SharePlus.instance.share(
      ShareParams(
        files: <XFile>[
          XFile(
            file.path,
            mimeType: 'application/pdf',
            name: _fileNameFromPath(file.path),
          ),
        ],
        text: 'Отчёт WildNote: история наблюдений',
        subject: 'История наблюдений WildNote',
        title: 'История наблюдений WildNote',
      ),
    );

    return file;
  }

  Future<File> createObservationReport(ObservationPdfRecord record) async {
    final theme = await _loadTheme();
    final logoImage = await _loadUniversityLogoImage();
    final images = await _loadImages(
      record.photos.take(4).toList(),
      headers: record.imageHeaders,
    );

    final doc = pw.Document(
      author: 'WildNote',
      creator: 'WildNote',
      title: 'Отчёт наблюдения - ${_safeTitle(record.title)}',
      subject: 'Наблюдение WildNote',
    );

    final facts = _observationFactCards(record);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(32, 28, 32, 30),
        theme: theme,
        build: (context) => <pw.Widget>[
          _documentHeader(
            title: 'Отчёт наблюдения',
            subtitle: 'Автор: ${_ownerLabel(record.ownerLabel)} · сформировано ${_nowLabel()}',
            logoImage: logoImage,
          ),
          pw.SizedBox(height: 14),
          _observationHero(record, images, facts),
          if ((record.description ?? '').trim().isNotEmpty) ...<pw.Widget>[
            pw.SizedBox(height: 12),
            _textBlock('Описание наблюдения', record.description!.trim()),
          ],
          pw.SizedBox(height: 12),
          _compactFactsSection('Сведения и координаты', _technicalFactCards(record)),
          pw.SizedBox(height: 12),
          _attributesCardsSection(record.attributes),
        ],
        footer: (context) => _footer(context),
      ),
    );

    return _writeDocument(
      doc,
      'wildnote_observation_${_dateStamp()}.pdf',
    );
  }

  Future<File> createHistoryReport({
    required String ownerLabel,
    required List<ObservationPdfRecord> observations,
  }) async {
    final theme = await _loadTheme();
    final logoImage = await _loadUniversityLogoImage();
    final previewImages = <int, pw.MemoryImage>{};

    for (var i = 0; i < observations.length; i++) {
      final firstPhoto = observations[i].photos.isEmpty ? null : observations[i].photos.first;
      if (firstPhoto == null) continue;

      final bytes = await _readImageBytes(
        firstPhoto,
        headers: observations[i].imageHeaders,
      );
      if (bytes != null) {
        try {
          previewImages[i] = pw.MemoryImage(bytes);
        } catch (_) {
          // Игнорируем неподдерживаемую миниатюру, сам отчёт всё равно создаётся.
        }
      }
    }

    final doc = pw.Document(
      author: 'WildNote',
      creator: 'WildNote',
      title: 'История наблюдений WildNote',
      subject: 'История наблюдений WildNote',
    );

    final total = observations.length;
    final synced = observations.where((item) => _hasBadge(item, 'Отправлено')).length;
    final local = observations.where((item) => _hasBadge(item, 'Локально')).length;
    final errors = observations.where((item) => _hasBadge(item, 'Ошибка')).length;
    final manual = observations.where((item) => _hasBadge(item, 'Ручной ввод')).length;
    final edited = observations.where((item) => _hasBadge(item, 'Изменено')).length;
    final photos = observations.fold<int>(0, (sum, item) => sum + item.photos.length);
    final averagePhotos = total > 0 ? photos / total : 0.0;

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(30, 28, 30, 30),
        theme: theme,
        build: (context) => <pw.Widget>[
          _documentHeader(
            title: 'История наблюдений',
            subtitle: 'Пользователь: ${_ownerLabel(ownerLabel)} · сформировано ${_nowLabel()}',
            logoImage: logoImage,
          ),
          pw.SizedBox(height: 14),
          _historySummaryPanel(
            total: total,
            synced: synced,
            local: local,
            errors: errors,
            manual: manual,
            edited: edited,
            photos: photos,
            averagePhotos: averagePhotos,
          ),
          pw.SizedBox(height: 14),
          _sectionTitle('Список наблюдений'),
          pw.SizedBox(height: 8),
          ...observations.asMap().entries.map(
                (entry) => _historyRow(
              index: entry.key + 1,
              record: entry.value,
              image: previewImages[entry.key],
            ),
          ),
        ],
        footer: (context) => _footer(context),
      ),
    );

    return _writeDocument(
      doc,
      'wildnote_history_${_dateStamp()}.pdf',
    );
  }

  Future<pw.MemoryImage?> _loadUniversityLogoImage() async {
    const assetCandidates = <String>[
      'mlogo.png',
      'assets/mlogo.png',
      'assets/icon/mlogo.png',
    ];

    for (final asset in assetCandidates) {
      try {
        final bytes = await rootBundle.load(asset);
        return pw.MemoryImage(bytes.buffer.asUint8List());
      } catch (_) {
        continue;
      }
    }

    return null;
  }

  Future<pw.ThemeData> _loadTheme() async {
    final systemRegular = await _loadFirstSystemFont(const <String>[
      '/system/fonts/Roboto-Regular.ttf',
      '/system/fonts/NotoSans-Regular.ttf',
      '/system/fonts/DroidSans.ttf',
    ]);

    if (systemRegular != null) {
      final systemBold = await _loadFirstSystemFont(const <String>[
        '/system/fonts/Roboto-Bold.ttf',
        '/system/fonts/NotoSans-Bold.ttf',
        '/system/fonts/DroidSans-Bold.ttf',
      ]);
      final systemItalic = await _loadFirstSystemFont(const <String>[
        '/system/fonts/Roboto-Italic.ttf',
        '/system/fonts/NotoSans-Italic.ttf',
      ]);

      return pw.ThemeData.withFont(
        base: systemRegular,
        bold: systemBold ?? systemRegular,
        italic: systemItalic ?? systemRegular,
      );
    }

    try {
      final regular = await PdfGoogleFonts.notoSansRegular();
      final bold = await PdfGoogleFonts.notoSansBold();
      final italic = await PdfGoogleFonts.notoSansItalic();

      return pw.ThemeData.withFont(
        base: regular,
        bold: bold,
        italic: italic,
      );
    } catch (_) {
      rethrow;
    }
  }

  Future<pw.Font?> _loadFirstSystemFont(List<String> paths) async {
    for (final path in paths) {
      try {
        final file = File(path);
        if (!await file.exists()) continue;

        final bytes = await file.readAsBytes();
        if (bytes.isEmpty) continue;

        return pw.Font.ttf(
          ByteData.view(
            bytes.buffer,
            bytes.offsetInBytes,
            bytes.lengthInBytes,
          ),
        );
      } catch (_) {
        continue;
      }
    }

    return null;
  }

  pw.Widget _documentHeader({
    required String title,
    required String subtitle,
    pw.MemoryImage? logoImage,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 8),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: <pw.Widget>[
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: <pw.Widget>[
                pw.Text(
                  title,
                  style: pw.TextStyle(
                    fontSize: 23,
                    height: 1.05,
                    fontWeight: pw.FontWeight.bold,
                    color: _primaryDark,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  subtitle,
                  style: const pw.TextStyle(
                    color: _muted,
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),
          if (logoImage != null) ...<pw.Widget>[
            pw.SizedBox(width: 12),
            pw.Container(
              width: 176,
              height: 48,
              alignment: pw.Alignment.centerRight,
              child: pw.Image(
                logoImage,
                fit: pw.BoxFit.contain,
                alignment: pw.Alignment.centerRight,
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<MapEntry<String, String>> _observationFactCards(
      ObservationPdfRecord record,
      ) {
    final status = _statusFromBadges(record);

    return <MapEntry<String, String>>[
      if (status.isNotEmpty) MapEntry('Статус', status),
      if (_hasBadge(record, 'Ручной ввод')) const MapEntry('Координаты', 'Ручной ввод'),
      if (_hasBadge(record, 'Изменено')) const MapEntry('Запись', 'Изменено'),
    ];
  }

  List<MapEntry<String, String>> _technicalFactCards(ObservationPdfRecord record) {
    final rows = <MapEntry<String, String>>[];

    void add(String key, String label) {
      final value = _rowValue(record.technicalRows, key);
      if (value.isNotEmpty && value != '—') rows.add(MapEntry(label, value));
    }

    final date = _firstBadgeValue(record, RegExp('\\d{2}\\.\\d{2}\\.\\d{4}'));
    if (date.isNotEmpty) rows.add(MapEntry('Дата наблюдения', date));
    if (_hasBadge(record, 'Ручной ввод')) rows.add(const MapEntry('Тип координат', 'Ручной ввод'));
    if (_hasBadge(record, 'Изменено')) rows.add(const MapEntry('Состояние записи', 'Изменено'));

    add('Координаты', 'Координаты WGS84');
    add('Гаусс X / Y', 'Гаусс X / Y');

    return rows;
  }

  pw.Widget _observationHero(
      ObservationPdfRecord record,
      List<pw.MemoryImage> images,
      List<MapEntry<String, String>> facts,
      ) {
    final quickMetrics = _quickObservationMetrics(record, images.length);

    return pw.Container(
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        color: _surface,
        borderRadius: pw.BorderRadius.circular(18),
        border: pw.Border.all(color: _border, width: 1),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          _photoGrid(images),
          pw.SizedBox(width: 14),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: <pw.Widget>[
                pw.Text(
                  record.title.trim().isEmpty ? 'Без названия' : record.title.trim(),
                  maxLines: 2,
                  style: pw.TextStyle(
                    fontSize: 22,
                    height: 1.05,
                    fontWeight: pw.FontWeight.bold,
                    color: _primaryDark,
                  ),
                ),
                pw.SizedBox(height: 5),
                pw.Text(
                  'Автор: ${_ownerLabel(record.ownerLabel)}',
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                    color: _primary,
                  ),
                ),
                pw.SizedBox(height: 11),
                _miniFactsWrap(facts.take(4).toList()),
                if (quickMetrics.isNotEmpty) ...<pw.Widget>[
                  pw.SizedBox(height: 12),
                  _metricStatsStrip(quickMetrics),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _photoGrid(List<pw.MemoryImage> images) {
    if (images.isEmpty) {
      return pw.Container(
        width: 158,
        height: 132,
        alignment: pw.Alignment.center,
        decoration: pw.BoxDecoration(
          color: _soft,
          borderRadius: pw.BorderRadius.circular(14),
        ),
        child: pw.Text(
          'Фото\nнет',
          textAlign: pw.TextAlign.center,
          style: const pw.TextStyle(fontSize: 11, color: _muted),
        ),
      );
    }

    final visible = images.take(4).toList();
    if (visible.length == 1) {
      return pw.Container(
        width: 158,
        height: 132,
        child: pw.ClipRRect(
          horizontalRadius: 14,
          verticalRadius: 14,
          child: pw.Image(visible.first, fit: pw.BoxFit.cover),
        ),
      );
    }

    pw.Widget tile(pw.MemoryImage image, int index) {
      return pw.Container(
        width: 75,
        height: 62,
        decoration: pw.BoxDecoration(
          color: _soft,
          borderRadius: pw.BorderRadius.circular(12),
        ),
        child: pw.ClipRRect(
          horizontalRadius: 12,
          verticalRadius: 12,
          child: pw.Image(image, fit: pw.BoxFit.cover),
        ),
      );
    }

    return pw.Container(
      width: 158,
      height: 132,
      child: pw.Wrap(
        spacing: 8,
        runSpacing: 8,
        children: visible.asMap().entries
            .map((entry) => tile(entry.value, entry.key))
            .toList(),
      ),
    );
  }

  List<MapEntry<String, String>> _quickObservationMetrics(
      ObservationPdfRecord record,
      int loadedImageCount,
      ) {
    final result = <MapEntry<String, String>>[];

    void add(String label, String value) {
      final clean = value.trim();
      if (clean.isEmpty || clean == '—') return;
      result.add(MapEntry(label, clean));
    }

    add('Фото', record.photos.isNotEmpty ? '${record.photos.length}' : '$loadedImageCount');
    add('Точность', _rowValue(record.technicalRows, 'Точность'));
    add('ID', _rowValue(record.technicalRows, 'ID объекта'));
    add('Особей', _formatAttributeValue(record.attributes[PlantAttributeKeys.individualCount]));
    add('Площадь', _formatAttributeValue(record.attributes[PlantAttributeKeys.areaOccupied]));

    return result;
  }

  pw.Widget _metricStatsStrip(List<MapEntry<String, String>> metrics) {
    final visible = metrics
        .where((item) => item.value.trim().isNotEmpty && item.value.trim() != '—')
        .take(5)
        .toList();

    if (visible.isEmpty) return pw.SizedBox.shrink();

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: visible.asMap().entries.map((entry) {
        final item = entry.value;
        final isLast = entry.key == visible.length - 1;

        return pw.Expanded(
          child: pw.Container(
            margin: pw.EdgeInsets.only(right: isLast ? 0 : 4),
            child: _plainStatItem(
              item.key,
              _compactMetricValue(item.key, item.value),
              width: double.infinity,
              valueFontSize: 18.4,
              labelFontSize: 7.0,
              alignStart: false,
            ),
          ),
        );
      }).toList(),
    );
  }

  String _compactMetricValue(String label, String value) {
    final clean = value.trim();
    if (label == 'Точность') {
      return clean
          .replaceAll('±', '')
          .replaceAll(' м', ' м')
          .trim();
    }
    return clean;
  }

  pw.Widget _miniFactsWrap(List<MapEntry<String, String>> facts) {
    return pw.Wrap(
      spacing: 6,
      runSpacing: 6,
      children: facts
          .where((item) => item.value.trim().isNotEmpty && item.value.trim() != '—')
          .map(
            (item) => pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: pw.BoxDecoration(
            color: _soft,
            borderRadius: pw.BorderRadius.circular(12),
          ),
          child: pw.Text(
            '${item.key}: ${item.value}',
            maxLines: 1,
            style: pw.TextStyle(
              fontSize: 8.6,
              fontWeight: pw.FontWeight.bold,
              color: _primaryDark,
            ),
          ),
        ),
      )
          .toList(),
    );
  }

  pw.Widget _textBlock(String title, String text) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.fromLTRB(13, 11, 13, 12),
      decoration: pw.BoxDecoration(
        color: _soft,
        borderRadius: pw.BorderRadius.circular(16),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.Text(
            title,
            style: pw.TextStyle(
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
              color: _primaryDark,
            ),
          ),
          pw.SizedBox(height: 5),
          pw.Text(
            text,
            style: const pw.TextStyle(
              fontSize: 10.6,
              height: 1.25,
              color: _primaryDark,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _compactFactsSection(String title, List<MapEntry<String, String>> rows) {
    final visibleRows = rows
        .where((row) => row.value.trim().isNotEmpty && row.value.trim() != '—')
        .toList();

    if (visibleRows.isEmpty) return pw.SizedBox.shrink();

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        _sectionTitle(title),
        pw.SizedBox(height: 7),
        pw.Wrap(
          spacing: 8,
          runSpacing: 8,
          children: visibleRows
              .map((row) => _smallInfoCard(row.key, row.value, width: 158))
              .toList(),
        ),
      ],
    );
  }

  pw.Widget _smallInfoCard(
      String label,
      String value, {
        double width = 160,
        PdfColor background = _surface,
      }) {
    return pw.Container(
      width: width,
      padding: const pw.EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: pw.BoxDecoration(
        color: background,
        border: pw.Border.all(color: _border, width: 1),
        borderRadius: pw.BorderRadius.circular(14),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.Text(
            label,
            maxLines: 1,
            style: const pw.TextStyle(
              fontSize: 8.6,
              color: _muted,
            ),
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            value,
            maxLines: 3,
            style: pw.TextStyle(
              fontSize: 10.2,
              height: 1.12,
              fontWeight: pw.FontWeight.bold,
              color: _primaryDark,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _attributesCardsSection(Map<String, dynamic> attributes) {
    final rows = <MapEntry<String, String>>[];

    for (final key in _attributeOrder) {
      if (key == PlantAttributeKeys.individualCount ||
          key == PlantAttributeKeys.areaOccupied) {
        continue;
      }
      final value = _formatAttributeValue(attributes[key]);
      if (value.isEmpty) continue;
      rows.add(MapEntry(_attributeLabels[key] ?? key, value));
    }

    if (rows.isEmpty) return pw.SizedBox.shrink();

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        _sectionTitle('Характеристики растения'),
        pw.SizedBox(height: 7),
        pw.Wrap(
          spacing: 8,
          runSpacing: 8,
          children: rows
              .map((row) => _smallInfoCard(row.key, row.value, width: 158))
              .toList(),
        ),
      ],
    );
  }

  pw.Widget _sectionTitle(String title) {
    return pw.Text(
      title,
      style: pw.TextStyle(
        fontSize: 15,
        fontWeight: pw.FontWeight.bold,
        color: _primaryDark,
      ),
    );
  }

  pw.Widget _historySummaryPanel({
    required int total,
    required int synced,
    required int local,
    required int errors,
    required int manual,
    required int edited,
    required int photos,
    required double averagePhotos,
  }) {
    final items = <MapEntry<String, String>>[
      MapEntry('Всего', '$total'),
      MapEntry('Отправлено', '$synced'),
      MapEntry('Локально', '$local'),
      MapEntry('Ошибки', '$errors'),
      MapEntry('Фото', '$photos'),
      MapEntry('Сред. фото', _formatAverage(averagePhotos)),
      MapEntry('Ручной ввод', '$manual'),
      MapEntry('Изменено', '$edited'),
    ];

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        pw.Text(
          'Краткая статистика',
          style: pw.TextStyle(
            fontSize: 14,
            fontWeight: pw.FontWeight.bold,
            color: _primaryDark,
          ),
        ),
        pw.SizedBox(height: 10),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: items.asMap().entries.map((entry) {
            final item = entry.value;
            final isLast = entry.key == items.length - 1;

            return pw.Expanded(
              child: pw.Container(
                margin: pw.EdgeInsets.only(right: isLast ? 0 : 8),
                child: _plainStatItem(
                  item.key,
                  item.value,
                  width: double.infinity,
                  alignStart: false,
                  valueFontSize: item.value.length > 4 ? 12.8 : 18.2,
                  labelFontSize: 6.8,
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  pw.Widget _plainStatItem(
      String label,
      String value, {
        double width = 68,
        bool alignStart = false,
        double? valueFontSize,
        double labelFontSize = 7.6,
      }) {
    final bool textValue = value == 'Есть' || value == 'Нет';
    final double resolvedValueSize = valueFontSize ??
        (textValue ? 14 : (value.length > 5 ? 15 : 19.5));

    return pw.Container(
      width: width,
      padding: const pw.EdgeInsets.only(top: 1, bottom: 1),
      child: pw.Column(
        crossAxisAlignment: alignStart
            ? pw.CrossAxisAlignment.start
            : pw.CrossAxisAlignment.center,
        children: <pw.Widget>[
          pw.SizedBox(
            height: resolvedValueSize + 4,
            child: pw.Align(
              alignment: alignStart ? pw.Alignment.centerLeft : pw.Alignment.center,
              child: pw.Text(
                value,
                maxLines: 1,
                textAlign: alignStart ? pw.TextAlign.left : pw.TextAlign.center,
                style: pw.TextStyle(
                  fontSize: resolvedValueSize,
                  height: 0.95,
                  fontWeight: pw.FontWeight.bold,
                  color: _primary,
                ),
              ),
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            label,
            maxLines: 2,
            textAlign: alignStart ? pw.TextAlign.left : pw.TextAlign.center,
            style: pw.TextStyle(
              fontSize: labelFontSize,
              height: 1.08,
              color: _muted,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _historyRow({
    required int index,
    required ObservationPdfRecord record,
    pw.MemoryImage? image,
  }) {
    final date = _firstBadgeValue(record, RegExp('\\d{2}\\.\\d{2}\\.\\d{4}'));
    final status = _statusFromBadges(record);
    final coordinates = _rowValue(record.technicalRows, 'Координаты');
    final accuracy = _rowValue(record.technicalRows, 'Точность');
    final photoCount = record.photos.length;
    final isManual = _hasBadge(record, 'Ручной ввод');
    final isEdited = _hasBadge(record, 'Изменено');

    final metaParts = <String>[
      if (date.isNotEmpty) date,
      if (photoCount > 0) 'Фото: $photoCount',
      if (!isManual && accuracy.isNotEmpty) accuracy,
    ];

    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 8),
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: _surface,
        border: pw.Border.all(color: _border, width: 1),
        borderRadius: pw.BorderRadius.circular(16),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.Container(
            width: 54,
            height: 54,
            decoration: pw.BoxDecoration(
              color: _soft,
              borderRadius: pw.BorderRadius.circular(12),
            ),
            child: image == null
                ? pw.Center(
              child: pw.Text(
                '$index',
                style: pw.TextStyle(
                  color: _primary,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            )
                : pw.ClipRRect(
              horizontalRadius: 12,
              verticalRadius: 12,
              child: pw.Image(image, fit: pw.BoxFit.cover),
            ),
          ),
          pw.SizedBox(width: 10),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: <pw.Widget>[
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: <pw.Widget>[
                    pw.Expanded(
                      child: pw.Text(
                        record.title.trim().isEmpty ? 'Без названия' : record.title.trim(),
                        maxLines: 2,
                        style: pw.TextStyle(
                          fontSize: 12.3,
                          height: 1.1,
                          fontWeight: pw.FontWeight.bold,
                          color: _primaryDark,
                        ),
                      ),
                    ),
                    pw.SizedBox(width: 8),
                    pw.Container(
                      width: 220,
                      child: pw.Wrap(
                        spacing: 5,
                        runSpacing: 4,
                        alignment: pw.WrapAlignment.end,
                        children: <pw.Widget>[
                          if (isEdited)
                            _statusPill(
                              'Изменено',
                              textColor: PdfColor(0.75, 0.50, 0.10),
                              background: PdfColor(1.0, 0.97, 0.88),
                              borderColor: PdfColor(0.95, 0.87, 0.65),
                            ),
                          if (isManual)
                            _statusPill(
                              'Ручной ввод',
                              textColor: PdfColor(0.74, 0.20, 0.20),
                              background: PdfColor(1.0, 0.94, 0.94),
                              borderColor: PdfColor(0.93, 0.75, 0.75),
                            ),
                          if (status.isNotEmpty)
                            _statusPill(status, textColor: _primary, background: _soft),
                        ],
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 5),
                if (metaParts.isNotEmpty)
                  pw.Text(
                    metaParts.join(' · '),
                    style: const pw.TextStyle(fontSize: 8.6, color: _muted),
                  ),
                if (coordinates.isNotEmpty) ...<pw.Widget>[
                  pw.SizedBox(height: 4),
                  pw.Text(
                    coordinates,
                    style: const pw.TextStyle(fontSize: 8.6, color: _muted),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }



  pw.Widget _statusPill(
      String text, {
        required PdfColor textColor,
        required PdfColor background,
        PdfColor? borderColor,
      }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: pw.BoxDecoration(
        color: background,
        borderRadius: pw.BorderRadius.circular(10),
        border: borderColor == null ? null : pw.Border.all(color: borderColor, width: 0.8),
      ),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 8.2,
          fontWeight: pw.FontWeight.bold,
          color: textColor,
        ),
      ),
    );
  }

  String _formatAverage(double value) {
    if (value == 0) return '0';
    final rounded = value.toStringAsFixed(1);
    return rounded.endsWith('.0') ? rounded.substring(0, rounded.length - 2) : rounded;
  }

  pw.Widget _footer(pw.Context context) {
    return pw.Container(
      alignment: pw.Alignment.centerRight,
      padding: const pw.EdgeInsets.only(top: 8),
      child: pw.Text(
        'WildNote · страница ${context.pageNumber} из ${context.pagesCount}',
        style: const pw.TextStyle(fontSize: 8, color: _muted),
      ),
    );
  }

  Future<List<pw.MemoryImage>> _loadImages(
      List<String> paths, {
        Map<String, String>? headers,
      }) async {
    final result = <pw.MemoryImage>[];

    for (final path in paths) {
      final bytes = await _readImageBytes(path, headers: headers);
      if (bytes == null) continue;
      try {
        result.add(pw.MemoryImage(bytes));
      } catch (_) {
        continue;
      }
    }

    return result;
  }

  Future<Uint8List?> _readImageBytes(
      String path, {
        Map<String, String>? headers,
      }) async {
    final value = path.trim();
    if (value.isEmpty) return null;

    try {
      if (_isRemotePath(value)) {
        final uri = Uri.tryParse(value);
        if (uri == null) return null;

        final client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 8);
        try {
          final request = await client
              .getUrl(uri)
              .timeout(const Duration(seconds: 8));
          request.headers.set(HttpHeaders.acceptHeader, 'image/*,*/*;q=0.8');
          request.headers.set(HttpHeaders.userAgentHeader, 'WildNote/1.0');
          headers?.forEach(request.headers.set);

          final response = await request
              .close()
              .timeout(const Duration(seconds: 12));

          if (response.statusCode < 200 || response.statusCode >= 300) {
            await response.drain<void>();
            return null;
          }

          final bytes = await consolidateHttpClientResponseBytes(response)
              .timeout(const Duration(seconds: 16));

          return bytes.isEmpty ? null : bytes;
        } finally {
          client.close();
        }
      }

      final file = File(value);
      if (!await file.exists()) return null;
      return file.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  bool _isRemotePath(String value) {
    final lower = value.toLowerCase();
    return lower.startsWith('http://') || lower.startsWith('https://');
  }

  Future<File> _writeDocument(pw.Document document, String fileName) async {
    final directory = await getTemporaryDirectory();
    final reportsDir = Directory('${directory.path}/wildnote_reports');

    if (!await reportsDir.exists()) {
      await reportsDir.create(recursive: true);
    }

    final file = File('${reportsDir.path}/$fileName');
    await file.writeAsBytes(await document.save(), flush: true);
    return file;
  }

  String _formatAttributeValue(Object? value) {
    if (value == null) return '';

    if (value is Iterable) {
      return value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty && item != 'null')
          .join(', ');
    }

    if (value is num) {
      final number = value.toDouble();
      if (number.truncateToDouble() == number) {
        return number.toStringAsFixed(0);
      }
      return number.toString();
    }

    final text = value.toString().trim();
    if (text.isEmpty || text == 'null') return '';

    return text;
  }

  String _rowValue(List<MapEntry<String, String>> rows, String key) {
    for (final row in rows) {
      if (row.key == key) return row.value.trim();
    }
    return '';
  }

  bool _hasBadge(ObservationPdfRecord record, String text) {
    final target = text.trim().toLowerCase();
    return record.badges.any((badge) => badge.value.trim().toLowerCase() == target);
  }

  String _statusFromBadges(ObservationPdfRecord record) {
    const statuses = <String>[
      'Отправлено',
      'Локально',
      'В очереди',
      'Ошибка',
    ];

    for (final status in statuses) {
      if (_hasBadge(record, status)) return status;
    }

    return '';
  }

  String _firstBadgeValue(ObservationPdfRecord record, RegExp pattern) {
    for (final badge in record.badges) {
      if (pattern.hasMatch(badge.value)) return badge.value;
    }
    return '';
  }

  String _ownerLabel(String value) {
    final normalized = value.trim();
    return normalized.isEmpty ? 'не указан' : normalized;
  }

  String _nowLabel() {
    final now = DateTime.now();
    return '${_two(now.day)}.${_two(now.month)}.${now.year} ${_two(now.hour)}:${_two(now.minute)}';
  }

  String _dateStamp() {
    final now = DateTime.now();
    return '${now.year}${_two(now.month)}${_two(now.day)}_${_two(now.hour)}${_two(now.minute)}';
  }

  String _two(int value) => value.toString().padLeft(2, '0');

  String _safeTitle(String value) {
    final title = value.trim();
    return title.isEmpty ? 'Без названия' : title;
  }

  String _fileNameFromPath(String path) {
    final slash = path.lastIndexOf(Platform.pathSeparator);
    return slash < 0 ? path : path.substring(slash + 1);
  }
}
