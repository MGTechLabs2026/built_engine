import 'package:build_engine/affix_plugin.dart';
import 'package:build_engine/build_engine.dart';
import 'package:test/test.dart';

PluginContext _ctx() {
  final events = EventBus();
  final entities = EntityRegistry(events);
  final components = ComponentStore();
  final rng = RngService(1);
  return PluginContext(
    entities: entities,
    components: components,
    events: events,
    rng: rng,
    rules: RuleEngine(entities: entities, components: components, events: events, rng: rng),
    queries: QueryEngine(QueryScope(components: components)),
    modifiers: ModifierCollection(),
    content: ContentRegistry(),
  );
}

void main() {
  test('initialize loads content and enumerates by pool tag', () {
    final ctx = _ctx();
    AffixPlugin().initialize(ctx);
    expect(ctx.content.allOfType('affix'), hasLength(33));
    expect(ctx.content.withTag('affix_pool:item_prefix'), hasLength(11));
    expect(ctx.content.withTag('affix_pool:technique_suffix'), hasLength(6));
  });

  test('initialize is idempotent (second call, e.g. after unregister, does not throw)', () {
    final ctx = _ctx();
    AffixPlugin().initialize(ctx);
    expect(() => AffixPlugin()..initialize(ctx)..unregister(ctx), returnsNormally);
  });

  test('runs standalone (no other plugin initialized)', () {
    expect(() => AffixPlugin().initialize(_ctx()), returnsNormally);
  });

  test('a malformed affix entry makes initialize throw ContentValidationException', () {
    final ctx = _ctx();
    // Pre-load a bad entry under a shipped id so the load-once guard skips
    // registerContentBatch and the validation loop hits this map.
    ctx.content.load({
      'id': 'af_keen',
      'type': 'affix',
      'tags': ['affix', 'affix_pool:item_prefix', 'lean:neutral'],
      'label': 'Keen',
      'category': 'item_prefix',
      'mechanic': {'kind': 'heal', 'amount': 3}, // wrong family for an item pool
    });
    expect(() => AffixPlugin().initialize(ctx), throwsA(isA<ContentValidationException>()));
  });

  group('§9 content-parse validation rejects', () {
    void expectRejected(Map<String, dynamic> badEntry) {
      final ctx = _ctx();
      // Pre-load under a shipped id so the load-once guard skips the batch
      // and the validation loop hits this entry.
      ctx.content.load(badEntry);
      expect(() => AffixPlugin().initialize(ctx),
          throwsA(isA<ContentValidationException>()));
    }

    test('mechanic.amount <= 0', () {
      expectRejected({
        'id': 'af_keen',
        'type': 'affix',
        'tags': ['affix', 'affix_pool:item_prefix', 'lean:neutral'],
        'label': 'Keen',
        'category': 'item_prefix',
        'mechanic': {'kind': 'weapon_stat_bonus', 'amount': 0},
      });
    });

    test('affix_pool tag disagrees with category', () {
      expectRejected({
        'id': 'af_keen',
        'type': 'affix',
        'tags': ['affix', 'affix_pool:item_suffix', 'lean:neutral'],
        'label': 'Keen',
        'category': 'item_prefix',
        'mechanic': {'kind': 'weapon_stat_bonus', 'amount': 3},
      });
    });

    test('two lean:* tags', () {
      expectRejected({
        'id': 'af_keen',
        'type': 'affix',
        'tags': ['affix', 'affix_pool:item_prefix', 'lean:neutral', 'lean:force'],
        'label': 'Keen',
        'category': 'item_prefix',
        'mechanic': {'kind': 'weapon_stat_bonus', 'amount': 3},
      });
    });

    test('no affix_pool:* tag', () {
      expectRejected({
        'id': 'af_keen',
        'type': 'affix',
        'tags': ['affix', 'lean:neutral'],
        'label': 'Keen',
        'category': 'item_prefix',
        'mechanic': {'kind': 'weapon_stat_bonus', 'amount': 3},
      });
    });
  });
}
