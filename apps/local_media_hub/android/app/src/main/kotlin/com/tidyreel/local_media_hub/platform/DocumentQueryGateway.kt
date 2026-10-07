package com.tidyreel.local_media_hub.platform

interface DocumentQueryGateway {
    val authority: String

    fun children(parentDocumentId: String): List<DocumentNode>
}
