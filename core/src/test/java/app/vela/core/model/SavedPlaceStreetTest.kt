package app.vela.core.model

import org.junit.Assert.assertEquals
import org.junit.Test

class SavedPlaceStreetTest {
    private fun sp(name: String, address: String?, bare: Boolean = false, id: String = "x") =
        SavedPlace(id = id, name = name, lat = 0.0, lng = 0.0, address = address, bare = bare)

    @Test fun `a point's street moves into a locality-only address`() {
        assertEquals("Elm Street 5, 95616 Davis", sp("Elm Street 5", "95616 Davis", bare = true).addressKeepingStreet())
        assertEquals("Elm Street 5, 95616 Davis", sp("Elm Street 5", "95616 Davis", id = "pin:1").addressKeepingStreet())
    }

    @Test fun `an address that already starts with the street, a listing and a blank are left alone`() {
        assertEquals("Elm Street 5, 95616 Davis", sp("Elm Street 5", "Elm Street 5, 95616 Davis").addressKeepingStreet())
        assertEquals("95616 Davis", sp("Davis Food Co-op", "95616 Davis").addressKeepingStreet())
        assertEquals(null, sp("Elm Street 5", null, bare = true).addressKeepingStreet())
        assertEquals(" ", sp("Elm Street 5", " ", bare = true).addressKeepingStreet())
    }

    @Test fun `a rename moves the street once and a second rename leaves the address alone`() {
        val once = sp("Elm Street 5", "95616 Davis", bare = true).renamed("Peter")
        assertEquals("Peter", once.name)
        assertEquals("Elm Street 5, 95616 Davis", once.address)
        assertEquals(true, once.streetKept)
        val twice = once.renamed("Groceries")
        assertEquals("Elm Street 5, 95616 Davis", twice.address)
    }
}
