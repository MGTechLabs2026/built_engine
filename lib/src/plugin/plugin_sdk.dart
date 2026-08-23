import '../content/content_definition.dart';
import '../entity/entity_registry.dart';
import '../event/event_bus.dart';
import '../rule/condition.dart';
import '../rule/effect.dart';
import '../rule/rule.dart';

import 'plugin_context.dart';

/// A convenience facade over [PluginContext] for writing a content
/// plugin without touching Core. Every method here delegates to a
/// service [PluginContext] already exposes — this class adds no new
/// Core capability, only discoverable names and automatic subscription
/// bookkeeping (see [disposeAll]) in place of the `List<EventSubscription>`
/// every plugin previously had to manage by hand (see
/// `MartialArtsPlugin`'s `_subscriptions` field).
///
/// Construct one per plugin, typically once in `GamePlugin.initialize`:
/// `sdk = PluginSdk(context);`.
class PluginSdk {
  PluginSdk(this.context);

  final PluginContext context;

  final List<EventSubscription> _subscriptions = [];
  final Map<String, String> _tags = {};

  // --- component registration ---

  /// Subscribes `EntityDestroyed` and removes an entity's component of
  /// type [T] whenever it's destroyed — the manual step
  /// `ARCHITECTURE.md`'s "Integrating EntityRegistry and ComponentStore"
  /// section otherwise documents as something every consumer must wire
  /// up itself. Tracked for [disposeAll].
  EventSubscription registerComponentCleanup<T extends Object>() {
    final subscription = context.events.subscribe<EntityDestroyed>(
      (event) => context.components.remove<T>(event.id),
    );
    _subscriptions.add(subscription);
    return subscription;
  }

  // --- event registration ---

  /// Subscribes [handler] to every published event of type [T]. Tracked
  /// for [disposeAll].
  EventSubscription registerEvent<T>(void Function(T event) handler) {
    final subscription = context.events.subscribe<T>(handler);
    _subscriptions.add(subscription);
    return subscription;
  }

  // --- effect / condition registration ---

  /// Registers [factory] as this plugin's [Effect] factory under [key],
  /// so `{"type": key, ...}` in loaded content dispatches to it. Not
  /// tracked for [disposeAll] — `ContentRegistry` has no factory-removal
  /// operation today.
  void registerEffect(
    String key,
    Effect Function(Map<String, dynamic> params) factory,
  ) {
    context.content.registerEffectFactory(key, factory);
  }

  /// Registers [factory] as this plugin's [Condition] factory under
  /// [key]. See [registerEffect].
  void registerCondition(
    String key,
    Condition Function(Map<String, dynamic> params) factory,
  ) {
    context.content.registerConditionFactory(key, factory);
  }

  // --- rule registration ---

  /// Registers [rule] against this context's `RuleEngine`. Tracked for
  /// [disposeAll].
  EventSubscription registerRule(Rule rule) {
    final subscription = context.rules.register(rule);
    _subscriptions.add(subscription);
    return subscription;
  }

  // --- tag registration ---

  /// Records [tag] (with an optional human-readable [description]) as
  /// part of this plugin's own tag vocabulary. Purely a documentation/
  /// introspection aid — Core never interprets tags (`claude.md`'s TAGS
  /// section), and this does not change that.
  void registerTag(String tag, {String description = ''}) {
    _tags[tag] = description;
  }

  /// This plugin's tag vocabulary, as recorded via [registerTag].
  Map<String, String> get tags => Map.unmodifiable(_tags);

  // --- content registration ---

  /// Loads [json] as one content definition. See `ContentRegistry.load`.
  ContentDefinition registerContent(Map<String, dynamic> json) =>
      context.content.load(json);

  /// Loads every entry in [jsonList] as one atomic batch. See
  /// `ContentRegistry.loadAll`.
  List<ContentDefinition> registerContentBatch(
          List<Map<String, dynamic>> jsonList) =>
      context.content.loadAll(jsonList);

  // --- asset registration ---

  /// Loads an asset-shaped content definition: `{...data, 'id': id,
  /// 'type': 'asset'}`. `id`/`type` are applied after spreading [data],
  /// so [data] can never override them. Whatever shape [data] carries
  /// (a `path`, a size, ...) is never interpreted by Core — it surfaces
  /// verbatim on the resulting `ContentDefinition.extra`.
  ContentDefinition registerAsset({
    required String id,
    required Map<String, dynamic> data,
  }) =>
      context.content.load({...data, 'id': id, 'type': 'asset'});

  // --- localization registration ---

  /// Loads a localization-shaped content definition, id `'$locale:$key'`
  /// — `locale`/`key`/`value` are not otherwise interpreted, so they
  /// surface on `ContentDefinition.extra` exactly like any other
  /// unrecognized field.
  ContentDefinition registerLocalization({
    required String locale,
    required String key,
    required String value,
  }) =>
      context.content.load({
        'id': '$locale:$key',
        'type': 'localization',
        'locale': locale,
        'key': key,
        'value': value,
      });

  /// Looks up a string registered via [registerLocalization] for
  /// [locale]/[key]. `null` if no such definition exists, or if a
  /// definition exists at that id but isn't a `'localization'` entry.
  String? localize(String locale, String key) {
    final definition = context.content.find('$locale:$key');
    if (definition == null || definition.type != 'localization') {
      return null;
    }
    return definition.extra['value'] as String?;
  }

  // --- teardown ---

  /// Cancels every subscription tracked by [registerComponentCleanup]/
  /// [registerEvent]/[registerRule], in registration order, then clears
  /// the tracking list. Safe to call more than once.
  void disposeAll() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
  }
}
