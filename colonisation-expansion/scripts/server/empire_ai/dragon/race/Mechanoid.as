import empire_ai.weasel.WeaselAI;
import empire_ai.weasel.race.Race;

import empire_ai.weasel.Resources;
import empire_ai.weasel.Colonization;
import empire_ai.weasel.Construction;
import empire_ai.weasel.Movement;
import empire_ai.weasel.Planets;
import empire_ai.weasel.Budget;

import empire_ai.dragon.expansion.colonization;
import empire_ai.dragon.expansion.colony_data;

import resources;
import abilities;
import planet_levels;
from constructions import getConstructionType, ConstructionType;
from abilities import getAbilityID;
import oddity_navigation;

const double MAX_POP_BUILDTIME = 3.0 * 60.0;

// Simplified mirror of transfer cost formula for use in Mechanoid AI
double transferCost(Object@ obj, Empire@ emp, Object@ target) {
	if (target is null || obj is null) {
		return INFINITY;
	}
	double cost = 20;
	double dist = getPathDistance(emp, target.position, obj.position);
	cost += 0.002 * dist;
	if (emp !is null) {
		Region@ myReg = obj.region;
		if (myReg !is null && myReg.FreeFTLMask & emp.mask != 0)
			return 0.0;
	}
	return cost;
}

int colonizeAbilityID = -1;
const ConstructionType@ buildPop;

class ColonizerMechanoidPlanet : ColonizationSource {
	Planet@ planet;

	ColonizerMechanoidPlanet(Planet@ planet) {
		@this.planet = planet;
	}

	vec3d getPosition() {
		return planet.position;
	}

	bool valid(AI& ai) {
		return planet.owner is ai.empire;
	}

	string toString() {
		return planet.name;
	}

	// How useful this planet is for colonising others, (ie sufficient pop)
	double weight(AI& ai) {
		if(!valid(ai))
			return 0.0;
		if(planet.isColonizing)
			return 0.0;
		if(planet.population <= 1)
			return 0.0;
		if(!planet.canSafelyColonize)
			return 0.0;
		double pop = planet.population;
		double maxPop = planet.maxPopulation;
		if (pop <= maxPop) {
			return 0.0;
		}
		return (pop / maxPop) - 1.0;
	}

	bool transferPop(uint amount, PopulationRequest@ request, AI& ai) {
		Planet@ target = request.source.planet;
		double ftlCost = transferCost(planet, ai.empire, target);
		while (amount > 0) {
			if (ftlCost <= ai.empire.FTLStored) {
				if (true)
					ai.print("Transfering population to "+target.name, planet);
				planet.activateAbilityTypeFor(ai.empire, colonizeAbilityID, target);
				amount -= 1;
				request.neededPopulation -= 1;
			} else {
				return false;
			}
		}
		return true;
	}

	// Spare pop is pop exceeding max
	double sparePop() {
		return planet.population - planet.maxPopulation;
	}

	// Checks if a planet has good enough labor production that we want to
	// build pop exceeding its max population to colonise with
	bool isGoodForPopulationProduction(Construction@ construction) {
		if(buildPop is null)
			return false;
		if(!buildPop.canBuild(planet, ignoreCost=true))
			return false;
		// primary factory should always be considered enough labor income
		// (mostly useful in early game when we only have our homeworld)
		auto@ primaryFactory = construction.primaryFactory;
		if (primaryFactory !is null && planet is primaryFactory.obj)
			return true;

		double laborCost = buildPop.getLaborCost(planet);
		double laborIncome = planet.laborIncome;
		return laborCost < laborIncome * MAX_POP_BUILDTIME;
	}
}

// Pop requests are made when a planet doesn't have enough pop to meet its resource level
class PopulationRequest {
	ColonizerMechanoidPlanet@ source;
	double neededPopulation;

	PopulationRequest(ColonizerMechanoidPlanet@ source, double neededPopulation) {
		@this.source = source;
		this.neededPopulation = neededPopulation;
	}

	bool valid(AI& ai) {
		return neededPopulation > 0 && source.valid(ai);
	}
}

class Mechanoid2 : Race, ColonizationAbility {
	IColonization@ colonization;
	Construction@ construction;
	Movement@ movement;
	Budget@ budget;
	Planets@ planets;

