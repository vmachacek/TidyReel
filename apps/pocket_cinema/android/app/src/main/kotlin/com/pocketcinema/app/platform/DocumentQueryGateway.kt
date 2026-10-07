package com.pocketcinema.app.platform

interface DocumentQueryGateway {
    val authority: String

    fun children(parentDocumentId: String): List<DocumentNode>
}
