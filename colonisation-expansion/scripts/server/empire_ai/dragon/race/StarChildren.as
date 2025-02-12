// A quite substantially reworked Star Children AI which fits into the Expansion
// colonisation rework

import empire_ai.weasel.WeaselAI;
import empire_ai.weasel.race.Race;
import empire_ai.weasel.Colonization;
import empire_ai.weasel.Resources;
import empire_ai.weasel.Construction;
import empire_ai.weasel.Development;
import empire_ai.weasel.Fleets;
import empire_ai.weasel.Movement;
import empire_ai.weasel.Planets;
import empire_ai.weasel.Designs;
import empire_ai.dragon.expansion.colonization;
import empire_ai.dragon.expansion.colony_data;
import empire_ai.dragon.expansion.resource_value;
import empire_ai.dragon.logs;

import oddity_navigation;
from abilities import getAbilityID;
from statuses import getStatusID;

// TODO: Should be able to queue habitat missions
// Should use idle motherships for scouting, especially when we run low
// on explored neighbouring systems and requests are drying up
// Make the AI not put command computers on motherships

double HEALTH_ABORT_THRESHOLD = 0.97;
double HEALTH_MISSION_THRESHOLD = 0.99;

// TODO: Idle motherships need to be kept out of danger too
// and we should avoid ordering motherships into danger

class HabitatMission : Mission {
	Planet@ target;
	MoveOrder@ move;
	double timer = 0.0;
	uint retries = 0;
	double targetPopAtLastRetry = 0;

	void save(Fleets& fleets, SaveFile& file) override {
		file << target;
		file << timer;
		fleets.movement.saveMoveOrder(file, move);
		file << retries;
		file << targetPopAtLastRetry;
	}

	void load(Fleets& fleets, SaveFile& file) override {
		file >> target;
		file >> timer;
		@move = fleets.movement.loadMoveOrder(file);
		file >> retries;
		file >> targetPopAtLastRetry;
	}

	void start(AI& ai, FleetAI& fleet) override {
		uint priority = MP_Normal;
		if (gameTime < 30.0 * 60.0)
			priority = MP_Critical;
		@move = cast<Movement>(ai.movement).move(fleet.obj, target, priority);
	}

	void tick(AI& ai, FleetAI& fleet, double time) override {
		if (fleet.flagshipHealth < HEALTH_ABORT_THRESHOLD) {
			if (LOG) {
				ai.print("Aborted habitat mission, took too much damage", fleet.obj);
			}
			onCancel(ai);
			cast<Fleets>(ai.fleets).returnToBase(fleet, MP_Critical);
			return;
		}
		if(move !is null) {
			if(move.failed) {
				retries += 1;
				@move = cast<Movement>(ai.movement).move(fleet.obj, target, priority);
				if (retries > 2) {
					// just hope for the best I guess, this seems to fail sporadically
					// when planets orbit slightly away from us rather than us not
					// actually making it to them
					int ablId = cast<StarChildren2>(ai.race).habitatAbilityID;
					fleet.obj.activateAbilityTypeFor(ai.empire, ablId, target);

					@move = null;
					timer = gameTime + 30.0;
					retries = 0;
				}
			} else if (move.completed) {
				int ablId = cast<StarChildren2>(ai.race).habitatAbilityID;
				fleet.obj.activateAbilityTypeFor(ai.empire, ablId, target);

				@move = null;
				timer = gameTime + 30.0;
				retries = 0;
			}
		}
		else {
			if(target is null || !target.valid || target.quarantined
					|| (target.owner !is ai.empire && target.owner.valid)
					|| target.inCombat) {
				onCancel(ai);
				return;
			}

			double maxPop = max(double(target.maxPopulation), double(getPlanetLevel(target, target.primaryResourceLevel).population));
			double curPop = target.population;
			if(curPop >= maxPop) {
				completed = true;
				return;
			}

			if(gameTime >= timer) {
				// keep trying up to a limit, as we may be trying to add a lot of
				// population our mothership currently lacks, and so may need to idle
				// at the planet for a while
				bool makingProgress = curPop > targetPopAtLastRetry;
				if (retries > 6) {
					// give up
					onCancel(ai);
					return;
				}
				// try again, maybe we didn't have enough pop?
				int ablId = cast<StarChildren2>(ai.race).habitatAbilityID;
				fleet.obj.activateAbilityTypeFor(ai.empire, ablId, target);
				timer = gameTime + 60.0;
				if (!makingProgress) {
					retries += 1;
				}
				targetPopAtLastRetry = curPop;
			}
		}
	}

