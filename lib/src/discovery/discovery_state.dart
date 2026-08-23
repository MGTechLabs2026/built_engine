/// A content subject's discovery state for one entity. `unknown` is the
/// implicit default and never actually stored — only `discovered`/
/// `unlocked` entries live in a [DiscoveryComponent]. `discovered` means
/// only that the entity has encountered the subject; it may still be
/// unusable — `unlocked` is the separate, stronger state that means it
/// actually can be used.
enum DiscoveryState { unknown, discovered, unlocked }
