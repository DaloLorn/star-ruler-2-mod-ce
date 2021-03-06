import hooks;
import hook_globals;
import generic_effects;
import repeat_hooks;
from generic_effects import GenericEffect;
import biomes;
import abilities;
import target_filters;
from abilities import AbilityHook;
import int getAbilityID(const string&) from "abilities";
import int getUnlockTag(const string& ident, bool create = true) from "unlock_tags";
from requirement_effects import Requirement;
#section server
import Planet@ spawnPlanetSpec(const vec3d& point, const string& resourceSpec, bool distributeResource = true, double radius = 0.0, bool physics = true) from "map_effects";
import void filterToResourceTransferAbilities(array<Ability>&) from "CE_resource_transfer";
import CE_array_map;
#section all

// TODO: Rename as no longer just biomes

class SwapBiome : GenericEffect, TriggerableGeneric {
		Document doc("Changes a biome on a planet to a new one");
		Argument old_biome(AT_PlanetBiome, doc="old biome");
		Argument new_biome(AT_PlanetBiome, doc="new biome");

#section server
	void enable(Object& obj, any@ data) const override {
		if (obj.isPlanet) {
			int old_biome_id = getBiomeID(old_biome.str);
			int new_biome_id = getBiomeID(new_biome.str);
			if (old_biome_id == -1) {
				return;
			}
			if (new_biome_id == -1) {
				return;
			}
			obj.swapBiome(uint(old_biome_id), uint(new_biome_id));
		}
	}
#section all
};

class SetHomeworld : BonusEffect {
		Document doc("Set the planet as the empire homeworld");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if (obj is null) {
			return;
		}
		if (!obj.isPlanet) {
			return;
		}
		@emp.Homeworld = cast<Planet>(obj);
		@emp.HomeObj = cast<Planet>(obj);
	}
#section all
}

class UnlockSubsystem : EmpireEffect {
	Document doc("Set a particular subsystem as unlocked in the affected empire.");
	Argument subsystem(AT_Subsystem, doc="Identifier of the subsystem to unlock.");

#section server
	void enable(Empire& owner, any@ data) const override {
		owner.setUnlocked(getSubsystemDef(subsystem.integer), true);
	}
#section all
};

class UnlockTag : EmpireEffect {
	Document doc("Set a particular tag as unlocked in the affected empire.");
	Argument tag(AT_UnlockTag, doc="The unlock tag to unlock. Unlock tags can be named any arbitrary thing, and will be created as specified. Use the same tag value in any RequireUnlockTag() or similar hooks that check for it.");

#section server
	void enable(Empire& owner, any@ data) const override {
		owner.setTagUnlocked(tag.integer, true);
	}
#section all
};

class CancelIfAttributeGT : InfluenceVoteEffect {
	Document doc("Cancel the vote if the owner's attribute is too high.");
	Argument attribute(AT_EmpAttribute, doc="Attribute to check.");
	Argument value(AT_Decimal, "1", doc="Value to test against.");

#section server
	bool onTick(InfluenceVote@ vote, double time) const override {
		Empire@ owner = vote.startedBy;
		if(owner is null || !owner.valid)
			return false;
		if(owner.getAttribute(attribute.integer) > value.decimal)
			vote.end(false, true);
		return false;
	}
#section all
};

class CancelIfAnyAttributeGT : InfluenceVoteEffect {
	Document doc("Cancel the vote if any empires's attribute is too high. Works with ownerless votes");
	Argument attribute(AT_EmpAttribute, doc="Attribute to check.");
	Argument value(AT_Decimal, "1", doc="Value to test against.");

#section server
	bool onTick(InfluenceVote@ vote, double time) const override {
		for (uint i = 0, cnt = getEmpireCount(); i < cnt; ++i) {
			Empire@ emp = getEmpire(i);
			if (emp.getAttribute(attribute.integer) > value.decimal) {
				vote.end(false, true);
				return false;
			}
		}
		return false;
	}
#section all
};

