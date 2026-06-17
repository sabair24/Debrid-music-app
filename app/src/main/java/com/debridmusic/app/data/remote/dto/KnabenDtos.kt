package com.debridmusic.app.data.remote.dto

data class KnabenRequest(
    val query: String,
    val search_type: String = "100%",
    val search_field: String = "title",
    val order_by: String = "seeders",
    val order_direction: String = "desc",
    val size: Int = 50,
    val hide_unsafe: Boolean = true,
    val hide_xxx: Boolean = true,
)

data class KnabenResponse(
    val hits: List<KnabenHit>? = null,
)

data class KnabenHit(
    val hash: String? = null,
    val title: String? = null,
    val bytes: Long? = null,
    val seeders: Int? = null,
    val peers: Int? = null,
    val magnetUrl: String? = null,
    val category: String? = null,
)
