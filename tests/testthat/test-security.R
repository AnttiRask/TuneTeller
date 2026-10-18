source(test_path("../../app/www/security.R"))

test_that("the header set covers framing, referrers, permissions, transport and CSP", {
  h <- security_headers()
  expect_equal(h[["X-Frame-Options"]], "DENY")
  expect_equal(h[["X-Content-Type-Options"]], "nosniff")
  expect_equal(h[["Referrer-Policy"]], "strict-origin-when-cross-origin")
  expect_match(h[["Strict-Transport-Security"]], "^max-age=[0-9]+$")
  expect_false(grepl("includeSubDomains|preload", h[["Strict-Transport-Security"]]))
  expect_match(h[["Permissions-Policy"]], "geolocation=()", fixed = TRUE)
  expect_match(h[["Permissions-Policy"]], "camera=()", fixed = TRUE)
})

test_that("the enforced CSP only contains directives that can't break the app", {
  csp <- security_headers()[["Content-Security-Policy"]]
  expect_match(csp, "frame-ancestors 'none'", fixed = TRUE)
  expect_match(csp, "object-src 'none'", fixed = TRUE)
  # no resource-loading directives in the enforced policy
  expect_false(grepl("script-src|style-src|img-src|connect-src|default-src", csp))
})

test_that("the report-only CSP allows exactly the hosts the app uses", {
  csp <- security_headers()[["Content-Security-Policy-Report-Only"]]
  expect_match(csp, "img-src [^;]*https://i\\.scdn\\.co")
  expect_match(csp, "img-src [^;]*https://\\*\\.spotifycdn\\.com")
  expect_match(csp, "font-src [^;]*https://fonts\\.cdnfonts\\.com")
  expect_match(csp, "style-src [^;]*https://fonts\\.cdnfonts\\.com")
  expect_match(csp, "connect-src 'self' wss:", fixed = TRUE)
  # nothing is allowed from arbitrary hosts
  expect_false(grepl("\\*(;| |$)|https:(;| |$)", csp))
})

fake_app <- function(handler) structure(list(httpHandler = handler), class = "shiny.appobj")

test_that("with_security_headers adds headers to page responses", {
  app <- with_security_headers(fake_app(function(req) {
    shiny::httpResponse(200, "text/html", "<p>hi</p>", headers = list("X-Existing" = "kept"))
  }))
  res <- app$httpHandler(list(PATH_INFO = "/"))
  expect_s3_class(res, "httpResponse")
  expect_equal(res$headers[["X-Frame-Options"]], "DENY")
  expect_equal(res$headers[["X-Existing"]], "kept")
  expect_equal(res$content, "<p>hi</p>")
})

test_that("with_security_headers leaves NULL and non-response values alone", {
  expect_null(with_security_headers(fake_app(function(req) NULL))$httpHandler(list()))
  expect_equal(with_security_headers(fake_app(function(req) "x"))$httpHandler(list()), "x")
})

test_that("with_security_headers works on promised responses", {
  app <- with_security_headers(fake_app(function(req) {
    promises::promise_resolve(shiny::httpResponse(200, "text/html", "ok"))
  }))
  out <- NULL
  promises::then(app$httpHandler(list()), function(v) out <<- v)
  for (i in 1:50) {
    later::run_now()
    if (!is.null(out)) break
  }
  expect_s3_class(out, "httpResponse")
  expect_equal(out$headers[["X-Frame-Options"]], "DENY")
})