	void onCancel(AI& ai) {
		canceled = true;
		if (target !is null && target.valid && target.owner !is ai.empire) {
			// if we cancel notify Expansion so it can respond immediately
			// instead of it waiting for a timeout before it realises
			auto@ expansion = cast<ColonizationAbilityOwner>(ai.colonization);
			if (LOG) {
				ai.print("Colonize failed at "+target.name);
			}
			expansion.onColonizeFailed(target);
		}
	}
};

class MothershipColonizer : ColonizationSource {
	FleetAI@ mothership;

	MothershipColonizer(FleetAI@ mothership) {
		@this.mothership = mothership;
	}

	vec3d getPosition() {
		return mothership.obj.position;
	}

	bool valid(AI& ai) {
		return mothership.obj.valid && mothership.obj.owner is ai.empire;
	}

	string toString() {
		return mothership.obj.name;
	}

	bool idle() {
		return mothership.mission is null;
	}

	bool inGoodHealth() {
		return mothership.flagshipHealth > HEALTH_MISSION_THRESHOLD;
	}
}

class StarChildren2 : Race, ColonizationAbility, RaceResourceValuation {
	IColonization@ colonization;
	Construction@ construction;
	IDevelopment@ development;
	Movement@ movement;
	Planets@ planets;
	Fleets@ fleets;
	Designs@ designs;
	Resources@ resources;

	DesignTarget@ mothershipDesign;
	double idleSince = 0;

	array<ColonizationSource@> motherships;

	int habitatAbilityID = -1;
	int mothershipPopulationID = -1;
	int habitatPopulationID = -1;

	array<Planet@> popRequests;
	array<Planet@> laborPlanets;

	BuildFlagship@ mcBuild;
	BuildOrbital@ yardBuild;

	bool gotHomeworld = false;

	// Weasel Star Children AI moved the motherships to labor sources
	// and made itself colonise way too slowly
	// Dragon Star Children AI moves the labor sources to the motherships ;)
	array<ExportData@> laborMissionResources;
	uint laborMissionResourcesIndex = 0;
	double lastLaborMission = 0;

	void save(SaveFile& file) override {
		designs.saveDesign(file, mothershipDesign);
		file << idleSince;
		construction.saveConstruction(file, mcBuild);
		construction.saveConstruction(file, yardBuild);

		uint cnt = motherships.length;
		file << cnt;
		for (uint i = 0; i < cnt; ++i) {
			MothershipColonizer@ mothership = cast<MothershipColonizer>(motherships[i]);
			fleets.saveAI(file, mothership.mothership);
		}
		file << gotHomeworld;

		cnt = laborMissionResources.length;
		file << cnt;
		for(uint i = 0; i < cnt; ++i)
			resources.saveExport(file, laborMissionResources[i]);
		file << laborMissionResourcesIndex;
		file << lastLaborMission;
	}

	void load(SaveFile& file) override {
		@mothershipDesign = designs.loadDesign(file);
		file >> idleSince;
		@mcBuild = cast<BuildFlagship>(construction.loadConstruction(file));
		@yardBuild = cast<BuildOrbital>(construction.loadConstruction(file));

		uint cnt = 0;
		file >> cnt;
		for(uint i = 0; i < cnt; ++i) {
			auto@ flAI = fleets.loadAI(file);
			if (flAI !is null)
				motherships.insertLast(MothershipColonizer(flAI));
		}
		file >> gotHomeworld;

		file >> cnt;
		for(uint i = 0; i < cnt; ++i) {
			auto@ data = resources.loadExport(file);
			laborMissionResources.insertLast(data);
		}
		file >> laborMissionResourcesIndex;
		file >> lastLaborMission;
	}

