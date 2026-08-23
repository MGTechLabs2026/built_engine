import 'content_errors.dart';

/// Typed field-extraction helpers shared by every content factory —
/// Core's built-in ones and any a plugin registers. Each throws
/// [ContentFieldException] on a missing or wrong-typed field rather than
/// letting a raw [TypeError]/`null` surface — this is what keeps every
/// individual factory a few lines long. Namespaced under one class
/// (rather than exported as top-level functions) so the package's
/// public surface doesn't gain generic top-level names like
/// `requireString`.
class ContentField {
  const ContentField._();

  static String requireString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! String || value.isEmpty) {
      throw ContentFieldException(
          key, 'required non-empty String field missing');
    }
    return value;
  }

  static num requireNum(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! num) {
      throw ContentFieldException(key, 'required num field missing');
    }
    return value;
  }

  static Map<String, dynamic> requireMap(
      Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! Map) {
      throw ContentFieldException(key, 'required object field missing');
    }
    return value.map((k, v) => MapEntry(k as String, v));
  }

  /// Reads an optional array of objects at [key]; `null`/absent yields
  /// an empty list. Every element must itself be a JSON object.
  static List<Map<String, dynamic>> optionalMapList(
      Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) return const [];
    if (value is! List) {
      throw ContentFieldException(key, 'must be an array if present');
    }
    final result = <Map<String, dynamic>>[];
    for (var i = 0; i < value.length; i++) {
      final entry = value[i];
      if (entry is! Map) {
        throw ContentFieldException('$key[$i]', 'entry must be an object');
      }
      result.add(entry.map((k, v) => MapEntry(k as String, v)));
    }
    return result;
  }

  /// Reads an optional array of strings at [key]; `null`/absent yields
  /// an empty set.
  static Set<String> optionalStringSet(
      Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) return const <String>{};
    if (value is! List) {
      throw ContentFieldException(key, 'must be an array if present');
    }
    final result = <String>{};
    for (var i = 0; i < value.length; i++) {
      final entry = value[i];
      if (entry is! String) {
        throw ContentFieldException('$key[$i]', 'entry must be a string');
      }
      result.add(entry);
    }
    return result;
  }
}
