/*
 * CustomTuning.h
 *
 * NON-STOCK: server tuning constants for this fork, gathered in one place so the
 * values cannot drift between the translation units that use them.
 *
 * Set any multiplier to 1.f to restore stock Core3 behaviour.
 */

#ifndef CUSTOMTUNING_H_
#define CUSTOMTUNING_H_

namespace server {
namespace zone {

/*
 * Multiplier applied to a player's run speed while on foot and upright.
 *
 * Applied in CreatureObjectImplementation::getSpeedModifier, which is recomputed
 * on every speed update, so the value cannot accumulate. The client honours it
 * because a player's speedMultiplierMod is sent to them as a CREO delta, and
 * PlayerManagerImplementation::checkPlayerSpeedTest derives its ceiling from the
 * same value, so the anti-cheat allowance scales with it.
 *
 * Does not apply to prone or crouched movement, which uses slope_move instead.
 */
constexpr float PLAYER_RUN_SPEED_MULTIPLIER = 2.f;

/*
 * Multiplier applied to anything a player rides: vehicles and creature mounts.
 *
 * This one needs three co-operating pieces, because the client does not take a
 * mount's speed from the server's runSpeed -- it uses its own client-side value
 * for the mount and multiplies it by the RIDER's speedMultiplierMod:
 *
 *   1. CreatureObjectImplementation::getSpeedModifier applies it to the rider
 *      while CreatureState::RIDINGMOUNT is set. This is what actually makes the
 *      client move faster.
 *   2. CreatureObjectImplementation scales a vehicle's own runSpeed, in both
 *      loadTemplateData and initializeTransientMembers. checkPlayerSpeedTest
 *      validates a mounted rider against the vehicle's runSpeed, so this is what
 *      raises the anti-cheat ceiling and stops the faster rider from being
 *      rejected and snapped back to their last validated position.
 *   3. PetManagerImplementation::getMountedRunSpeed scales creature mounts, whose
 *      speeds come from the mount speed datatable rather than an object template,
 *      so that their ceiling matches too.
 *
 * Raising this without (2) and (3) causes constant rubber-banding; raising only
 * (2) has no visible effect at all.
 */
constexpr float VEHICLE_SPEED_MULTIPLIER = 4.f;

/*
 * Maximum absorption percentage against damage-over-time effects: bleeding, fire,
 * poison and disease. Stock Core3 caps this at 50, so every DoT always did at
 * least half damage. At 100 enough absorption makes a character immune.
 *
 * Do not raise this above 100. DamageOverTime computes
 * (uint32)(strength * (1 - absorption / 100)), so a negative factor wraps around
 * to an enormous unsigned value instead of zero damage.
 */
constexpr int DOT_MAX_ABSORPTION = 100;

/*
 * Added to every applicable stat of a newly spawned resource, on top of the stock
 * random roll within the resource type's range, so spawns keep their variety but
 * are all strong. Attributes a type does not have (range 0-0) stay 0.
 *
 * Every attribute range in the client resource tree has a minimum of at least 1
 * (checked across all 3100 ranges), so a boosted stat is always above this value.
 * ResourceSpawner::loadResourceSpawns relies on that: at startup it retires any
 * active spawn with an applicable stat at or below this value, which catches both
 * stock spawns and spawns from before the bonus existed, and the startup shift
 * replaces them. Set to 0 for stock behaviour (the startup check then does nothing).
 */
constexpr int RESOURCE_STAT_BONUS = 1000;

} // namespace zone
} // namespace server

#endif /* CUSTOMTUNING_H_ */
