import empire_ai.weasel.WeaselAI;
import empire_ai.weasel.Orbitals;
import empire_ai.weasel.Planets;

import abilities;
from ai.abilities import AbilitiesAI, AsCreatedCard;

/**
 * CE mod code for the AI to track abilities on objects it owns.
 *
 * TODO: Fleets can have abilities too!
 */

class AbilityAI {
	Object@ obj;
	array<const AbilityType@> abilities;

	bool init(AI& ai, AbilitiesComponent& abilitiesComponent) {
		return checkAbilities();
	}

	/**
	 * Checks the object for abilities the AI knows how to use, returning
	 * true if some were found.
	 */
	bool checkAbilities() {
		if (obj is null) {
			return false;
		}

		if (obj.hasAbilities) {
			this.abilities.length = 0;

			array<Ability> abilities;
			abilities.syncFrom(obj.getAbilities());

			for (uint i = 0, cnt = abilities.length; i < cnt; ++i) {
				Ability@ ability = abilities[i];
				const AbilityType@ type = ability.type;

				if (type is null)
					continue;

				if (type.ai.length == 0)
					continue;

				this.abilities.insertLast(type);

				for (uint j = 0, jcnt = type.ai.length; j < jcnt; ++j) {
					auto@ hook = cast<AbilitiesAI>(type.ai[j]);
					if (hook !is null) {
						auto@ buyCard = cast<AsCreatedCard>(hook);
						if (buyCard !is null) {
							// TODO
						}
					}
				}
			}
		}

		return this.abilities.length > 0;
	}

	void save(AbilitiesComponent& abilitiesComponent, SaveFile& file) {
		file << obj;
	}

	void load(AbilitiesComponent& abilitiesComponent, SaveFile& file) {
		file >> obj;
	}

	void remove(AI& ai, AbilitiesComponent& abilitiesComponent) {
		abilitiesComponent.removedAbilityAI(this);
	}

	void tick(AI& ai, AbilitiesComponent& abilitiesComponent) {
		//Deal with losing object ownership or no longer having abilities
		if(obj is null || !obj.valid || obj.owner !is ai.empire || !obj.hasAbilities) {
			abilitiesComponent.remove(this);
			return;
		}

		// Refresh our info on the abilities this object has
		bool stillHasAbilities = checkAbilities();

		if (!stillHasAbilities) {
			abilitiesComponent.remove(this);
			return;
		}
	}
}

/**
 * An interface for other components to register themselves as listeners onto
 * the Abilities component so they can respond to events without having to
 * track the lifetimes of everything themselves.
 */
interface AbilitiesEventListener {
	/**
	 * An AbilityAI that was previously tracked is no longer valid for tracking
	 */
	void onRemovedAbilityAI(AbilityAI@ abilityAI);
}

class AbilitiesComponent : AIComponent, PlanetEventListener, OrbitalEventListener {
	Planets@ planets;
	Orbitals@ orbitals;

	array<AbilityAI@> abilityObjects;
	uint abilityObjectIndex = 0;

	uint planetCardCheckIndex = 0;
	uint orbitalCardCheckIndex = 0;

	array<AbilitiesEventListener@> listeners;

	void create() {
		@planets = cast<Planets>(ai.planets);
		@orbitals = cast<Orbitals>(ai.orbitals);
		planets.listeners.insertLast(this);
		orbitals.listeners.insertLast(this);
	}

	Empire@ get_empire() {
		return ai.empire;
	}

