# HemisphereMeshBuilder
#
# Generates an inverted hemisphere ArrayMesh for displaying 180° equirectangular
# video on the inside surface. The camera sits at the world origin (0, 0, 0)
# looking in the -Z direction (Godot default).
#
# Coordinate conventions:
#   Forward: -Z  |  Up: +Y  |  Right: +X
#
# UV mapping (matches equirectangular 180° projection):
#   U: 0 → left edge  (azimuth = -90°)  to  1 → right edge (azimuth = +90°)
#   V: 0 → top edge   (elevation = +90°) to  1 → bottom edge (elevation = -90°)
#
# Normals point INWARD (toward the origin) so the surface is lit/visible
# from inside with an unshaded material.

class_name HemisphereMeshBuilder


# Build an inverted hemisphere ArrayMesh.
#
# radius:      Distance from origin to surface in world units (default 50)
# h_segments:  Horizontal subdivisions — higher = smoother edges (default 64)
# v_segments:  Vertical subdivisions — higher = smoother top/bottom (default 32)
static func build(
	radius: float = 50.0,
	h_segments: int = 64,
	v_segments: int = 32
) -> ArrayMesh:
	var verts  := PackedVector3Array()
	var norms  := PackedVector3Array()
	var uvs    := PackedVector2Array()
	var idx    := PackedInt32Array()

	# ── Vertex grid ────────────────────────────────────────────────────────────
	for vi in range(v_segments + 1):
		# phi: elevation angle from +PI/2 (top) down to -PI/2 (bottom)
		var phi: float = PI * 0.5 - PI * float(vi) / float(v_segments)

		for ui in range(h_segments + 1):
			# theta: azimuth angle from -PI/2 (left) across to +PI/2 (right)
			var theta: float = -PI * 0.5 + PI * float(ui) / float(h_segments)

			# Cartesian position on the unit sphere.
			# Forward = -Z, so the centre of the video maps to (0, 0, -radius).
			var x := cos(phi) * sin(theta)
			var y := sin(phi)
			var z := -cos(phi) * cos(theta)

			verts.append(Vector3(x, y, z) * radius)
			norms.append(Vector3(-x, -y, -z))  # Inward normals

			uvs.append(Vector2(
				float(ui) / float(h_segments),  # U: left → right
				float(vi) / float(v_segments)   # V: top  → bottom
			))

	# ── Index triangles ────────────────────────────────────────────────────────
	# Winding order is reversed relative to an outward-facing sphere so that
	# the front face is visible from inside (inward normals).
	var row := h_segments + 1
	for vi in range(v_segments):
		for ui in range(h_segments):
			var i0 := vi * row + ui
			var i1 := i0 + 1
			var i2 := i0 + row
			var i3 := i2 + 1

			idx.append(i0); idx.append(i2); idx.append(i1)
			idx.append(i1); idx.append(i2); idx.append(i3)

	# ── Assemble ArrayMesh ─────────────────────────────────────────────────────
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX]  = idx

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