	const ResourceType@ unobtanium;
	const ResourceType@ crystals;
	int unobtaniumAbl = -1;

	/* const ResourceClass@ foodClass;
	const ResourceClass@ waterClass;
	const ResourceClass@ scalableClass; */

	//const AbilityType@ colonizeAbility = getAbilityType("MechanoidColonize");

	/* array<Planet@> popRequests;
	array<Planet@> popSources;
	array<Planet@> popFactories; */

	// wrapper around potential source to implement the colonisation ability
	// interfaces, tracks our planets that are populated enough to colonise with
	array<ColonizationSource@> planetSources;
	uint planetIndex = 0;
	uint sourceIndex = 0;

	// population requests, this is not saved to file as we will repopulate it
	// quickly enough on reloading of a save and saving to a file would
	// introduce quite a bit of complexity with keeping the pointers valid on
	// reload
	array<PopulationRequest@> popRequests;

	// colonise sources that have good labor income
	array<ColonizerMechanoidPlanet@> factories;
	double lastRefreshedFactories = -60;

	void create() {
		@colonization = cast<IColonization>(ai.colonization);
		@construction = cast<Construction>(ai.construction);
		@movement = cast<Movement>(ai.movement);
		@planets = cast<Planets>(ai.planets);
		@budget = cast<Budget>(ai.budget);

		@ai.defs.Shipyard = null;

		@crystals = getResource("FTL");
		@unobtanium = getResource("Unobtanium");
		unobtaniumAbl = getAbilityID("UnobtaniumMorph");

		/* @foodClass = getResourceClass("Food");
		@waterClass = getResourceClass("WaterType");
		@scalableClass = getResourceClass("Scalable"); */

		colonizeAbilityID = getAbilityID("MechanoidColonize");

		//colonization.PerformColonization = false;

		@buildPop = getConstructionType("MechanoidPopulation");

		// Register ourselves as overriding the colony management
		auto@ expansion = cast<ColonizationAbilityOwner>(ai.colonization);
		expansion.setColonyManagement(this);
	}

	void start() {
		/* //Oh yes please can we have some ftl crystals sir
		if(crystals !is null) {
			ResourceSpec spec;
			spec.type = RST_Specific;
			@spec.resource = crystals;
			spec.isLevelRequirement = false;
			spec.isForImport = false;

			colonization.queueColonizeLowPriority(spec);
		} */
	}

	/* bool canBuildPopulation(Planet& pl, double factor=1.0) {
		if(buildPop is null)
			return false;
		if(!buildPop.canBuild(pl, ignoreCost=true))
			return false;
		auto@ primFact = construction.primaryFactory;
		if(primFact !is null && pl is primFact.obj)
			return true;

		double laborCost = buildPop.getLaborCost(pl);
		double laborIncome = pl.laborIncome;
		return laborCost < laborIncome * MAX_POP_BUILDTIME * factor;
	} */

	void removeInvalidSources() {
		uint sourceCount = planetSources.length;
		for (uint i = 0; i < sourceCount; ++i) {
			if (!planetSources[i].valid(ai)) {
				planetSources.removeAt(i);
				--i; --sourceCount;
			}
		}
	}

	void checkForSources() {
		uint planetCount = planets.planets.length;
		uint sourceCount = planetSources.length;
		planetIndex = (planetIndex + 1) % planetCount;
		auto@ plAI = planets.planets[planetIndex];
		for (uint i = 0; i < sourceCount; ++i) {
			 auto@ source = cast<ColonizerMechanoidPlanet>(planetSources[i]);
			 if (source.planet is plAI.obj) {
				 // we have this one already
				 return;
			 }
		}
		planetSources.insertLast(ColonizerMechanoidPlanet(plAI.obj));
	}

	void checkSources() {
		uint sourceCount = planetSources.length;
		sourceIndex = (sourceIndex + 1) % sourceCount;
		auto@ source = cast<ColonizerMechanoidPlanet>(planetSources[sourceIndex]);

		// Make pop requests when we are not meeting our resource level
		double pop = source.planet.population;
		double needPop = getPlanetLevelRequiredPop(source.planet, source.planet.resourceLevel);
		if (pop < needPop) {
			for (uint i = 0, cnt = popRequests.length; i < cnt; ++i) {
				if (popRequests[i].source is source) {
					return;
				}
			}
			popRequests.insertLast(PopulationRequest(source, needPop - pop));
			return;
		} else {
			// try to build population to get to max pop
			if (pop < double(source.planet.maxPopulation)) {
				buildPopAtIdle(source);
			}
		}
	}

