package app.vela.core.nav

import app.vela.core.model.LatLng
import app.vela.core.model.ManeuverType
import app.vela.core.model.Route

/**
 * The arrows drawn on the route at its turns while navigating (issue #804): a short stretch of the
 * route through each maneuver, [BEFORE_M] before the corner to [AFTER_M] past it, with the bearing
 * the stretch ends on for the arrowhead. One arrow per maneuver that bends the course, from the
 * step in hand onward; a continue, a merge or a roundabout's entry gets none.
 */
object TurnArrowGeometry {
    data class Arrow(val points: List<LatLng>, val endBearingDeg: Double)

    const val BEFORE_M = 30.0
    const val AFTER_M = 30.0

    /** How far a maneuver point may sit off the line and still be placed along it. */
    const val MATCH_M = 40.0

    /** An arrow shorter than this (two maneuvers on top of each other at the route's ends) is skipped. */
    const val MIN_LENGTH_M = 15.0

    val TYPES: Set<ManeuverType> = setOf(
        ManeuverType.TURN_LEFT, ManeuverType.TURN_RIGHT, ManeuverType.SLIGHT_LEFT, ManeuverType.SLIGHT_RIGHT,
        ManeuverType.SHARP_LEFT, ManeuverType.SHARP_RIGHT, ManeuverType.UTURN, ManeuverType.FORK_LEFT,
        ManeuverType.FORK_RIGHT, ManeuverType.RAMP_LEFT, ManeuverType.RAMP_RIGHT, ManeuverType.EXIT_ROUNDABOUT,
        ManeuverType.KEEP_LEFT, ManeuverType.KEEP_RIGHT,
    )

    fun arrows(route: Route, fromStep: Int): List<Arrow> {
        val poly = route.polyline
        if (poly.size < 2) return emptyList()
        val cum = RouteProjection.cumulative(poly)
        val total = cum.last()
        val out = ArrayList<Arrow>()
        val maneuvers = route.maneuvers
        for (i in maxOf(fromStep, 0) until maneuvers.size) {
            val m = maneuvers[i]
            if (m.type !in TYPES) continue
            val at = RouteProjection.alongMeters(poly, cum, m.location, MATCH_M) ?: continue
            val s0 = maxOf(0.0, at - BEFORE_M)
            val s1 = minOf(total, at + AFTER_M)
            if (s1 - s0 < MIN_LENGTH_M) continue
            val pts = ArrayList<LatLng>()
            pts += RouteProjection.pointAt(poly, cum, s0)
            var k = RouteProjection.segmentEnd(cum, s0)
            while (k < cum.size && cum[k] < s1) { pts += poly[k]; k++ }
            pts += RouteProjection.pointAt(poly, cum, s1)
            out += Arrow(pts, RouteProjection.bearingAt(poly, cum, maxOf(s0, s1 - 2.0)))
        }
        return out
    }
}
