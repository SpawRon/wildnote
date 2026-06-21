import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

class TaxonNameSuggestion {
  final String id;
  final String acceptedNameRu;
  final String scientificName;
  final String group;
  final String source;
  final int priority;
  final List<String> synonymsRu;

  const TaxonNameSuggestion({
    required this.id,
    required this.acceptedNameRu,
    required this.scientificName,
    required this.group,
    required this.source,
    required this.priority,
    required this.synonymsRu,
  });

  factory TaxonNameSuggestion.fromJson(Map<String, dynamic> json) {
    final acceptedNameRu = TaxonNameService.normalizeDisplayName(
      json['acceptedNameRu']?.toString() ?? '',
    );
    final scientificName = (json['scientificName']?.toString() ?? '').trim();

    return TaxonNameSuggestion(
      id: (json['id']?.toString() ?? scientificName).trim(),
      acceptedNameRu: acceptedNameRu,
      scientificName: scientificName,
      group: (json['group']?.toString() ?? 'plant').trim(),
      source: (json['source']?.toString() ?? 'Локальный справочник').trim(),
      priority: int.tryParse(json['priority']?.toString() ?? '') ?? 0,
      synonymsRu: (json['synonymsRu'] as List? ?? const <dynamic>[])
          .map((item) => TaxonNameService.normalizeDisplayName(item.toString()))
          .where((item) => item.isNotEmpty)
          .toSet()
          .toList(),
    );
  }

  factory TaxonNameSuggestion.legacy(String value) {
    final normalized = TaxonNameService.normalizeDisplayName(value);

    return TaxonNameSuggestion(
      id: 'legacy:${TaxonNameService.normalizeSearchQuery(normalized)}',
      acceptedNameRu: normalized,
      scientificName: '',
      group: 'plant',
      source: 'Ранее сохранённая запись',
      priority: 0,
      synonymsRu: const <String>[],
    );
  }

  TaxonNameSuggestion copyWith({
    String? id,
    String? acceptedNameRu,
    String? scientificName,
    String? group,
    String? source,
    int? priority,
    List<String>? synonymsRu,
  }) {
    return TaxonNameSuggestion(
      id: id ?? this.id,
      acceptedNameRu: acceptedNameRu ?? this.acceptedNameRu,
      scientificName: scientificName ?? this.scientificName,
      group: group ?? this.group,
      source: source ?? this.source,
      priority: priority ?? this.priority,
      synonymsRu: synonymsRu ?? this.synonymsRu,
    );
  }

  String get groupLabel {
    switch (group) {
      case 'lichen':
        return 'Лишайник';
      case 'moss':
        return 'Мох';
      case 'liverwort':
        return 'Печёночник';
      case 'fungus':
        return 'Гриб';
      case 'plant':
      default:
        return 'Растение';
    }
  }
}

class _ScoredTaxonSuggestion {
  final TaxonNameSuggestion item;
  final int score;

  const _ScoredTaxonSuggestion(this.item, this.score);
}

class TaxonNameService {
  TaxonNameService._();

  static final TaxonNameService instance = TaxonNameService._();

  static const String _assetPath = 'assets/data/taxa_ru.json';

  Future<List<TaxonNameSuggestion>>? _loadFuture;

  Future<void> warmUp() async {
    await _loadTaxa();
  }

  Future<List<TaxonNameSuggestion>> search(
      String rawQuery, {
        int limit = 12,
      }) async {
    final query = normalizeSearchQuery(rawQuery);
    if (query.length < 2) return const <TaxonNameSuggestion>[];

    final taxa = await _loadTaxa();
    final scored = <_ScoredTaxonSuggestion>[];

    for (final item in taxa) {
      final score = _score(item, query);
      if (score > 0) scored.add(_ScoredTaxonSuggestion(item, score));
    }

    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;

      final byPriority = b.item.priority.compareTo(a.item.priority);
      if (byPriority != 0) return byPriority;

      return a.item.acceptedNameRu.compareTo(b.item.acceptedNameRu);
    });

    return scored.take(limit).map((entry) => entry.item).toList();
  }

  Future<List<TaxonNameSuggestion>> _loadTaxa() {
    return _loadFuture ??= _readTaxa();
  }

  Future<List<TaxonNameSuggestion>> _readTaxa() async {
    final raw = await rootBundle.loadString(_assetPath);
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const <TaxonNameSuggestion>[];

    final result = <TaxonNameSuggestion>[];
    final usedIds = <String>{};

    for (final item in decoded) {
      if (item is! Map) continue;
      final taxon = TaxonNameSuggestion.fromJson(
        Map<String, dynamic>.from(item),
      );

      if (taxon.acceptedNameRu.isEmpty || taxon.scientificName.isEmpty) {
        continue;
      }
      if (!usedIds.add(taxon.id)) continue;

      result.add(taxon);
    }

    return result;
  }

  static int _score(TaxonNameSuggestion item, String query) {
    final accepted = normalizeSearchQuery(item.acceptedNameRu);
    final scientific = normalizeSearchQuery(item.scientificName);
    final synonyms = item.synonymsRu.map(normalizeSearchQuery).toList();
    final acceptedWords = accepted.split(' ');
    final synonymWords = synonyms.expand((item) => item.split(' ')).toList();

    var score = 0;

    if (accepted == query) {
      score = 10000;
    } else if (synonyms.any((item) => item == query)) {
      score = 9600;
    } else if (accepted.startsWith(query)) {
      score = 9000;
    } else if (synonyms.any((item) => item.startsWith(query))) {
      score = 8700;
    } else if (acceptedWords.any((word) => word.startsWith(query))) {
      score = 8200;
    } else if (synonymWords.any((word) => word.startsWith(query))) {
      score = 7800;
    } else if (accepted.contains(query)) {
      score = 6500;
    } else if (synonyms.any((item) => item.contains(query))) {
      score = 6200;
    } else if (scientific == query) {
      score = 5700;
    } else if (scientific.startsWith(query)) {
      score = 5200;
    } else if (scientific.contains(query)) {
      score = 4600;
    }

    if (score == 0) return 0;

    return score + item.priority;
  }

  static String normalizeDisplayName(String value) {
    final trimmed = value
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(' ,', ',')
        .trim();
    if (trimmed.isEmpty) return '';

    return trimmed.substring(0, 1).toUpperCase() + trimmed.substring(1);
  }

  static String normalizeSearchQuery(String value) {
    return value
        .replaceAll('Ё', 'Е')
        .replaceAll('ё', 'е')
        .toLowerCase()
        .replaceAll(RegExp(r'[\u00A0\t\n\r]+'), ' ')
        .replaceAll(RegExp(r'[.,;:()\[\]{}"“”«»]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
