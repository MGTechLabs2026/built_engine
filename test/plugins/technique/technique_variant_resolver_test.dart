// test/plugins/technique/technique_variant_resolver_test.dart
import 'package:build_engine/src/plugins/technique/technique_descriptor.dart';
import 'package:build_engine/src/plugins/technique/technique_variant_resolver.dart';
import 'package:test/test.dart';

const _bear = TechniqueDescriptor(id: 'bear', axes: {'power': 6, 'speed': -1});
const _thunder = TechniqueDescriptor(id: 'thunder', axes: {'power': 7});
const _swift = TechniqueDescriptor(id: 'swift', axes: {'speed': 5});

void main() {
  const resolver = TechniqueVariantResolver();

  test('empty descriptors → empty profile', () {
    expect(resolver.resolve(const []), isEmpty);
  });

  test('a multi-axis descriptor yields every axis in its map', () {
    expect(resolver.resolve(const [_bear]), {'power': 6, 'speed': -1});
  });

  test('descriptors sharing an axis sum; other axes stay separate', () {
    expect(
      resolver.resolve(const [_bear, _thunder, _swift]),
      {'power': 13, 'speed': 4},
    );
  });

  test('resolve takes descriptors only — no styleCentre argument', () {
    // Compile-time guarantee (rule 2): this call has exactly one positional
    // arg. If a styleCentre param is ever added, this file stops compiling.
    final profile = resolver.resolve(const [_bear]);
    expect(profile['power'], 6);
  });

  test('deterministic — identical inputs, identical output', () {
    expect(
      resolver.resolve(const [_bear, _swift, _thunder]),
      resolver.resolve(const [_bear, _swift, _thunder]),
    );
  });

  group('composeAxisProfile', () {
    test('empty base → contribution unchanged', () {
      expect(composeAxisProfile(const {}, const {'power': 3}), {'power': 3});
    });
    test('empty contribution → base unchanged', () {
      expect(composeAxisProfile(const {'speed': 2}, const {}), {'speed': 2});
    });
    test('overlapping axes add; disjoint axes union', () {
      expect(
        composeAxisProfile(const {'power': 2, 'endurance': 1}, const {'power': 6}),
        {'power': 8, 'endurance': 1},
      );
    });
    test('deterministic', () {
      expect(
        composeAxisProfile(const {'power': 2}, const {'speed': 1}),
        composeAxisProfile(const {'power': 2}, const {'speed': 1}),
      );
    });
  });
}
