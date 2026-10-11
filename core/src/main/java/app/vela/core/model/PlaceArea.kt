package app.vela.core.model

/**
 * The zoom an area result is framed at, or null for a place. Google's keyless search answers a
 * country, a state, a county, a city or a postal code with no bounds (checked 2026-10-11, issue
 * #752), so the kind is read off what the entry carries: an area has no category and no rating,
 * a country or a state no address at all, a city or a county only its region as the address, and
 * a postal code the category "Postal code". The map used to fly to street level in the middle of
 * a country.
 */
fun Place.areaZoom(): Double? {
    if (rating != null || reviewCount != null) return null
    if (category.equals("Postal code", ignoreCase = true)) return POSTAL_ZOOM
    if (!category.isNullOrBlank()) return null
    val a = address?.trim().orEmpty()
    return when {
        a.isEmpty() -> COUNTRY_ZOOM
        a.none { it.isDigit() } && ',' !in a -> CITY_ZOOM
        else -> null
    }
}

const val COUNTRY_ZOOM = 6.5
const val CITY_ZOOM = 11.5
const val POSTAL_ZOOM = 13.0
