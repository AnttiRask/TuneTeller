source(test_path("../../app/scripts/health.R"))
source(test_path("../../app/scripts/security.R"))

good_openai_key <- "sk-proj-abcdefghijklmnopqrstuvwxyz0123456789"
good_spotify <- "0123456789abcdef0123456789abcdef"

test_that("health_problems() is empty when the configuration is fine", {
  expect_equal(health_problems(good_openai_key, good_spotify, good_spotify), character(0))
})

test_that("health_problems() names each broken setting, and only those", {
  expect_equal(health_problems("", good_spotify, good_spotify), "OPENAI_API_KEY")
  expect_equal(health_problems(good_openai_key, "", good_spotify), "SPOTIFY_CLIENT_ID")
  expect_equal(health_problems(good_openai_key, good_spotify, ""), "SPOTIFY_CLIENT_SECRET")
  expect_equal(
    health_problems("", "", ""),
    c("OPENAI_API_KEY", "SPOTIFY_CLIENT_ID", "SPOTIFY_CLIENT_SECRET")
  )
})

test_that("health_problems() catches keys that arrive wrapped in quotes or with whitespace", {
  # the .env file's values are quoted; a quote that survives into the environment breaks the call
  expect_equal(health_problems(paste0("\"", good_openai_key, "\""), good_spotify, good_spotify), "OPENAI_API_KEY")
  expect_equal(health_problems(paste0(good_openai_key, "\n"), good_spotify, good_spotify), "OPENAI_API_KEY")
  expect_equal(health_problems(good_openai_key, paste0("'", good_spotify, "'"), good_spotify), "SPOTIFY_CLIENT_ID")
  expect_equal(health_problems(good_openai_key, good_spotify, toupper(good_spotify)), "SPOTIFY_CLIENT_SECRET")
  expect_equal(health_problems(good_openai_key, good_spotify, substr(good_spotify, 1, 31)), "SPOTIFY_CLIENT_SECRET")
})

test_that("health_problems() copes with missing values", {
  expect_equal(health_problems(NULL, NA_character_, character(0)), c("OPENAI_API_KEY", "SPOTIFY_CLIENT_ID", "SPOTIFY_CLIENT_SECRET"))
})

test_that("health_response() is 200 ok when nothing is wrong, 503 naming the problems otherwise", {
  ok <- health_response(character(0))
  expect_equal(ok$status, 200L)
  expect_equal(ok$content, "ok")
  expect_equal(ok$headers[["Cache-Control"]], "no-store")

  bad <- health_response(c("OPENAI_API_KEY", "SPOTIFY_CLIENT_ID"))
  expect_equal(bad$status, 503L)
  expect_equal(bad$content, "unhealthy: OPENAI_API_KEY, SPOTIFY_CLIENT_ID")
})

test_that("a 503 never contains a value, only names", {
  secret <- "sk-proj-THIS-MUST-NEVER-BE-PRINTED-0123456789\n"
  bad <- health_response(health_problems(secret, good_spotify, good_spotify))
  expect_no_match(bad$content, "THIS-MUST-NEVER", fixed = TRUE)
})

fake_app <- function(handler) structure(list(httpHandler = handler), class = "shiny.appobj")
page <- function(req) shiny::httpResponse(200, "text/html", "<p>page</p>")

test_that("with_health_check() answers GET and HEAD /health itself and leaves other requests alone", {
  app <- with_health_check(fake_app(page), check = function() character(0))

  get <- app$httpHandler(list(PATH_INFO = "/health", REQUEST_METHOD = "GET"))
  expect_equal(get$status, 200L)
  expect_equal(get$content, "ok")
  expect_equal(app$httpHandler(list(PATH_INFO = "/health", REQUEST_METHOD = "HEAD"))$status, 200L)

  expect_equal(app$httpHandler(list(PATH_INFO = "/", REQUEST_METHOD = "GET"))$content, "<p>page</p>")
  expect_equal(app$httpHandler(list(PATH_INFO = "/healthz", REQUEST_METHOD = "GET"))$content, "<p>page</p>")
  # not a read-only request: the page's handler decides
  expect_equal(app$httpHandler(list(PATH_INFO = "/health", REQUEST_METHOD = "POST"))$content, "<p>page</p>")
})

test_that("with_health_check() reports what the check finds", {
  app <- with_health_check(fake_app(page), check = function() "OPENAI_API_KEY")
  res <- app$httpHandler(list(PATH_INFO = "/health", REQUEST_METHOD = "GET"))

  expect_equal(res$status, 503L)
  expect_equal(res$content, "unhealthy: OPENAI_API_KEY")
})

test_that("with_health_check() reads the environment on every request by default", {
  app <- with_health_check(fake_app(page))

  withr::local_envvar(OPENAI_API_KEY = good_openai_key, SPOTIFY_CLIENT_ID = good_spotify, SPOTIFY_CLIENT_SECRET = good_spotify)
  expect_equal(app$httpHandler(list(PATH_INFO = "/health", REQUEST_METHOD = "GET"))$status, 200L)

  withr::local_envvar(OPENAI_API_KEY = "")
  expect_equal(app$httpHandler(list(PATH_INFO = "/health", REQUEST_METHOD = "GET"))$status, 503L)
})

test_that("the health response gets the security headers when wrapped as run.R does", {
  app <- with_security_headers(with_health_check(fake_app(page), check = function() character(0)))
  res <- app$httpHandler(list(PATH_INFO = "/health", REQUEST_METHOD = "GET"))

  expect_equal(res$status, 200L)
  expect_equal(res$headers[["X-Frame-Options"]], "DENY")
  expect_true("Content-Security-Policy" %in% names(res$headers))
  expect_equal(res$headers[["Cache-Control"]], "no-store")
})