	void create() override {
		@colonization = cast<IColonization>(ai.colonization);
		@construction = cast<Construction>(ai.construction);
		@development = cast<IDevelopment>(ai.development);
		@movement = cast<Movement>(ai.movement);
		@planets = cast<Planets>(ai.planets);
		@fleets = cast<Fleets>(ai.fleets);
		@designs = cast<Designs>(ai.designs);
		@resources = cast<Resources>(ai.resources);

		development.ManagePlanetPressure = false;
		development.BuildBuildings = false;

		@ai.defs.Factory = null;
		@ai.defs.LaborStorage = null;

		habitatAbilityID = getAbilityID("MothershipColonize");
		mothershipPopulationID = getStatusID("MothershipPopulation");
		habitatPopulationID = getStatusID("StarHabitats");

		// Register ourselves as overriding the colony management
		// and resource valuation
		auto@ expansion = cast<ColonizationAbilityOwner>(ai.colonization);
		expansion.setColonyManagement(this);
		auto@ valuation = cast<ResourceValuationOwner>(ai.colonization);
		valuation.setResourceValuation(this);
	}

	void start() override {
		// Design a mothership
		// Code borrowed from Verdant to look through our default designs
		// to find the predesigned small mothership
		// TODO: Add lightly armored designs and use those instead so the AI
		// is less prone to suiciding its motherships by accident
		ReadLock lock(ai.empire.designMutex);
		for(uint i = 0, cnt = ai.empire.designCount; i < cnt; ++i) {
			const Design@ dsg = ai.empire.getDesign(i);
			if(dsg.newer !is null)
				continue;
			if(dsg.updated !is null)
				continue;

			uint goal = designs.classify(dsg, DP_Unknown);
			if(goal == DP_Unknown)
				continue;

			if (goal == DP_Mothership && dsg.size == 500) {
				@mothershipDesign = DesignTarget();
				mothershipDesign.set(dsg);
			}
		}

		// a second mothership doubles early expansion rates
		construction.buildFlagship(mothershipDesign, force=true);
	}

	bool requiresPopulation(Planet& target) {
		double maxPop = max(double(target.maxPopulation), double(getPlanetLevel(target, target.primaryResourceLevel).population));
		double curPop = target.population;
		return curPop < maxPop;
	}

	int findMothership(FleetAI@ fleet) {
		for (uint i = 0, cnt = motherships.length; i < cnt; ++i) {
			MothershipColonizer@ mothership = cast<MothershipColonizer>(motherships[i]);
			if (mothership.mothership is fleet) {
				return i;
			}
		}
		return -1;
	}

	void turn() {
		lookToBuildNewMotherships();
	}

	uint chkInd = 0;
	void focusTick(double time) override {
		checkMotherships();
		checkOwnedPlanets();
		addNeededPopulation();
		checkGotHomeworld();
		moveLaborToMotherships();
	}

	void checkMotherships() {
		// Detect motherships
		for (uint i = 0, cnt = fleets.fleets.length; i < cnt; ++i) {
			auto@ flAI = fleets.fleets[i];
			if (flAI.fleetClass != FC_Mothership)
				continue;

			if (findMothership(flAI) == -1) {
				// Add to our tracking list
				flAI.obj.autoFillSupports = false;
				flAI.obj.allowFillFrom = false;
				motherships.insertLast(MothershipColonizer(flAI));

				// Add as a factory
				construction.registerFactory(flAI.obj);
			}
		}

		// Stop tracking invalid motherships
		for (uint i = 0, cnt = motherships.length; i < cnt; ++i) {
			MothershipColonizer@ mothership = cast<MothershipColonizer>(motherships[i]);
			Object@ obj = mothership.mothership.obj;
			if (obj is null || !mothership.valid(ai)) {
				// TODO: Cancel any colonise requests set for this ship
				motherships.removeAt(i);
				--i; --cnt;
			}
		}
	}

