extends SceneTree

# Not a test. Reports what each decal actually does to each shape at the size
# the marker is really built at -- how much it removes, how many pieces it
# leaves, and how many INLAY pieces survive the seam inset.
#
# The inlay number is the one no other instrument reports: a piece too thin to
# survive INLAY_INSET is dropped silently, so a decal can cut a visible hole and
# still fill NOTHING.


const INLAY_INSET := 0.008


func _area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		a += p.x * q.y - q.x * p.y
	return absf(a) * 0.5


func _init() -> void:
	# The real build scale, so widths are in metres rather than outline units.
	var r: float = Tuning.MARKER_RADIUS * 0.46
	print("scale r=%.4f" % r)
	print("shape        decal        cut%   pieces  inlay  minfeat%")
	for shape in Tuning.MARKER_SHAPES:
		var flat := PackedVector2Array()
		for v in shape["outline"]:
			flat.append(Vector2(v.x * r, v.y * r))
		var full := _area(flat)
		for decal in Tuning.MARKER_DECALS:
			var id: String = decal["id"]
			if id == Tuning.MARKER_DECAL_DEFAULT:
				continue
			var outline: Array = []
			for v in flat:
				outline.append(v)
			var cuts: Array = Tuning.decal_polygons(id, outline)

			var result: Array = [flat]
			for cut in cuts:
				var next: Array = []
				for loop in result:
					for piece in Geometry2D.clip_polygons(loop,
							PackedVector2Array(cut)):
						if piece.size() < 3:
							continue
						if Geometry2D.is_polygon_clockwise(piece):
							continue
						next.append(piece)
				if next.is_empty():
					next = result
					break
				result = next

			var inlay := 0
			for cut in cuts:
				for piece in Geometry2D.intersect_polygons(
						PackedVector2Array(cut), flat):
					if piece.size() < 3:
						continue
					for inner in Geometry2D.offset_polygon(piece, -INLAY_INSET):
						if inner.size() >= 3:
							inlay += 1

			var remain := 0.0
			var smallest := INF
			for piece in result:
				remain += _area(piece)
				smallest = minf(smallest, _area(piece))
			print("%-12s %-12s %5.1f  %6d  %5d  %7.1f" % [
				shape["id"], id, (1.0 - remain / full) * 100.0,
				result.size(), inlay, (smallest / full) * 100.0])
	quit(0)
