import resources;
import empire_ai.weasel.ImportData;
from resources import ResourceType;
from resources import Resource;
import statuses;

interface RaceResourceValuation {
	/**
	 * Updates a resource valuation to accomodate race specific factors.
	 */
	double modifyValue(const ResourceType@ resource, double currentValue);
}

/**
 * A valuator of a resource.
 */
class ResourceValuator {
	RaceResourceValuation@ race;
	const ResourceClass@ scalableClass;
	const ResourceType@ ftlCrystals;
	const ResourceType@ altar;
	const ResourceType@ razed;

	ResourceValuator() {
		// TODO: Race specific valuations
		@scalableClass = getResourceClass("Scalable");
		@ftlCrystals = getResource("FTL");
		@altar = getResource("Altar");
		@razed = getResource("Razed");
	}

	/**
	 * Gets the value of a resouce to the AI in terms of a
	 * resource to build up via levelling.
	 */
	double getValue(const ResourceType@ resource) {
		double value = 0.0;
		// scalabe resources are generally the best for levelling
		if (resource.cls is scalableClass) {
			value += 10;
		}
		// tier 3 resources are generally pretty good too
		if (resource.level == 3) {
			value += 7;
		}
		// tier 2 resources will do if we have nothing better
		if (resource.level == 2) {
			value += 3;
		}
		// tier 1 resources will do if we are completely out of options
		if (resource.level == 1) {
			value += 1;
		}
		// Resources with pressure are generally more helpful than ones
		// without, if nothing else is a major difference
		value += double(resource.totalPressure) * 0.1;
		// FTL crystals is extremely useful for levelling
		if (ftlCrystals !is null && resource.id == ftlCrystals.id) {
			value += 20;
		}
		value = devalueUselessResources(resource, value);
		if (race !is null) {
			value = race.modifyValue(resource, value);
		}
		return value;
	}

	double devalueUselessResources(const ResourceType@ resource, double currentValue) {
		if (altar !is null && resource.id == altar.id)
			return -1;
		if (razed !is null && resource.id == razed.id)
			return -5;
		return currentValue;
	}
}

/**
 * All the desirable or not so desirable things on a planet to
 * consider for colonisation, development and levelling.
 */
class PlanetValuables {
	Planet@ planet;
	array<const ResourceType@> exportable;
	array<const ResourceType@> unexportable;
	//array<?> dummy;
	array<const StatusType@> conditions;

	PlanetValuables(Planet@ planet) {
		@this.planet = planet;
		array<Status> planetStatuses;
		planetStatuses.syncFrom(planet.getStatusEffects());
		for (uint i = 0, cnt = planetStatuses.length; i < cnt; ++i) {
			if (planetStatuses[i].type.conditionFrequency > 0) {
				conditions.insertLast(planetStatuses[i].type);
			}
		}
		array<Resource> planetResources;
		planetResources.syncFrom(planet.getNativeResources());
		for (uint i = 0; i < planetResources.length; ++i) {
			auto planetResourceType = planetResources[i].type;
			if (planetResourceType.exportable) {
				exportable.insertLast(planetResourceType);
			} else {
				unexportable.insertLast(planetResourceType);
			}
		}
	}

	/**
	 * Gets the value of a planet based on its conditions and other non
	 * resource factors.
	 *
	 * ie, if we're looking for a particular resource to meet a resource
	 * spec, we want to colonise the planet with exotic atmosphere instead
	 * of the planet with a noxious atmosphere
	 */
	double getGenericValue(ResourceValuator& valuation) {
		return 1; // NYI
	}

	/**
	 * Gets the value of a planet based on its resources and other
	 * non resource factors like conditions.
	 *
	 * ie, how much we want this planet for levelling and income
	 * purposes
	 */
	double getResourceValue(ResourceValuator& valuation) {
		double weight = 0;
		for (uint i = 0, cnt = unexportable.length; i < cnt; ++i) {
			const ResourceType@ resource = unexportable[i];
			weight += 0.8 * valuation.getValue(resource);
		}
		for (uint i = 0, cnt = exportable.length; i < cnt; ++i) {
			const ResourceType@ resource = exportable[i];
			weight += valuation.getValue(resource);
		}
		return weight + getGenericValue(valuation);
	}

	bool canExportToMeet(ResourceSpec@ spec) {
		for (uint i = 0, cnt = exportable.length; i < cnt; ++i) {
			const ResourceType@ resource = exportable[i];
			if (spec.meets(resource)) {
				return true;
			}
		}
		return false;
	}

	/**
	 * Checks if any resources have any generic value, such as pressure of any
	 * kind or a level/scalable resource. This notably excludes resources
	 * we only colonise for levelling purposes, such as most food and water.
	 *
	 * Scalable resources are assumed to always have hooks or other reasons
	 * we want them.
	 */
	bool hasGenericUsefulnessOutsideLevelChains() {
		const ResourceClass@ scalableClass = getResourceClass("Scalable");
		for (uint i = 0, cnt = exportable.length; i < cnt; ++i) {
			const ResourceType@ resource = exportable[i];
			if (resource.level >= 1) {
				return true;
			}
			if (resource.totalPressure > 0) {
				return true;
			}
			if (resource.cls is scalableClass) {
				return true;
			}
		}
		for (uint i = 0, cnt = unexportable.length; i < cnt; ++i) {
			const ResourceType@ resource = unexportable[i];
			if (resource.level >= 1) {
				return true;
			}
			if (resource.totalPressure > 0) {
				return true;
			}
			if (resource.cls is scalableClass) {
				return true;
			}
		}
		return false;
	}
}
