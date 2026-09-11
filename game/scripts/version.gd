class_name Version
## The game's version, one place. build_dist.py reads it for the export's
## product version, the zip's name and the GitHub release tag (v1.1.0);
## the updater compares it with the newest release on launch.

const VERSION := "1.1.0"


static func newer(a: String, b: String) -> bool:
	## a is a later version than b (1.2.0 > 1.1.9 > 1.1.0)
	var pa := a.strip_edges().trim_prefix("v").split(".")
	var pb := b.strip_edges().trim_prefix("v").split(".")
	for i in range(maxi(pa.size(), pb.size())):
		var x := int(pa[i]) if i < pa.size() else 0
		var y := int(pb[i]) if i < pb.size() else 0
		if x != y:
			return x > y
	return false
