extends RefCounted
## A bounded frame-interval profiler. Never substitutes desktop/Xvfb results for Android data.
## Pure summaries make real engine data reproducible and reject malformed evidence.

static func summarize_frame_intervals(frame_ms: Array[float]) -> Dictionary:
	if frame_ms.is_empty() or frame_ms.size() > 10000:
		return {"valid": false, "reason": "INVALID_SAMPLE_COUNT"}
	var sorted: Array[float] = frame_ms.duplicate()
	var total := 0.0
	for value in sorted:
		if not is_finite(value) or value <= 0.0:
			return {"valid": false, "reason": "INVALID_SAMPLE"}
		total += value
	sorted.sort()
	var count := sorted.size()
	return {
		"valid": true,
		"samples": count,
		"average_ms": total / float(count),
		"min_ms": sorted[0],
		"max_ms": sorted[count - 1],
		"p50_ms": sorted[maxi(0, int(ceil(0.50 * count)) - 1)],
		"p95_ms": sorted[maxi(0, int(ceil(0.95 * count)) - 1)],
		"p99_ms": sorted[maxi(0, int(ceil(0.99 * count)) - 1)],
	}
