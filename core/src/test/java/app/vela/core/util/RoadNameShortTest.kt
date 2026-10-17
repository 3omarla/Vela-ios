package app.vela.core.util

import org.junit.Assert.assertEquals
import org.junit.Test

class RoadNameShortTest {
    @Test fun typesAndTrailingDirections() {
        assertEquals("Covell Blvd", RoadNameShort.shorten("Covell Boulevard"))
        assertEquals("W Covell Blvd", RoadNameShort.shorten("West Covell Boulevard"))
        assertEquals("Russell Rd NE", RoadNameShort.shorten("Russell Road Northeast"))
        assertEquals("NE 8th St", RoadNameShort.shorten("Northeast 8th Street"))
    }

    @Test fun theNameItselfIsKept() {
        assertEquals("North Ave", RoadNameShort.shorten("North Avenue"))
        assertEquals("Court St", RoadNameShort.shorten("Court Street"))
        assertEquals("Broadway", RoadNameShort.shorten("Broadway"))
        assertEquals("I 80", RoadNameShort.shorten("I 80"))
    }

    @Test fun theRoadInsideAnInstruction() {
        assertEquals("Turn right onto Court St", RoadNameShort.inText("Turn right onto Court Street", "Court Street"))
        assertEquals("Continue onto Russell Rd NE", RoadNameShort.inText("Continue onto Russell Road Northeast", "Russell Road Northeast"))
        assertEquals("Turn left", RoadNameShort.inText("Turn left", null))
        assertEquals("Turn left onto Broadway", RoadNameShort.inText("Turn left onto Broadway", "Broadway"))
        // The text names the road another way: untouched.
        assertEquals("Continue onto CA 113", RoadNameShort.inText("Continue onto CA 113", "Richards Boulevard"))
        assertEquals("Elm Jct", RoadNameShort.shorten("Elm Junction"))
    }

    @Test fun otherLanguagesPassThrough() {
        assertEquals("Rue de la Paix", RoadNameShort.shorten("Rue de la Paix"))
        assertEquals("Hauptstraße", RoadNameShort.shorten("Hauptstraße"))
    }
}
