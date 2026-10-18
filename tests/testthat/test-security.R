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

test_that("the CSP is enforced, not report-only", {
  h <- security_headers()
  expect_true("Content-Security-Policy" %in% names(h))
  expect_false("Content-Security-Policy-Report-Only" %in% names(h))
})

test_that("the CSP blocks everything by default and keeps the anti-framing directives", {
  csp <- security_headers()[["Content-Security-Policy"]]
  expect_match(csp, "default-src 'self'", fixed = TRUE)
  expect_match(csp, "frame-ancestors 'none'", fixed = TRUE)
  expect_match(csp, "object-src 'none'", fixed = TRUE)
  expect_match(csp, "base-uri 'self'", fixed = TRUE)
  expect_match(csp, "form-action 'self'", fixed = TRUE)
})

test_that("the CSP allows exactly the hosts the app uses", {
  csp <- security_headers()[["Content-Security-Policy"]]
  # Spotify's image CDNs (artist pictures), including hosts other than i.scdn.co
  expect_match(csp, "img-src [^;]*https://\\*\\.scdn\\.co")
  expect_match(csp, "img-src [^;]*https://\\*\\.spotifycdn\\.com")
  expect_match(csp, "font-src [^;]*https://fonts\\.cdnfonts\\.com")
  expect_match(csp, "style-src [^;]*https://fonts\\.cdnfonts\\.com")
  expect_match(csp, "connect-src 'self' wss:", fixed = TRUE)
  # nothing is allowed from arbitrary hosts: no bare * and no bare https:
  expect_false(grepl("(^|[; ])\\*([; ]|$)|https:(;| |$)", csp))
})

test_that("the CSP doesn't allow eval, and only allows inline script and style", {
  csp <- security_headers()[["Content-Security-Policy"]]
  expect_false(grepl("unsafe-eval", csp, fixed = TRUE))
  expect_match(csp, "script-src 'self' 'unsafe-inline'(;|$)")
  expect_match(csp, "style-src 'self' 'unsafe-inline' https://fonts\\.cdnfonts\\.com")
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