	void checkOwnedPlanets() {
		// Detect planets that require more population
		for (uint i = 0, cnt = popRequests.length; i < cnt; ++i) {
			auto@ obj = popRequests[i];
			if (obj is null || !obj.valid || obj.owner !is ai.empire) {
				popRequests.removeAt(i);
				--i; --cnt;
				continue;
			}
			if (!requiresPopulation(obj)) {
				popRequests.removeAt(i);
				--i; --cnt;
				continue;
			}
		}

		for (uint i = 0, cnt = laborPlanets.length; i < cnt; ++i) {
			auto@ obj = laborPlanets[i];
			if (obj is null || !obj.valid || obj.owner !is ai.empire) {
				laborPlanets.removeAt(i);
				--i; --cnt;
				continue;
			}
			if (obj.laborIncome < 3.0/60.0) {
				laborPlanets.removeAt(i);
				--i; --cnt;
				continue;
			}
		}

		uint plCnt = planets.planets.length;
		for(uint n = 0, cnt = min(15, plCnt); n < cnt; ++n) {
			chkInd = (chkInd+1) % plCnt;
			auto@ plAI = planets.planets[chkInd];

			//Find planets that need population
			if(requiresPopulation(plAI.obj)) {
				if(popRequests.find(plAI.obj) == -1)
					popRequests.insertLast(plAI.obj);
			}

			//Find planets that have labor
			if(plAI.obj.laborIncome >= 3.0/60.0) {
				if(laborPlanets.find(plAI.obj) == -1)
					laborPlanets.insertLast(plAI.obj);
			}
		}
	}

	void addNeededPopulation() {
		for(uint i = 0, cnt = popRequests.length; i < cnt; ++i) {
			Planet@ dest = popRequests[i];
			if(isColonizing(dest))
				continue;
			if(dest.inCombat)
				continue;

			ColonizationSource@ source = getFastestSource(dest);
			if (source !is null) {
				MothershipColonizer@ mothership = cast<MothershipColonizer>(source);
				if (LOG) {
					ai.print("filling population at "+dest.name+" from "+source.toString());
				}
				HabitatMission miss;
				@miss.target = dest;
				fleets.performMission(mothership.mothership, miss);
			}
		}
	}

	void lookToBuildNewMotherships() {
		//See if we should build new motherships
		uint haveMC = motherships.length;
		// [[ MODIFY BASE GAME START ]]
		uint wantMC = 4;
		// [[ MODIFY BASE GAME END ]]
		if(gameTime > 20.0 * 60.0)
			wantMC += 1;
		// [[ MODIFY BASE GAME START ]]
		wantMC = max(wantMC, uint(gameTime/(30.0*60.0)));
		// [[ MODIFY BASE GAME END ]]

		if (mcBuild !is null && mcBuild.completed)
			@mcBuild = null;
		if (wantMC > haveMC && mcBuild is null)
			@mcBuild = construction.buildFlagship(mothershipDesign, force=true);

		// TODO: The AI already knows how to make shipyards, we should just make that code work for us
		/* if (yardBuild is null && haveMC > 0 && gameTime > 60 && gameTime < 180 && ai.defs.Shipyard !is null) {
			Region@ reg = motherships[0].obj.region;
			if (reg !is null) {
				vec3d pos = reg.position;
				vec2d offset = random2d(reg.radius * 0.4, reg.radius * 0.8);
				pos.x += offset.x;
				pos.z += offset.y;

				@yardBuild = construction.buildOrbital(ai.defs.Shipyard, pos);
			}
		} */
	}

	void checkGotHomeworld() {
		if (gotHomeworld) {
			return;
		}
		// when we get our first planet, request 3 level 0 pressure
		// resources so we can build motherships faster
		if (ai.empire.planetCount > 0) {
			for (uint i = 0, cnt = ai.empire.planetCount; i < cnt; ++i) {
				Planet@ planet = ai.empire.planetList[i];
				if (planet !is null && planet.valid) {
					if (log) {
						ai.print("Requesting labor pressure resources");
					}
					for (uint i = 0; i < 3; ++i) {
						ResourceSpec spec;
						spec.type = RST_Pressure_Level0;
						spec.level = 0;
						spec.pressureType = TR_Labor;
						spec.isForImport = false;
						spec.isLevelRequirement = false;
						resources.requestResource(planet, spec);
					}
					gotHomeworld = true;
					return;
				}
			}
		}
	}

