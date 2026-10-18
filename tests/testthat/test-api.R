# OpenAI ---------------------------------------------------------------------

test_that("get_recommendation() returns the parsed recommendation", {
  local_mocked_responses(function(req) {
    json_response(openai_reply(recommendation_json()))
  })

  result <- get_recommendation("rainy day")

  expect_equal(result$status, "ok")
  expect_equal(
    result$data,
    list(
      artist = "Sufjan Stevens",
      description = "An indie folk artist.",
      reason = "Fits a rainy day."
    )
  )
})

test_that("get_recommendation() sends the key, the model, the JSON schema and store = FALSE", {
  seen <- NULL
  local_mocked_responses(function(req) {
    seen <<- req
    json_response(openai_reply(recommendation_json()))
  })
  withr::local_envvar(OPENAI_API_KEY = "test-key")

  get_recommendation("rainy day")

  expect_equal(req_get_headers(seen, "reveal")$Authorization, "Bearer test-key")
  expect_equal(seen$url, openai_url)
  body <- seen$body$data
  expect_equal(body$model, openai_model)
  expect_false(body$store)
  expect_equal(body$text$format$type, "json_schema")
  expect_true(body$text$format$strict)
  expect_equal(body$input, "<request>rainy day</request>")
  # GPT-5.4 models reject these
  expect_null(body$temperature)
  expect_equal(body$reasoning$effort, "none")
})

test_that("get_recommendation() never throws", {
  # HTTP error
  local_mocked_responses(function(req) json_response(list(), status = 401))
  expect_equal(get_recommendation("x"), list(status = "error", data = NULL))

  # Network failure
  local_mocked_responses(function(req) stop("connection refused"))
  expect_equal(get_recommendation("x"), list(status = "error", data = NULL))

  # A reply that isn't a valid recommendation
  local_mocked_responses(function(req) json_response(openai_reply("not json")))
  expect_equal(get_recommendation("x"), list(status = "error", data = NULL))
})

test_that("get_recommendation() doesn't log the prompt or the response body", {
  local_mocked_responses(function(req) {
    json_response(list(error = list(message = "secret detail")), status = 400)
  })

  messages <- capture_messages(get_recommendation("my private prompt"))

  expect_false(any(str_detect(messages, "my private prompt|secret detail")))
})

# Spotify --------------------------------------------------------------------

test_that("get_spotify_token() requests a token with basic auth", {
  seen <- NULL
  local_mocked_responses(function(req) {
    seen <<- req
    json_response(list(access_token = "tok", expires_in = 3600))
  })

  expect_equal(get_spotify_token("id", "secret"), "tok")
  expect_equal(seen$url, spotify_token_url)
  expect_match(req_get_headers(seen, "reveal")$Authorization, "^Basic ")
})

test_that("search_spotify_artist() sends the token as a header, not in the URL", {
  seen <- NULL
  local_mocked_responses(function(req) {
    seen <<- req
    json_response(spotify_artist_body())
  })

  search_spotify_artist("Sufjan Stevens", token = "tok")

  expect_equal(req_get_headers(seen, "reveal")$Authorization, "Bearer tok")
  expect_no_match(seen$url, "access_token")
})

test_that("search_spotify_artist() returns the details shown in the UI", {
  local_mocked_responses(function(req) json_response(spotify_artist_body()))

  expect_equal(
    search_spotify_artist("Sufjan Stevens", token = "tok"),
    list(
      followers = 2798272L,
      imageUrl = "https://i.scdn.co/large",
      name = "Sufjan Stevens",
      spotifyUrl = "https://open.spotify.com/artist/abc"
    )
  )
})

test_that("search_spotify_artist() returns NULL without a match, an image or https links", {
  local_mocked_responses(function(req) {
    json_response(list(artists = list(items = list())))
  })
  expect_null(search_spotify_artist("Nobody", token = "tok"))

  local_mocked_responses(function(req) json_response(spotify_artist_body(images = list())))
  expect_null(search_spotify_artist("Sufjan Stevens", token = "tok"))

  local_mocked_responses(function(req) {
    json_response(spotify_artist_body(images = list(list(url = "http://i.scdn.co/large"))))
  })
  expect_null(search_spotify_artist("Sufjan Stevens", token = "tok"))

  local_mocked_responses(function(req) {
    json_response(spotify_artist_body(spotify_url = "javascript:alert(1)"))
  })
  expect_null(search_spotify_artist("Sufjan Stevens", token = "tok"))
})

test_that("search_spotify_artist() returns NULL for a missing name without a request", {
  local_mocked_responses(function(req) stop("no request expected"))

  expect_null(search_spotify_artist(NA_character_, token = "tok"))
  expect_null(search_spotify_artist("", token = "tok"))
})

test_that("find_artist() reports ok, not_found and error", {
  local_mock("search_spotify_artist", function(artist_name) list(name = artist_name))
  expect_equal(find_artist("X"), list(status = "ok", data = list(name = "X")))

  local_mock("search_spotify_artist", function(artist_name) NULL)
  expect_equal(find_artist("X"), list(status = "not_found", data = NULL))

  local_mock("search_spotify_artist", function(artist_name) stop("HTTP 401 Unauthorized."))
  expect_equal(find_artist("X"), list(status = "error", data = NULL))
})