	void save(SaveFile& file) {
		file << planetCardCheckIndex;
		file << orbitalCardCheckIndex;
		uint cnt = abilityObjects.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i) {
			auto@ data = abilityObjects[i];
			saveAI(file, data);
			data.save(this, file);
		}
	}

	void load(SaveFile& file) {
		file >> planetCardCheckIndex;
		file >> orbitalCardCheckIndex;
		uint cnt = 0;
		file >> cnt;
		for(uint i = 0; i < cnt; ++i) {
			auto@ data = loadAI(file);
			if(data !is null)
				data.load(this, file);
			else
				AbilityAI().load(this, file);
		}
	}

	AbilityAI@ loadAI(SaveFile& file) {
		Object@ obj;
		file >> obj;

		if(obj is null)
			return null;

		AbilityAI@ data = getAI(obj);
		if(data is null) {
			@data = AbilityAI();
			@data.obj = obj;
			abilityObjects.insertLast(data);
		}
		return data;
	}

	void saveAI(SaveFile& file, AbilityAI@ ai) {
		Object@ obj;
		if(ai !is null)
			@obj = ai.obj;
		file << obj;
	}

	void start() {
	}

	void tick(double time) {

	}

	void turn() {
		if (log) {
			ai.print("Tracking "+string(abilityObjects.length)+" ability objects");
		}
	}

	void focusTick(double time) override {
		// Check through our planets and orbitals one index at a time

		if (abilityObjects.length != 0) {
			abilityObjectIndex = (abilityObjectIndex + 1) % abilityObjects.length;
			AbilityAI@ data = abilityObjects[abilityObjectIndex];
			data.tick(ai, this);
		}

		// Look at the next planet and orbital in our empire
		uint planetCount = planets.planets.length;
		if (planetCount != 0) {
			planetCardCheckIndex = (planetCardCheckIndex + 1) % planetCount;
			PlanetAI@ plAI = planets.planets[planetCardCheckIndex];
			if (plAI !is null && plAI.obj !is null && plAI.obj.hasAbilities) {
				register(plAI.obj);
			}
		}
		uint orbitalCount = orbitals.orbitals.length;
		if (orbitalCount != 0) {
			orbitalCardCheckIndex = (orbitalCardCheckIndex + 1) % orbitalCount;
			OrbitalAI@ orbitalAI = orbitals.orbitals[orbitalCardCheckIndex];
			if (orbitalAI !is null && orbitalAI.obj !is null && orbitalAI.obj.hasAbilities) {
				register(orbitalAI.obj);
			}
		}
	}

	AbilityAI@ getAI(Object& obj) {
		for (uint i = 0, cnt = abilityObjects.length; i < cnt; ++i) {
			if (abilityObjects[i].obj is obj)
				return abilityObjects[i];
		}
		return null;
	}

	AbilityAI@ register(Object& obj) {
		AbilityAI@ data = getAI(obj);
		if (data is null) {
			@data = AbilityAI();
			@data.obj = obj;
			if (data.init(ai, this)) {
				abilityObjects.insertLast(data);
			} else {
				// Object exists but we won't be making an AbilityAI for it
				return null;
			}
		}
		return data;
	}

	void remove(AbilityAI@ data) {
		data.remove(ai, this);
		abilityObjects.remove(data);
	}

	// [[ MODIFY BASE GAME START ]]
	void removedAbilityAI(AbilityAI@ abilityAI) {
		// Tell everything that is listening
		for (uint i = 0, cnt = listeners.length; i < cnt; ++i) {
			listeners[i].onRemovedAbilityAI(abilityAI);
		}
	}

	void onRemovedAbilityObject(Object@ removed) {
		if (removed is null)
			return;
		for (uint i = 0, cnt = abilityObjects.length; i < cnt; ++i) {
			if (abilityObjects[i].obj is removed) {
				abilityObjects[i].remove(ai, this);
				abilityObjects.removeAt(i);
				--i; --cnt;
			}
		}
	}

	void onRemovedPlanetAI(PlanetAI@ plAI) {
		if (plAI !is null) {
			onRemovedAbilityObject(plAI.obj);
		}
	}
	void onRemovedOrbitalAI(OrbitalAI@ orbAI) {
		if (orbAI !is null) {
			onRemovedAbilityObject(orbAI.obj);
		}
	}
	void onConstructionRequestActioned(ConstructionRequest@ request) {}
	// [[ MODIFY BASE GAME END ]]
};

AIComponent@ createAbilities() {
	return AbilitiesComponent();
}