	void moveLaborToMotherships() {
		// only do this on hard difficulty
		if (ai.difficulty < 2) {
			return;
		}

		// Avoid doing this too many times a minute, it takes around a minute
		// per mothership pop anyway, so 25 seconds is more than fast enough
		// to catch our orbiting motherships.
		// Plus this would be quite micro intensive for a player to do at
		// any sort of high efficiency (though I only coded the AI to do this
		// after trying it myself).
		if (gameTime < lastLaborMission + 15) {
			return;
		}
		lastLaborMission = gameTime;

		// Steal level 0 labor pressure resources from the other components
		uint availableResources = resources.available.length;
		if (availableResources > 0) {
			uint index = randomi(0, availableResources - 1);
			ExportData@ res = resources.available[index];
			if (res.usable && res.obj !is null && res.obj.valid && res.obj.owner is ai.empire) {
				if (res.resource.level == 0 && res.resource.exportable && res.resource.tilePressure[TR_Labor] > 0) {
					if (laborMissionResources.find(res) == -1) {
						laborMissionResources.insertLast(res);
						if (res.request !is null) {
							resources.cancelRequest(res.request);
						}
					}
				}
			}
		}
		uint usedResources = resources.used.length;
		if (usedResources > 0) {
			uint index = randomi(0, usedResources - 1);
			ExportData@ res = resources.used[index];
			if (res.usable && res.obj !is null && res.obj.valid && res.obj.owner is ai.empire) {
				if (res.resource.level == 0 && res.resource.exportable && res.resource.tilePressure[TR_Labor] > 0) {
					if (laborMissionResources.find(res) == -1) {
						laborMissionResources.insertLast(res);
						if (res.request !is null) {
							resources.cancelRequest(res.request);
						}
					}
				}
			}
		}

		if (laborMissionResources.length == 0) {
			return;
		}

		// Pick one pressure resource to move per tick
		laborMissionResourcesIndex = (laborMissionResourcesIndex + 1) % laborMissionResources.length;
		ExportData@ res = laborMissionResources[laborMissionResourcesIndex];

		// Remove the resource if it is no longer valid
		if (res.request !is null || res.obj is null || !res.obj.valid || res.obj.owner !is ai.empire || !res.usable) {
			laborMissionResources.removeAt(laborMissionResourcesIndex);
			return;
		}

		for (uint i = 0, cnt = motherships.length; i < cnt; ++i) {
			MothershipColonizer@ mothership = cast<MothershipColonizer>(motherships[i]);
			Object@ obj = mothership.mothership.obj;
			Factory@ f = construction.get(obj);
			if (f is null || f.active is null)
				continue;
			// move level 0 labor resources to motherships in orbit that are
			// building something
			Object@ orbit;
			if (obj.hasOrbit && obj.inOrbit)
				@orbit = obj.getOrbitingAround();
			if (orbit is null && obj.hasMover)
				@orbit = obj.getAroundLockedOrbit();
			if (orbit !is null && orbit.isPlanet) {
				Planet@ orbiting = cast<Planet>(orbit);
				if (LOG) {
					ai.print("Move "+res.resource.name+" from "+res.obj.name, orbiting);
				}
				if (res.obj !is orbiting) {
					res.obj.exportResourceByID(res.resourceId, orbiting);
				} else {
					res.obj.exportResourceByID(res.resourceId, null);
				}
				@res.developUse = orbiting;
			}
		}
	}

	array<ColonizationSource@> getSources() {
		return motherships;
	}

	ColonizationSource@ getClosestSource(vec3d position) {
		MothershipColonizer@ fastest;
		double bestTime = INFINITY;
		for (uint i = 0, cnt = motherships.length; i < cnt; ++i) {
			MothershipColonizer@ mothership = cast<MothershipColonizer>(motherships[i]);
			auto@ flAI = mothership.mothership;
			// FIXME: We really need to be able to queue missions to maximise our usage
			// of our motherships
			if (flAI.mission !is null) {
				continue;
			}
			if (!mothership.inGoodHealth()) {
				continue;
			}

			double travelTime = movement.getApproximateETA(flAI.obj, position);
			if (travelTime < bestTime) {
				@fastest = mothership;
				bestTime = travelTime;
			}
		}
		return fastest;
	}