class SpawnDamagedPlanet : BonusEffect {
	Document doc("Spawn a new planet at the current position with half health.");
	Argument resource(AT_Custom, "distributed");
	Argument owned(AT_Boolean, "False", doc="Whether the planet starts colonized.");
	Argument add_status(AT_Status, EMPTY_DEFAULT, doc="A status to add to the planet after it is spawned.");
	Argument in_system(AT_Boolean, "False", doc="Whether to spawn the planet somewhere in the system, instead of on top of the object.");
	Argument radius(AT_Range, "0", doc="Radius of the resulting planet.");
	Argument physics(AT_Boolean, "True", doc="Whether the planet should be a physical object.");
	Argument set_homeworld(AT_Boolean, "False", doc="Whether to set this planet as the homeworld.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(obj is null)
			return;
		vec3d point = obj.position;
		if(in_system.boolean) {
			Region@ reg = obj.region;
			if(reg !is null) {
				point = reg.position;
				vec2d off = random2d(200.0, reg.radius);
				point.x += off.x;
				point.y += randomd(-20.0, 20.0);
				point.z += off.y;
			}
		}
		auto@ planet = spawnPlanetSpec(point, resource.str, true, radius.fromRange(), physics.boolean);
		if(owned.boolean && emp !is null)
			planet.colonyShipArrival(emp, 1.0);
		if(add_status.integer != -1)
			planet.addStatus(add_status.integer);
		if(set_homeworld.boolean) {
			@emp.Homeworld = planet;
			@emp.HomeObj = planet;
		}
		planet.Health *= 0.5;
	}
#section all
};

class DealStellarPercentageDamage : BonusEffect {
	Document doc("Deal percentage damage to a stellar object such as a planet or star.");
	Argument amount(AT_Decimal, doc="Amount of % damage to deal (% of current HP).");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(obj is null)
			return;

		if (obj.isPlanet) {
			Planet@ planet = cast<Planet>(obj);
			planet.dealPlanetDamage(planet.Health * amount.decimal);
		} else if (obj.isStar) {
			Star@ star = cast<Star>(obj);
			star.dealStarDamage(star.Health * amount.decimal);
		}
	}
#section all
};

tidy final class IfHaveEnergyIncome : IfHook {
	Document doc("Only applies the inner hook if the empire has at least a certain amount of energy income per second.");
	Argument amount(AT_Decimal, doc="Minimum amount of energy income per second required.");
	Argument hookID(AT_Hook, "planet_effects::GenericEffect");

	bool instantiate() override {
		if(!withHook(hookID.str))
			return false;
		return GenericEffect::instantiate();
	}

#section server
	bool condition(Object& obj) const override {
		return (obj.owner.EnergyIncome / obj.owner.EnergyGenerationFactor) >= amount.decimal;
	}
#section all
};

class GenerateCargoWhile : AbilityHook {
	Document doc("Generate cargo on the object casting the ability while is has a target.");
	Argument type(AT_Cargo, doc="Type of cargo to add.");
	Argument objTarg(TT_Object);
	Argument rate(AT_SysVar, "1", doc="Rate to create cargo at.");

#section server
	void tick(Ability@ abl, any@ data, double time) const {
		if(abl.obj is null || !abl.obj.hasCargo)
			return;
		Target@ storeTarg = objTarg.fromTarget(abl.targets);
		if(storeTarg is null)
			return;

		Object@ target = storeTarg.obj;
		if(target is null || !target.hasCargo)
			return;
		abl.obj.addCargo(type.integer, time * rate.fromSys(abl.subsystem));
	}
#section all
};

class IfFewerStatusStacks : IfHook {
	Document doc("Only applies the inner hook if the object has fewer status stacks than an amount.");
	Argument status(AT_Status, doc="Type of status effect to limit.");
	Argument amount(AT_Integer, doc="Minimum number of stacks to stop triggering inner hook at.");
	Argument hookID(AT_Hook, "planet_effects::GenericEffect");

	bool instantiate() override {
		if(!withHook(hookID.str))
			return false;
		return GenericEffect::instantiate();
	}

#section server
	bool condition(Object& obj) const override {
		if(!obj.hasStatuses)
			return false;
		int count = obj.getStatusStackCount(status.integer);
		return count < amount.integer;
	}
#section all
};

class DealPlanetTrueDamage : BonusEffect {
	Document doc("Deal true damage to a planet (bypassing pop based modifiers).");
	Argument amount(AT_Decimal, doc="Amount of damage to deal.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if(obj is null)
			return;

		if (obj.isPlanet) {
			Planet@ planet = cast<Planet>(obj);
			planet.Health -= amount.decimal;
			if (planet.Health <= 0) {
				planet.Health = 0;
				planet.destroy();
			}
		}
	}
#section all
};

