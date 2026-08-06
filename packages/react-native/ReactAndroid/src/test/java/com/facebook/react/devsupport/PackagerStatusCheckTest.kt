/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@file:Suppress("DEPRECATION_ERROR") // Conflicting okhttp versions

package com.facebook.react.devsupport

import java.io.IOException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import okhttp3.Interceptor
import okhttp3.MediaType
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Response
import okhttp3.ResponseBody
import org.assertj.core.api.Assertions.assertThat
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

// Robolectric provides a real android.util.Log; without it FLog throws "Stub!" on the OkHttp
// dispatcher thread and the status callback never runs.
@RunWith(RobolectricTestRunner::class)
class PackagerStatusCheckTest {

  /** One scripted answer to a single probe attempt. */
  private sealed interface Step {
    /** Fail at the transport layer, as a down tunnel or refused connection would. */
    object TransportFailure : Step

    /** Answer with the given HTTP status code and (optional) body. */
    data class HttpResponse(val code: Int, val body: String = "") : Step
  }

  /**
   * Answers every call from [steps] in order, entirely in-process. CI runs these tests in a
   * network-restricted sandbox where a real loopback server (MockWebServer) is unreachable, so
   * responses are synthesized by an OkHttp application interceptor that never touches a socket.
   * [requestCount] records how many probe attempts PackagerStatusCheck issued.
   */
  private class ScriptedPackager(private val steps: List<Step>) : Interceptor {
    val requestCount = AtomicInteger(0)

    override fun intercept(chain: Interceptor.Chain): Response {
      val step = steps[requestCount.getAndIncrement()]
      return when (step) {
        is Step.TransportFailure -> throw IOException("simulated connection failure")
        is Step.HttpResponse ->
            Response.Builder()
                .request(chain.request())
                .protocol(Protocol.HTTP_1_1)
                .code(step.code)
                .message(if (step.code in 200..299) "OK" else "Error")
                .body(ResponseBody.create(TEXT_PLAIN, step.body))
                .build()
      }
    }
  }

  /** Drives the check against [steps] and returns the reported status plus the attempt count. */
  private fun check(vararg steps: Step): Pair<Boolean, Int> {
    val packager = ScriptedPackager(steps.toList())
    // Disable OkHttp's own connection-failure retries so the count reflects only what
    // PackagerStatusCheck itself re-enqueued.
    val client =
        OkHttpClient.Builder().retryOnConnectionFailure(false).addInterceptor(packager).build()
    val status = AtomicBoolean(false)
    val done = CountDownLatch(1)

    PackagerStatusCheck(client).run(PACKAGER_HOST) { packagerIsRunning ->
      status.set(packagerIsRunning)
      done.countDown()
    }

    assertThat(done.await(30, TimeUnit.SECONDS))
        .describedAs("PackagerStatusCheck never invoked its callback")
        .isTrue()
    return status.get() to packager.requestCount.get()
  }

  private fun runningResponse(): Step = Step.HttpResponse(200, PACKAGER_RUNNING_BODY)

  @Test
  fun reportsRunningOnFirstSuccessfulResponse() {
    val (isRunning, requestCount) = check(runningResponse())

    assertThat(isRunning).isTrue()
    assertThat(requestCount).isEqualTo(1)
  }

  @Test
  fun retriesTransportFailuresBeforeGivingUp() {
    // Every attempt fails to connect - the transport-level failure a dev server behind a down
    // tunnel produces. The callback must still be invoked exactly once, reporting "not running".
    val packager =
        ScriptedPackager(
            listOf(Step.TransportFailure, Step.TransportFailure, Step.TransportFailure)
        )
    val client =
        OkHttpClient.Builder().retryOnConnectionFailure(false).addInterceptor(packager).build()
    val callbackCount = AtomicInteger(0)
    val status = AtomicBoolean(true)
    val done = CountDownLatch(1)

    PackagerStatusCheck(client).run(PACKAGER_HOST) { packagerIsRunning ->
      callbackCount.incrementAndGet()
      status.set(packagerIsRunning)
      done.countDown()
    }

    assertThat(done.await(30, TimeUnit.SECONDS))
        .describedAs("PackagerStatusCheck never invoked its callback")
        .isTrue()
    assertThat(status.get()).isFalse()
    assertThat(callbackCount.get()).isEqualTo(1)
    assertThat(packager.requestCount.get()).isEqualTo(3)
  }

  @Test
  fun retriesAfterServerErrorAndSucceeds() {
    val (isRunning, requestCount) = check(Step.HttpResponse(503), runningResponse())

    assertThat(isRunning).isTrue()
    assertThat(requestCount).isEqualTo(2)
  }

  @Test
  fun givesUpAfterBoundedNumberOfAttempts() {
    val (isRunning, requestCount) =
        check(
            Step.HttpResponse(503),
            Step.HttpResponse(503),
            Step.HttpResponse(503),
        )

    assertThat(isRunning).isFalse()
    assertThat(requestCount).isEqualTo(3)
  }

  @Test
  fun doesNotRetryClientError() {
    val (isRunning, requestCount) = check(Step.HttpResponse(404))

    assertThat(isRunning).isFalse()
    assertThat(requestCount).isEqualTo(1)
  }

  @Test
  fun doesNotRetryWhenSomethingOtherThanMetroResponds() {
    val (isRunning, requestCount) = check(Step.HttpResponse(200, "not metro"))

    assertThat(isRunning).isFalse()
    assertThat(requestCount).isEqualTo(1)
  }

  private companion object {
    private const val PACKAGER_RUNNING_BODY = "packager-status:running"
    // Never contacted: the interceptor short-circuits every call before any socket work.
    private const val PACKAGER_HOST = "localhost:8081"
    private val TEXT_PLAIN: MediaType? = MediaType.parse("text/plain; charset=utf-8")
  }
}