	void meetPopRequests(PopulationRequest@ request) {
		ColonizerMechanoidPlanet@ source;
		while (request.neededPopulation >= 1) {
			auto@ source = cast<ColonizerMechanoidPlanet>(getFastestSource(request.source.planet));
			if (source is null) {
				return;
			}
			bool success = source.transferPop(uint(min(source.sparePop(), request.neededPopulation)), request, ai);
			if (!success) {
				return; // probably out of FTL
			}
		}
	}

	void refreshFactories() {
		if ((lastRefreshedFactories + 60) > gameTime) {
			return;
		}
		factories.length = 0;
		uint sourceCount = planetSources.length;
		for (uint i = 0; i < sourceCount; ++i) {
			auto@ source = cast<ColonizerMechanoidPlanet>(planetSources[i]);
			if (source.isGoodForPopulationProduction(construction)) {
				factories.insertLast(source);
			}
		}
		lastRefreshedFactories = gameTime;
	}

	double desiredExcessPop() {
		double total = 5 + (0.5 * planets.planets.length);
		for (uint i = 0, cnt = popRequests.length; i < cnt; ++i) {
			total += popRequests[i].neededPopulation;
		}
		return total;
	}

	// Returns how much pop over their max our factories have in total
	// Note this may be negative if a lot of factories have gone under
	double factoriesExcessPop() {
		double excessPop = 0;
		uint factoryCount = factories.length;
		for (uint i = 0; i < factoryCount; ++i) {
			ColonizerMechanoidPlanet@ source = factories[i];
			excessPop += source.sparePop();
		}
		return excessPop;
	}

	void buildExcessPopAtFactories() {
		double desired = desiredExcessPop();
		double current = factoriesExcessPop();
		// FIXME: We should probably be counting pop being built here too
		if (current >= desired) {
			return;
		}

		uint factoryCount = factories.length;
		for (uint i = 0; i < factoryCount; ++i) {
			if (current >= desired) {
				return;
			}
			ColonizerMechanoidPlanet@ source = factories[i];
			if (buildPopAtIdle(source)) {
				current += 1;
			}
		}
	}

	bool buildPopAtIdle(ColonizerMechanoidPlanet@ source) {
		// see if we're not building anything (this is a convenient way)
		// to avoid building too many population as well
		Factory@ factory = construction.get(source.planet);
		if (factory is null || factory.active !is null) {
			// no factory or busy
			return false;
		}
		// FIXME: We should probably be checking how much income we have
		// and capping how many pops we are willing to build in one turn
		// while under debt
		if (buildPop is null) {
			return false;
		}
		auto@ build = construction.buildConstruction(buildPop);
		construction.buildNow(build, factory);
		if (log) {
			ai.print("Building population", factory.obj);
		}
		return true;
	}