class IfPlanetPercentageHealthLessThan : IfHook {
	Document doc("Only applies the inner hook if the planet has the specified % hp or less remaining.");
	Argument amount(AT_Decimal, doc="% of hp threshold.");
	Argument hookID(AT_Hook, "planet_effects::GenericEffect");

	bool instantiate() override {
		if(!withHook(hookID.str))
			return false;
		return GenericEffect::instantiate();
	}

#section server
	bool condition(Object& obj) const override {
		if (obj is null) {
			return false;
		}
		if (obj.isPlanet) {
			Planet@ planet = cast<Planet>(obj);
			return (planet.Health / planet.MaxHealth) <= amount.decimal;
		}
		return false;
	}
#section all
};

class DealPlanetPercentageTrueDamageOverTime : GenericEffect, TriggerableGeneric {
	Document doc("Deal percentage max hp true damage to the targeted planet over time. Stops when hits threshold");
	Argument amount(AT_Decimal, doc="Amount of % damage to deal (% of max HP) per second.");

#section server
	void tick(Object& obj, any@ data, double time) const override {
		if (obj is null) {
			return;
		}

		if (obj.isPlanet) {
			Planet@ planet = cast<Planet>(obj);
			planet.Health -= planet.MaxHealth * amount.decimal * time;
			if (planet.Health <= 0) {
				planet.Health = 0;
				planet.destroy();
			}
		}
	}
#section all
};

class IfPlanetHasBiome : IfHook {
	Document doc("Only applies the inner hook if the planet has the specified biome.");
	Argument biome(AT_PlanetBiome, doc="biome");
	Argument hookID(AT_Hook, "planet_effects::GenericEffect");

	bool instantiate() override {
		if(!withHook(hookID.str))
			return false;
		return GenericEffect::instantiate();
	}

#section server
	bool condition(Object& obj) const override {
		if (obj is null) {
			return false;
		}
		if (obj.isPlanet) {
			int biome_id = getBiomeID(biome.str);
			if (biome_id == -1) {
				return false;
			}
			uint id = int(biome_id);
			Planet@ planet = cast<Planet>(obj);
			return planet.Biome0 == id || planet.Biome1 == id || planet.Biome2 == id;
		}
		return false;
	}
#section all
};


class ConsumePlanetResource : AbilityHook {
	Document doc("Removes a planet resource from the object casting the ability.");
	Argument resource(AT_PlanetResource, doc="Type of resource to consume.");
	Argument objTarg(TT_Object);

	bool canActivate(const Ability@ abl, const Targets@ targs, bool ignoreCost) const override {
		if(abl.obj is null)
			return false;

		if (abl.obj.isPlanet) {
			Planet@ planet = cast<Planet>(abl.obj);
			array<Resource> planetResources;
			planetResources.syncFrom(planet.getNativeResources());
			for (uint i = 0, cnt = planetResources.length; i < cnt; i++) {
				auto planetResourceType = planetResources[i].type;
				if (planetResourceType.id == uint(resource.integer)) {
					return true;
				}
			}
		}
		return false;
	}

#section server
	void activate(Ability@ abl, any@ data, const Targets@ targs) const override {
		if(abl.obj is null)
			return;

		// remove planet resource from abl.obj
		if (abl.obj.isPlanet) {
			Planet@ planet = cast<Planet>(abl.obj);
			array<Resource> planetResources;
			planetResources.syncFrom(planet.getNativeResources());
			for (uint i = 0, cnt = planetResources.length; i < cnt; i++) {
				auto planetResourceType = planetResources[i].type;
				if (planetResourceType.id == uint(resource.integer)) {
					// native resources are identified differently to their
					// type identifier
					planet.removeResource(planetResources[i].id);
					return;
				}
			}
		}
	}
#section all
};

tidy final class UpdatedValue {
	double value = 0;
	double timer = 0;
}

class ModEfficiencyDistanceToOwnedPlanets : GenericEffect {
	Document doc("Modify the efficiency of the fleet based on the distance to the nearest owned planet.");
	Argument minrange_efficiency(AT_Decimal, doc="Efficiency at minimum range.");
	Argument maxrange_efficiency(AT_Decimal, doc="Efficiency at maximum range.");
	Argument minrange(AT_Decimal, doc="Minimum range for min efficiency.");
	Argument maxrange(AT_Decimal, doc="Maximum range for max efficiency.");

#section server
	void enable(Object& obj, any@ data) const override {
		UpdatedValue value;
		data.store(@value);
	}

