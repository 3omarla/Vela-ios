package app.vela.core.nav

import app.vela.core.model.LatLng
import app.vela.core.model.Maneuver
import app.vela.core.model.ManeuverType
import app.vela.core.model.Route
import app.vela.core.model.RouteLeg
import app.vela.core.model.distanceTo
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Turn arrows on an L-shaped route: north 200 m, then east 200 m (issue #804). */
class TurnArrowGeometryTest {
    private val a = LatLng(38.5400, -121.7400)
    private val corner = LatLng(38.5418, -121.7400)   // about 200 m north
    private val b = LatLng(38.5418, -121.7377)        // about 200 m east
    private fun m(type: ManeuverType, at: LatLng) = Maneuver(type, "", at, 0.0, 0.0)
    private val route = Route(
        polyline = listOf(a, corner, b),
        legs = listOf(RouteLeg(400.0, 60.0, null, listOf(m(ManeuverType.DEPART, a), m(ManeuverType.TURN_RIGHT, corner), m(ManeuverType.ARRIVE, b)))),
        distanceMeters = 400.0, durationSeconds = 60.0, durationInTrafficSeconds = null,
    )

    @Test fun oneArrowThroughTheCorner() {
        val arrows = TurnArrowGeometry.arrows(route, 0)
        assertEquals(1, arrows.size)
        val arrow = arrows[0]
        assertTrue(arrow.points.size >= 3)
        assertEquals(TurnArrowGeometry.BEFORE_M, arrow.points.first().distanceTo(corner), 2.0)
        assertEquals(TurnArrowGeometry.AFTER_M, arrow.points.last().distanceTo(corner), 2.0)
        assertTrue("corner is a vertex", arrow.points.any { it.distanceTo(corner) < 0.5 })
        assertEquals(90.0, arrow.endBearingDeg, 3.0)
    }

    @Test fun arrowsStartAtTheStepInHand() {
        assertEquals(0, TurnArrowGeometry.arrows(route, 2).size)
        assertEquals(1, TurnArrowGeometry.arrows(route, 1).size)
    }

    @Test fun aStraightStepGetsNone() {
        val straight = route.copy(legs = listOf(RouteLeg(400.0, 60.0, null, listOf(m(ManeuverType.DEPART, a), m(ManeuverType.STRAIGHT, corner), m(ManeuverType.ARRIVE, b)))))
        assertEquals(0, TurnArrowGeometry.arrows(straight, 0).size)
    }
}