	void focusTick(double time) override {
		removeInvalidSources();
		checkForSources();

		uint planetCount = planets.planets.length;
		uint checks = min(15, planetCount);
		for (uint i = 0; i < checks; ++i) {
			checkSources();
		}

		// try to meet requested population by moving pop around
		for (uint i = 0, cnt = popRequests.length; i < cnt; ++i) {
			if (!popRequests[i].valid(ai)) {
				popRequests.removeAt(i);
				--i; --cnt;
			} else {
				meetPopRequests(popRequests[i]);
			}
		}

		refreshFactories();
		buildExcessPopAtFactories();

		/* //Check existing lists
		for(uint i = 0, cnt = popFactories.length; i < cnt; ++i) {
			auto@ obj = popFactories[i];
			if(obj is null || !obj.valid || obj.owner !is ai.empire) {
				popFactories.removeAt(i);
				--i; --cnt;
				continue;
			}
			if(!canBuildPopulation(popFactories[i])) {
				popFactories.removeAt(i);
				--i; --cnt;
				continue;
			}
		}

		for(uint i = 0, cnt = popSources.length; i < cnt; ++i) {
			auto@ obj = popSources[i];
			if(obj is null || !obj.valid || obj.owner !is ai.empire) {
				popSources.removeAt(i);
				--i; --cnt;
				continue;
			}
			if(!canSendPopulation(popSources[i])) {
				popSources.removeAt(i);
				--i; --cnt;
				continue;
			}
		}

		for(uint i = 0, cnt = popRequests.length; i < cnt; ++i) {
			auto@ obj = popRequests[i];
			if(obj is null || !obj.valid || obj.owner !is ai.empire) {
				popRequests.removeAt(i);
				--i; --cnt;
				continue;
			}
			if(!requiresPopulation(popRequests[i])) {
				popRequests.removeAt(i);
				--i; --cnt;
				continue;
			}
		}

		uint plCnt = planets.planets.length;
		for(uint n = 0, cnt = min(15, plCnt); n < cnt; ++n) {
			chkInd = (chkInd+1) % plCnt;
			auto@ plAI = planets.planets[chkInd];

			//Find planets that can build population reliably
			if(canBuildPopulation(plAI.obj)) {
				if(popFactories.find(plAI.obj) == -1)
					popFactories.insertLast(plAI.obj);
			}

			//Find planets that need population
			if(requiresPopulation(plAI.obj)) {
				if(popRequests.find(plAI.obj) == -1)
					popRequests.insertLast(plAI.obj);
			}

			//Find planets that have extra population
			if(canSendPopulation(plAI.obj)) {
				if(popSources.find(plAI.obj) == -1)
					popSources.insertLast(plAI.obj);
			}

			if(plAI.resources !is null && plAI.resources.length != 0) {
				auto@ res = plAI.resources[0];

				//See if we have anything useful to morph our homeworld too
				if(checkMorph) {
					bool morph = false;
					if(res.resource is crystals)
						morph = true;
					else if(res.resource.level >= 2 && res.resource.tilePressure[TR_Labor] >= 5)
						morph = true;
					else if(res.resource.level >= 3 && res.resource.totalPressure > 10)
						morph = true;
					else if(res.resource.cls is scalableClass && gameTime > 30.0 * 60.0)
						morph = true;
					else if(res.resource.level >= 2 && res.resource.totalPressure >= 5 && gameTime > 60.0 * 60.0)
						morph = true;

					if(morph) {
						if(log)
							ai.print("Morph homeworld to "+res.resource.name+" from "+res.obj.name, hw);
						hw.activateAbilityTypeFor(ai.empire, unobtaniumAbl, plAI.obj);
					}
				}
			}
		}

		//See if we can find something to send population to
		availSources = popSources;

		for(uint i = 0, cnt = popRequests.length; i < cnt; ++i) {
			Planet@ dest = popRequests[i];
			if(canBuildPopulation(dest, factor=(availSources.length == 0 ? 2.5 : 1.5))) {
				Factory@ f = construction.get(dest);
				if(f !is null) {
					if(f.active is null) {
						auto@ build = construction.buildConstruction(buildPop);
						construction.buildNow(build, f);
						if(log)
							ai.print("Build population", f.obj);
						continue;
					}
					else {
						auto@ cons = cast<BuildConstruction>(f.active);
						if(cons !is null && cons.consType is buildPop) {
							if(double(dest.maxPopulation) <= dest.population + 0.0)
								continue;
						}
					}
				}
			}
			transferBest(dest, availSources);
		}

		if(availSources.length != 0) {
			//If we have any population left, do stuff from our colonization queue
			 // [[ MODIFY BASE GAME START ]]
			for(uint i = 0, cnt = colonization.AwaitingSource.length; i < cnt && availSources.length != 0; ++i) {
				Planet@ dest = colonization.AwaitingSource[i].target;
				Planet@ source = transferBest(dest, availSources);
				if(source !is null) {
					@colonization.AwaitingSource[i].colonizeFrom = source;
					colonization.AwaitingSource.removeAt(i);
					--i; --cnt;
				}
			}
			 // [[ MODIFY BASE END ]]
		}

		//Build population on idle planets
		if(budget.canSpend(BT_Development, 100)) {
			for(int i = popFactories.length-1; i >= 0; --i) {
				Planet@ dest = popFactories[i];
				Factory@ f = construction.get(dest);
				if(f is null || f.active !is null)
					continue;
				if(dest.population >= double(dest.maxPopulation) + 1.0)
					continue;

				auto@ build = construction.buildConstruction(buildPop);
				construction.buildNow(build, f);
				if(log)
					ai.print("Build population for idle", f.obj);
				break;
			}
		} */
	}
/*
	Planet@ transferBest(Planet& dest, array<Planet@>& availSources) {
		//Find closest source
		Planet@ bestSource;
		double bestDist = INFINITY;
		for(uint j = 0, jcnt = availSources.length; j < jcnt; ++j) {
			double d = movement.getPathDistance(availSources[j].position, dest.position);
			if(d < bestDist) {
				bestDist = d;
				@bestSource = availSources[j];
			}
		}

		if(bestSource !is null) {
			double cost = transferCost(bestDist);
			if(cost <= ai.empire.FTLStored) {
				if(log)
					ai.print("Transfering population to "+dest.name, bestSource);
				availSources.remove(bestSource);
				bestSource.activateAbilityTypeFor(ai.empire, colonizeAbl, dest);
				return bestSource;
			}
		}
		return null;
	} */

