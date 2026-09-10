import 'package:build_engine/build_engine.dart';

import 'affix_definition.dart';
import 'affix_types.dart';

/// Independent per-slot probability that a slot comes up empty — a plain,
/// unadorned piece. Ported from `reward_affix.dart`'s `kNoAffixChance`.
const double kNoAffixChance = 0.34;

const List<String> _slotKinds = ['prefix', 'suffix'];

/// What the resolver needs to know about the reward being generated.
/// [physiqueTradition] is resolved by the caller from the fighter's
/// physique (`'western'` / `'eastern'` / null); the resolver never reads
/// component state.
class AffixRewardContext {
  const AffixRewardContext({required this.domain, required this.physiqueTradition});

  final AffixDomain domain;
  final String? physiqueTradition;
}

/// One resolved slot. [slotKind] (`'prefix'` / `'suffix'`) is a
/// presentation hint for name assembly, not affix identity. [affix] is
/// null when this slot rolled empty.
class AffixResolvedSlot {
  const AffixResolvedSlot({
    required this.position,
    required this.slotKind,
    required this.affix,
  });

  final int position;
  final String slotKind;
  final AffixDefinition? affix;

  @override
  bool operator ==(Object other) =>
      other is AffixResolvedSlot &&
      other.position == position &&
      other.slotKind == slotKind &&
      other.affix?.id == affix?.id;

  @override
  int get hashCode => Object.hash(position, slotKind, affix?.id);
}

/// The immutable, ordered result of one reward's affix resolution —
/// always exactly two slots, `[prefix, suffix]`. Resolved once at reward
/// generation and carried by value through preview and TAKE.
class AffixResolution {
  const AffixResolution(this.slots);

  final List<AffixResolvedSlot> slots;

  @override
  bool operator ==(Object other) {
    if (other is! AffixResolution || other.slots.length != slots.length) {
      return false;
    }
    for (var i = 0; i < slots.length; i++) {
      if (slots[i] != other.slots[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(slots);
}

/// Deterministic engine-owned affix selection. Draws ONLY from [rng], in
/// the normative order: for each slot in position order — one
/// `nextDouble()` for the no-affix check, then, if kept, one weighted
/// pick (which itself draws one `nextDouble()`). Pools come from
/// `affix_pool:*` tags on [content].
AffixResolution resolveRewardAffixes({
  required AffixRewardContext ctx,
  required RngService rng,
  required ContentRegistry content,
}) {
  final AffixLean? favoured = switch (ctx.physiqueTradition) {
    'western' => AffixLean.force,
    'eastern' => AffixLean.flow,
    _ => null,
  };

  num weightOf(AffixDefinition d) {
    if (d.lean == AffixLean.neutral) return 2;
    if (favoured == null) return 2;
    return d.lean == favoured ? 3 : 1;
  }

  final slots = <AffixResolvedSlot>[];
  for (var i = 0; i < _slotKinds.length; i++) {
    final slotKind = _slotKinds[i];
    final poolTag = AffixPoolTags.forSlot(ctx.domain, slotKind);
    final pool = [
      for (final d in content.withTag(poolTag)) affixDefinitionFromContent(d),
    ];

    if (rng.nextDouble() < kNoAffixChance || pool.isEmpty) {
      slots.add(AffixResolvedSlot(position: i, slotKind: slotKind, affix: null));
      continue;
    }

    final chosen = weightedPick<AffixDefinition>(pool, weightOf, rng)!;
    slots.add(AffixResolvedSlot(position: i, slotKind: slotKind, affix: chosen));
  }
  return AffixResolution(slots);
}