	void tick(Object& obj, any@ data, double time) const override {
		UpdatedValue@ value;
		data.retrieve(@value);

		value.timer -= time;
		if(value.timer <= 0) {
			value.timer = randomd(0.5, 5.0);

			double prevValue = value.value;
			double dist = maxrange.decimal;

			// determine closest planet distance
			Object@ planet;
			DataList@ objs = obj.owner.getPlanets();
			while (receive(objs, planet)) {
				if (planet.isPlanet) {
					double planet_dist = planet.position.distanceTo(obj.position);
					if (planet_dist < dist) {
						dist = planet_dist;
						// no need to store the planet
					}
				}
			}

			if(dist <= minrange.decimal) {
				value.value = minrange_efficiency.decimal;
			}
			else if(dist >= maxrange.decimal) {
				value.value = maxrange_efficiency.decimal;
			}
			else {
				double pct = (dist - minrange.decimal) / (maxrange.decimal - minrange.decimal);
				value.value = minrange_efficiency.decimal + pct * (maxrange_efficiency.decimal - minrange_efficiency.decimal);
			}

			if(prevValue != value.value)
				obj.modFleetEffectiveness(value.value - prevValue);
		}
	}

	void disable(Object& obj, any@ data) const override {
		UpdatedValue@ value;
		data.retrieve(@value);

		if(value.value > 0) {
			obj.modFleetEffectiveness(-value.value);
			value.value = 0;
		}
	}

	void save(any@ data, SaveFile& file) const override {
		UpdatedValue@ value;
		data.retrieve(@value);
		file << value.value;
		file << value.timer;
	}

	void load(any@ data, SaveFile& file) const override {
		UpdatedValue value;
		file >> value.value;
		file >> value.timer;
		data.store(value);
	}
#section all
};

// Cache system defs to check things are unlocked
const SubsystemDef@ hyperdriveSubsystem = getSubsystemDef("Hyperdrive");
const SubsystemDef@ jumpdriveSubsystem = getSubsystemDef("Jumpdrive");
const SubsystemDef@ gateSubsystem = getSubsystemDef("GateModule");
const SubsystemDef@ slipstreamSubsystem = getSubsystemDef("Slipstream");
const SubsystemDef@ warpdriveSubsystem = getSubsystemDef("Warpdrive");

enum FTLUnlock {
	FTLU_Hyperdrive,
	FTLU_Jumpdrive,
	FTLU_Gate,
	FTLU_Slipstream,
	FTLU_Fling,
	FTLU_Warpdrive,
};