	void tick(double time) override {
	}

	array<ColonizationSource@> getSources() {
		return planetSources;
	}

	ColonizationSource@ getClosestSource(vec3d position) {
		ColonizerMechanoidPlanet@ closestSource;
		double shortestDistance = -1;
		for (uint i = 0, cnt = planetSources.length; i < cnt; ++i) {
			auto@ source = cast<ColonizerMechanoidPlanet>(planetSources[i]);
			if (!(source.sparePop() >= 1)) {
				continue;
			}
			double distance = source.planet.position.distanceTo(position);
			if (shortestDistance == -1 || distance < shortestDistance) {
				shortestDistance = distance;
				@closestSource = source;
			}
		}
		return closestSource;
	}

	// Finds the closest/therefore cheapest FTL wise source for the colony
	//
	// Note this may find a colonisation source that only has 1 spare pop,
	// even if the colony needs more, we'll just deal with such issues
	// on subsequent ticks
	ColonizationSource@ getFastestSource(Planet@ colony) {
		ColonizerMechanoidPlanet@ colonizeFrom;
		double colonizeFromWeight = 0;
		for (uint i = 0, cnt = planetSources.length; i < cnt; ++i) {
			auto@ source = cast<ColonizerMechanoidPlanet>(planetSources[i]);
			if (!(source.sparePop() >= 1)) {
				continue;
			}
			double ftlCost = transferCost(source.planet, ai.empire, colony);
			if (ftlCost > ai.empire.FTLStored) {
				continue;
			}
			double weight = source.weight(ai);
			// FTL cost is proportional to distance anyway, and we actually want
			// to minimise FTL costs instead of actual distance, so use it instead
			weight /= ftlCost;
			if (weight > colonizeFromWeight) {
				colonizeFromWeight = weight;
				@colonizeFrom = source;
			}
		}
		return colonizeFrom;
	}

	void colonizeTick() {
		// Don't need to do anything here
	}

	void orderColonization(ColonizeData@ data, ColonizationSource@ isource) {
		auto@ source = cast<ColonizerMechanoidPlanet>(isource);
		@data.colonizeFrom = source.planet;
		ColonizeData2@ _data = cast<ColonizeData2>(data);
		if (_data !is null) {
			@_data.colonizeUnit = source;
		}
		source.planet.activateAbilityTypeFor(ai.empire, colonizeAbilityID, data.target);
	}

	void saveSource(SaveFile& file, ColonizationSource@ source) {
		if (source !is null) {
			file.write1();
			auto@ source = cast<ColonizerMechanoidPlanet>(source);
			file << source.planet;
		} else {
			file.write0();
		}
	}

	ColonizationSource@ loadSource(SaveFile& file) {
		if (file.readBit()) {
			Planet@ planet;
			file >> planet;
			return ColonizerMechanoidPlanet(planet);
		}
		return null;
	}

	// We save our state in our save and load methods
	void saveManager(SaveFile& file) {}
	void loadManager(SaveFile& file) {}
};

AIComponent@ createMechanoid2() {
	return Mechanoid2();
}
