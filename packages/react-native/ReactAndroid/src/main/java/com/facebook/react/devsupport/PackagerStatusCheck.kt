/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@file:Suppress("DEPRECATION_ERROR") // Conflicting okhttp versions

package com.facebook.react.devsupport

import com.facebook.common.logging.FLog
import com.facebook.react.common.ReactConstants
import com.facebook.react.devsupport.inspector.DevSupportHttpClient
import com.facebook.react.devsupport.interfaces.PackagerStatusCallback
import java.io.IOException
import java.util.Locale
import okhttp3.Call
import okhttp3.Callback
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response

/** Use this class to check if the JavaScript packager is running on the provided host. */
internal class PackagerStatusCheck(private val client: OkHttpClient) {

  constructor() : this(DevSupportHttpClient.httpClient)

  fun run(host: String, callback: PackagerStatusCallback) {
    val statusURL = createPackagerStatusURL(host)
    val request = Request.Builder().url(statusURL).build()

    // A metro server reached over a slow link can exceed the client's connect timeout, or answer
    // 5xx while it is still starting up. A single-shot probe reports those as "no dev server",
    // which silently boots the bundle packaged in the app instead. Retry transport-level failures a
    // bounded number of times before giving up. Retries are re-enqueued rather than delayed,
    // because this client's dispatcher is shared with the bundle download and the packager
    // websockets and must not be blocked.
    fun attempt(attemptsLeft: Int) {
      // Only for failures that a later attempt could plausibly resolve.
      fun retryOrFail() {
        if (attemptsLeft > 1) {
          attempt(attemptsLeft - 1)
        } else {
          callback.onPackagerStatusFetched(false)
        }
      }

      client
          .newCall(request)
          .enqueue(
              object : Callback {
                override fun onFailure(call: Call, e: IOException) {
                  FLog.w(
                      ReactConstants.TAG,
                      "The packager does not seem to be running as we got an IOException requesting its status from $statusURL: ${e.message}",
                  )
                  retryOrFail()
                }

                override fun onResponse(call: Call, response: Response) {
                  if (!response.isSuccessful) {
                    FLog.e(
                        ReactConstants.TAG,
                        "Got non-success http code from packager at $statusURL when requesting status: ${response.code()}",
                    )
                    // 5xx can mean the dev server is still coming up; a 4xx will not change.
                    if (response.code() >= 500) {
                      retryOrFail()
                    } else {
                      callback.onPackagerStatusFetched(false)
                    }
                    return
                  }
                  val body = response.body()
                  if (body == null) {
                    FLog.e(
                        ReactConstants.TAG,
                        "Got null body response from packager at $statusURL when requesting status",
                    )
                    callback.onPackagerStatusFetched(false)
                    return
                  }
                  // Reading the body can still fail mid-stream (e.g. the connection drops after
                  // the headers). OkHttp only logs a throw from onResponse, so without catching it
                  // here the callback would never fire and bundle loading would wait forever.
                  val bodyString =
                      try {
                        body.string() // cannot call body.string() twice, stored it into variable.
                        // https://github.com/square/okhttp/issues/1240#issuecomment-68142603
                      } catch (e: IOException) {
                        FLog.w(
                            ReactConstants.TAG,
                            "Failed to read the packager status response from $statusURL: ${e.message}",
                        )
                        retryOrFail()
                        return
                      }
                  if (PACKAGER_OK_STATUS != bodyString) {
                    // Something other than Metro answered; retrying will not change the answer.
                    FLog.e(
                        ReactConstants.TAG,
                        "Got unexpected response from packager at $statusURL when requesting status: $bodyString",
                    )
                    callback.onPackagerStatusFetched(false)
                    return
                  }
                  callback.onPackagerStatusFetched(true)
                }
              },
          )
    }

    attempt(MAX_STATUS_ATTEMPTS)
  }

  private companion object {
    private const val PACKAGER_OK_STATUS = "packager-status:running"
    private const val PACKAGER_STATUS_URL_TEMPLATE = "%s://%s/status"
    private const val MAX_STATUS_ATTEMPTS = 3

    private fun createPackagerStatusURL(host: String): String =
        String.format(
            Locale.US,
            PACKAGER_STATUS_URL_TEMPLATE,
            DevSupportHttpClient.httpScheme(host),
            host,
        )
  }
}