// TODO: Add way to exclude the FTL about to be unlocked for all from the pool
class UnlockRandomFTL : EmpireTrigger {
	Document doc("Make the empire this is triggered on gain a random FTL it doesn't yet have.");

#section server
	void activate(Object@ obj, Empire@ emp) const override {
		if (emp is null) {
			return;
		}
		bool hasHyperdrives = emp.isUnlocked(hyperdriveSubsystem);
		bool hasJumpdrives = emp.isUnlocked(jumpdriveSubsystem);
		bool hasGates = emp.isUnlocked(gateSubsystem);
		bool hasFling = emp.HasFling >= 1;
		bool hasSlipstreams = emp.isUnlocked(slipstreamSubsystem);
		bool hasWarpdrive = emp.isUnlocked(slipstreamSubsystem);

		array<FTLUnlock> unlockPool = array<FTLUnlock>();
		if (!hasHyperdrives)
			unlockPool.insertLast(FTLU_Hyperdrive);
		if (!hasJumpdrives)
			unlockPool.insertLast(FTLU_Jumpdrive);
		if (!hasGates)
			unlockPool.insertLast(FTLU_Gate);
		if (!hasSlipstreams)
			unlockPool.insertLast(FTLU_Slipstream);
		if (!hasFling)
			unlockPool.insertLast(FTLU_Fling);

		if (unlockPool.length == 0) {
			if (!hasWarpdrive) {
				unlockPool.insertLast(FTLU_Warpdrive);
			} else {
				// How did this user unlock all the FTL types and still try to
				// win this vote?
				// TODO: Some consolation prize
				return;
			}
		}

		// randomi generates a number in the inclusive range
		int randomSelection = randomi(0, unlockPool.length - 1);
		uint unlock = unlockPool[randomSelection];

		// mark the empire attribute as unlocked, and unlock the subsystem
		if (unlock == FTLU_Hyperdrive) {
			emp.setUnlocked(hyperdriveSubsystem, true);
			emp.modAttribute(EA_ResearchUnlockedHyperdrive, AC_Add, 1);
			if(emp.player is null)
				return;
			sendClientMessage(emp.player, "Hyperdrives unlocked", "You have unlocked Hyperdrives through a galactic senate vote");
		}
		if (unlock == FTLU_Jumpdrive) {
			emp.setUnlocked(jumpdriveSubsystem, true);
			emp.modAttribute(EA_ResearchUnlockedJumpdrive, AC_Add, 1);
			if(emp.player is null)
				return;
			sendClientMessage(emp.player, "Jumpdrives unlocked", "You have unlocked Jumpdrives through a galactic senate vote");
		}
		if (unlock == FTLU_Gate) {
			emp.setUnlocked(gateSubsystem, true);
			emp.modAttribute(EA_ResearchUnlockedGate, AC_Add, 1);
			if(emp.player is null)
				return;
			sendClientMessage(emp.player, "Gates unlocked", "You have unlocked Gates through a galactic senate vote");
		}
		if (unlock == FTLU_Slipstream) {
			emp.setUnlocked(slipstreamSubsystem, true);
			emp.modAttribute(EA_ResearchUnlockedSlipstream, AC_Add, 1);
			if(emp.player is null)
				return;
			sendClientMessage(emp.player, "Slipstreams unlocked", "You have unlocked Slipstreams through a galactic senate vote");
		}
		if (unlock == FTLU_Fling) {
			int hasFlingUnlockTagID = getUnlockTag("HasFling", false);
			emp.setTagUnlocked(hasFlingUnlockTagID, true);
			emp.modAttribute(EA_HasFling, AC_Add, 1);
			emp.modAttribute(EA_ResearchUnlockedFling, AC_Add, 1);
			if(emp.player is null)
				return;
			sendClientMessage(emp.player, "Fling Beacons unlocked", "You have unlocked Fling Beacons through a galactic senate vote");
		}
		if (unlock == FTLU_Warpdrive) {
			emp.setUnlocked(warpdriveSubsystem, true);
			emp.modAttribute(EA_ResearchUnlockedWarpdrive, AC_Add, 1);
			if(emp.player is null)
				return;
			sendClientMessage(emp.player, "Warpdrives unlocked", "You have unlocked Warpdrives through a galactic senate vote");
		}
	}
#section all
};

class TransferAllResourcesAndAbandon : AbilityHook {
	Document doc("Queue up all available resource transfer abilities onto the target then abandon this object.");
	Argument objTarget(TT_Object, doc="Target to cast ability on.");

#section server
	void activate(Ability@ abl, any@ data, const Targets@ targs) const override {
		if(abl.obj is null)
			return;

		auto@ targ = objTarget.fromConstTarget(targs);
		if(targ is null || targ.obj is null)
			return;

		if (!abl.obj.isPlanet)
		 	return;

		Planet@ planet = cast<Planet>(abl.obj);

		array<Ability> abilities;
		abilities.syncFrom(abl.obj.getAbilities());

		int abandonAbility = -1;
		for (uint i = 0, cnt = abilities.length; i < cnt; ++i) {
			if (abilities[i].type.ident == "AbilityAbandon") {
				abandonAbility = abilities[i].id;
			}
		}

		// Queue up orders for each resource transfer and then abandon
		filterToResourceTransferAbilities(abilities);

		// Build up a map of planet resource type ids to occurrences,
		// to find out if a particular resource is present multiple times
		// on this planet already
		array<Resource> planetResources;
		ArrayMap resourceOccurances = ArrayMap();
		planetResources.syncFrom(planet.getNativeResources());
		for (uint i = 0, cnt = planetResources.length; i < cnt; i++) {
			auto planetResourceType = planetResources[i].type;
			resourceOccurances.increment(planetResourceType.id);
		}

		for (uint i = 0, cnt = abilities.length; i < cnt; ++i) {
			Ability@ transferAbility = abilities[i];
			if (transferAbility.type.resource is null) {
				// Error in ability definition?
				continue;
			}
			uint resourceTypeID = transferAbility.type.resource.id;
			uint resourceCount = 1;
			if (resourceOccurances.has(resourceTypeID)) {
				resourceCount = resourceOccurances.get(resourceTypeID);
			}
			// Queue up as many copies of this ability as we have occurances
			// of the resource the ability transfers
			for (uint j = 0; j < resourceCount; j++) {
				abl.obj.addAbilityOrder(transferAbility.id, targ.obj, true);
			}
		}
		abl.obj.addAbilityOrder(abandonAbility, abl.obj, true);
	}
#section all
};

