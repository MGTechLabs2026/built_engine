import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

const _source = ModifierSource('test');
const _target = EntityId(1);

Modifier _mod({
  required ModifierOperation operation,
  required num value,
  int priority = 0,
}) =>
    Modifier(
      source: _source,
      target: _target,
      stat: 'stat',
      operation: operation,
      value: value,
      priority: priority,
    );

void main() {
  group('ModifierResolver', () {
    const resolver = ModifierResolver();

    test('with no modifiers, returns the base value unchanged', () {
      expect(resolver.resolve(10, []), equals(10));
    });

    test('ADD modifiers sum together', () {
      final result = resolver.resolve(10, [
        _mod(operation: ModifierOperation.add, value: 5),
        _mod(operation: ModifierOperation.add, value: 3),
      ]);
      expect(result, equals(18));
    });

    test('MULTIPLY modifiers stack as sequential factors', () {
      final result = resolver.resolve(10, [
        _mod(operation: ModifierOperation.multiply, value: 2),
        _mod(operation: ModifierOperation.multiply, value: 1.5),
      ]);
      expect(result, equals(30));
    });

    test('OVERRIDE: the highest-priority modifier wins', () {
      final result = resolver.resolve(10, [
        _mod(operation: ModifierOperation.override, value: 100, priority: 1),
        _mod(operation: ModifierOperation.override, value: 200, priority: 5),
        _mod(operation: ModifierOperation.override, value: 50, priority: 2),
      ]);
      expect(result, equals(200));
    });

    test(
        'MIN modifiers act as a ceiling, tightest wins regardless of order',
        () {
      final result = resolver.resolve(100, [
        _mod(operation: ModifierOperation.min, value: 50, priority: 5),
        _mod(operation: ModifierOperation.min, value: 30, priority: 1),
      ]);
      expect(result, equals(30));
    });

    test(
        'MAX modifiers act as a floor, loosest (highest) wins regardless of '
        'order', () {
      final result = resolver.resolve(10, [
        _mod(operation: ModifierOperation.max, value: 20, priority: 5),
        _mod(operation: ModifierOperation.max, value: 50, priority: 1),
      ]);
      expect(result, equals(50));
    });

    test(
        'the full pipeline runs ADD, then MULTIPLY, then OVERRIDE, then MIN, '
        'then MAX', () {
      // base 10 -> +5 = 15 -> *2 = 30 -> override to 40 -> min(40,35)=35 -> max(35,38)=38
      final result = resolver.resolve(10, [
        _mod(operation: ModifierOperation.add, value: 5),
        _mod(operation: ModifierOperation.multiply, value: 2),
        _mod(operation: ModifierOperation.override, value: 40),
        _mod(operation: ModifierOperation.min, value: 35),
        _mod(operation: ModifierOperation.max, value: 38),
      ]);
      expect(result, equals(38));
    });

    test('priority orders modifiers within an operation group', () {
      final result = resolver.resolve(0, [
        _mod(operation: ModifierOperation.override, value: 1, priority: 10),
        _mod(operation: ModifierOperation.override, value: 2, priority: 1),
      ]);
      // Sorted ascending by priority: priority 1 (value=2) applies first,
      // then priority 10 (value=1) applies last and wins — proving this is
      // ordered by priority, not by input/list position (a list-position-only
      // implementation would incorrectly produce 2 here).
      expect(result, equals(1));
    });

    test('equal-priority modifiers break ties by input order, deterministically',
        () {
      final orderingA = resolver.resolve(0, [
        _mod(operation: ModifierOperation.override, value: 1, priority: 0),
        _mod(operation: ModifierOperation.override, value: 2, priority: 0),
      ]);
      final orderingB = resolver.resolve(0, [
        _mod(operation: ModifierOperation.override, value: 2, priority: 0),
        _mod(operation: ModifierOperation.override, value: 1, priority: 0),
      ]);
      // In each case, the SECOND modifier in the input list wins (applied last).
      expect(orderingA, equals(2));
      expect(orderingB, equals(1));
    });

    test('resolving the same modifiers twice produces the same result', () {
      final modifiers = [
        _mod(operation: ModifierOperation.add, value: 5, priority: 2),
        _mod(operation: ModifierOperation.multiply, value: 1.5, priority: 1),
      ];
      final resultA = resolver.resolve(10, modifiers);
      final resultB = resolver.resolve(10, modifiers);
      // The fixed macro order (ADD always before MULTIPLY, regardless of
      // priority) gives (10 + 5) * 1.5 = 22.5 — a priority-driven reordering
      // (MULTIPLY before ADD, since its priority is lower) would instead give
      // 10 * 1.5 + 5 = 20. Pinning the value, not just equality, is what
      // actually catches a regression of the fixed-order guarantee.
      expect(resultA, equals(22.5));
      expect(resultA, equals(resultB));
    });
  });
}
