package com.hon.reader.hon.shosetsu

import java.io.IOException

class SourceHttpException(val status: Int, val retryAfterMillis: Long = 0) : IOException(
    when (status) {
        401, 403 -> "HTTP $status: open this source's website to sign in or complete its verification."
        404, 410 -> "HTTP $status: this page is no longer available."
        429 -> "HTTP 429: this source is limiting requests. Hon will wait before retrying."
        else -> "Source returned HTTP $status"
    }
) {
    val transient: Boolean get() = status == 408 || status == 429 || status in 500..599
}