class RequireNotHomeworld : Requirement {
	Document doc("Can only be built on planets that are not the homeworld.");

	bool meets(Object& obj, bool ignoreState = false) const override {
		if (obj is null || !obj.isPlanet || obj.owner is null || obj.owner.Homeworld is null) {
			return false;
		}
		Planet@ planet = cast<Planet>(obj);
		return obj.owner.Homeworld.id != planet.id;
	}
};

class RequireHomeworld : Requirement {
	Document doc("Can only be built on planets that are the homeworld.");

	bool meets(Object& obj, bool ignoreState = false) const override {
		if (obj is null || !obj.isPlanet || obj.owner is null || obj.owner.Homeworld is null) {
			return false;
		}
		Planet@ planet = cast<Planet>(obj);
		return obj.owner.Homeworld.id == planet.id;
	}
};

class RequireUndevelopedTiles : Requirement {
	Document doc("Can only be built on planets with undeveloped tiles remaining.");

	bool meets(Object& obj, bool ignoreState = false) const override {
		if (obj is null || !obj.isPlanet) {
			return false;
		}
		Planet@ planet = cast<Planet>(obj);
		return planet.hasUndevelopedSurfaceTiles;
	}
};

class PickupSpecificCargoFrom : AbilityHook {
	Document doc("Pick up all cargo of a type from the target object, as much as possible.");
	Argument cargo_type(AT_Cargo, doc="Type of cargo to pickup.");
	Argument targ(TT_Object);

#section server
	void activate(Ability@ abl, any@ data, const Targets@ targs) const override {
		auto@ objTarg = targ.fromConstTarget(targs);
		if(objTarg is null || objTarg.obj is null)
			return;
		Object@ other = objTarg.obj;
		if(!other.hasCargo || abl.obj is null || !abl.obj.hasCargo)
			return;
		other.transferCargoTo(cargo_type.integer, abl.obj);
	}
#section all
};

class TransferSpecificCargoTo : AbilityHook {
	Document doc("Transfer all cargo of a type to the target object, as much as possible.");
	Argument cargo_type(AT_Cargo, doc="Type of cargo to transfer.");
	Argument targ(TT_Object);

#section server
	void activate(Ability@ abl, any@ data, const Targets@ targs) const override {
		auto@ objTarg = targ.fromConstTarget(targs);
		if(objTarg is null || objTarg.obj is null)
			return;
		Object@ other = objTarg.obj;
		if(!other.hasCargo || abl.obj is null || !abl.obj.hasCargo)
			return;
		abl.obj.transferCargoTo(cargo_type.integer, other);
	}
#section all
};

class TargetFilterHasSpecificCargoStored : TargetFilter {
	Document doc("Only allow targets that have some type of cargo stored.");
	Argument cargo_type(AT_Cargo, doc="Type of cargo to have.");
	Argument objTarg(TT_Object);

	string getFailReason(Empire@ emp, uint index, const Target@ targ) const override {
		return locale::NTRG_CARGO;
	}

	bool isValidTarget(Empire@ emp, uint index, const Target@ targ) const override {
		if(index != uint(objTarg.integer))
			return true;
		if(targ.obj is null)
			return false;
		if(!targ.obj.hasCargo)
			return false;
		if(targ.obj.cargoStored < 0.001)
			return false;
		return targ.obj.getCargoStored(cargo_type.integer) > 0;
	}
};

class RequireHeldSpecificCargo : AbilityHook {
	Document doc("Ability can only be used if cargo space contains a type of cargo.");
	Argument cargo_type(AT_Cargo, doc="Type of cargo to have.");

	bool canActivate(const Ability@ abl, const Targets@ targs, bool ignoreCost) const override {
		if(abl.obj is null || !abl.obj.hasCargo)
			return false;
		return abl.obj.getCargoStored(cargo_type.integer) >= 0.001;
	}
};