	ColonizationSource@ getFastestSource(Planet@ colony) {
		if (colony is null) {
			return null;
		}
		MothershipColonizer@ fastest;
		double maxPop = max(double(colony.maxPopulation), double(getPlanetLevel(colony, colony.primaryResourceLevel).population));
		double curPop = colony.population;
		double needPop = maxPop - curPop;
		double bestTime = INFINITY;
		for (uint i = 0, cnt = motherships.length; i < cnt; ++i) {
			MothershipColonizer@ mothership = cast<MothershipColonizer>(motherships[i]);
			auto@ flAI = mothership.mothership;
			// FIXME: We really need to be able to queue missions to maximise our usage
			// of our motherships
			if (flAI.mission !is null) {
				continue;
			}
			if (!mothership.inGoodHealth()) {
				continue;
			}

			double travelTime = movement.getApproximateETA(flAI.obj, colony.position);

			int mothershipPopulation = flAI.obj.getStatusStackCountAny(mothershipPopulationID);

			if (mothershipPopulation <= needPop) {
				// FIXME: This should check the max pop of the mothership
				double popOnJourneyTime = travelTime / 60.0;
				if (mothershipPopulation + popOnJourneyTime < needPop) {
					travelTime += 60 * ((mothershipPopulation + popOnJourneyTime) - needPop);
				}
			}

			if (travelTime < bestTime) {
				@fastest = mothership;
				bestTime = travelTime;
			}
		}
		return fastest;
	}

	void colonizeTick() {
		// Don't need to do anything here
	}

	void orderColonization(ColonizeData@ data, ColonizationSource@ source) {
		MothershipColonizer@ mothership = cast<MothershipColonizer>(source);
		ColonizeData2@ _data = cast<ColonizeData2>(data);
		if (_data !is null) {
			@_data.colonizeUnit = mothership;
		}
		HabitatMission miss;
		@miss.target = data.target;
		fleets.performMission(mothership.mothership, miss);
	}

	void saveSource(SaveFile& file, ColonizationSource@ source) {
		if (source !is null) {
			file.write1();
			MothershipColonizer@ mothership = cast<MothershipColonizer>(source);
			// just save the fleet
			fleets.saveAI(file, mothership.mothership);
		} else {
			file.write0();
		}
	}

	ColonizationSource@ loadSource(SaveFile& file) {
		if (file.readBit()) {
			// read back the fleet
			auto@ flAI = fleets.loadAI(file);
			if (flAI !is null) {
				return MothershipColonizer(flAI);
			}
		}
		return null;
	}

	// We save our state in our save and load methods
	void saveManager(SaveFile& file) {}
	void loadManager(SaveFile& file) {}

	uint idleMothershipCount() {
		uint count = 0;
		for(uint i = 0, cnt = motherships.length; i < cnt; ++i) {
			MothershipColonizer@ mothership = cast<MothershipColonizer>(motherships[i]);
			if (mothership.idle()) {
				count += 1;
			}
		}
		return count;
	}

	bool isColonizing(Planet& dest) {
		for(uint i = 0, cnt = motherships.length; i < cnt; ++i) {
			MothershipColonizer@ mothership = cast<MothershipColonizer>(motherships[i]);
			auto@ flAI = mothership.mothership;
			auto@ miss = cast<HabitatMission>(flAI.mission);
			if(miss !is null && miss.target is dest)
				return true;
		}
		return false;
	}

	// Methods for RaceResourceValuation
	double modifyValue(const ResourceType@ resource, double currentValue) {
		return currentValue; // TODO: penalise resources like quartz and peklem
	}

	double devalueEnergyCosts(double energyCost, double currentValue) {
		return currentValue; // star children don't pay ice giant energy upkeep
	}

	bool canSafelyColonize(SystemAI@ sys) {
		// seenPresent is a cache of the PlanetsMask of this system
		uint presentMask = sys.seenPresent;
		bool isOwned = presentMask & ai.mask != 0;
		if (isOwned) {
			return true;
		} else {
			if(!ai.behavior.colonizeEnemySystems && (presentMask & ai.enemyMask) != 0)
				return ai.behavior.aggressive; // assume the worst, that this system is actually guarded
			if(!ai.behavior.colonizeNeutralOwnedSystems && (presentMask & ai.neutralMask) != 0)
				return ai.behavior.aggressive;
			if(!ai.behavior.colonizeAllySystems && (presentMask & ai.allyMask) != 0)
				return false; // lets be nice to our allies
			return true;
		}
	}
};

AIComponent@ createStarChildren2() {
	return StarChildren2();
}
