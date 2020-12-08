import empire_ai.weasel.ImportData;
from resources import ResourceType;
from resources import Resource;
import statuses;

/* enum ResourceUsageType {
	// The resource is used for levelling up a planet
	// eg a Tier 1 resource
	RUT_Levelling,
	// The resource is used for providing labor to a planet,
	// not levelling it up, and hence could be redirected to
	// another labor sink.
	// eg Aluminium
	RUT_Labor,
	// The resource is used for providing pressure, not levelling
	// and hence could be redirected elsewhere if we go over pressure
	// capacity
	// eg Fulrate
	RUT_Pressure,
	// This resource isn't in use
	RUT_Unused,
}; */

// Don't think this is the right level of abstraction for colonising purposes
/**
 * A resource flow is a resource of some kind that can be exported somewhere
 * (to a sink) from a source. It contains additional bookkeeping to help the
 * AI remember what its exports are used for.
 */
/* class ResourceFlow {
	// The exportable resource
	const ResourceType@ resource;

	// The source of this exportable resource.
	Object@ source;
	// The object we are exporting this resource to, or null
	Object@ sink;

	// If last time we checked, this resource was exported somewhere.
	// For many reasons the export might be cancelled by the Resources
	// component, in which case we'll compare that to this flag and
	// reconsider where to use this.
	bool used;

	// The export data this resouce is in use for, or null
	ExportData@ use;

	// The way we are using this resource
	ResourceUsageType usageType;

	ResourceFlow(const ResourceType@ resource, Object@ source) {
		if (source is null) {
			// hopefully this never happens
			throw("Unable to create ResourceFlow from null source");
		}
		if (resource is null) {
			// hopefully this never happens
			throw("Unable to create ResourceFlow from null resource");
		}
		@this.source = source;
		@this.resource = resource;
		used = false;
		usageType = RUT_Unused;
	}

	// TODO
	void save(SaveFile& file) {}
	void load(SaveFile& file) {}
} */
