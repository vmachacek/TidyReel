package com.pocketcinema.app.platform

enum class RootAccessState(val wireValue: String) {
    AVAILABLE("available"),
    PERMISSION_REVOKED("permissionRevoked"),
    UNAVAILABLE("unavailable"),
}
object RootAccessEvaluator {
    fun evaluate(
        hasPersistedRead: Boolean,
        rootQueryable: Boolean,
    ): RootAccessState = when {
        !hasPersistedRead -> RootAccessState.PERMISSION_REVOKED
        !rootQueryable -> RootAccessState.UNAVAILABLE
        else -> RootAccessState.AVAILABLE
    }
}
