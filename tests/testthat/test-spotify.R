library(httr2)
library(purrr)
library(magrittr)

source(test_path("../../app/www/spotify.R"))

json_response <- function(body, status = 200) {
  response_json(status_code = status, body = body)
}

artist_body <- list(
  artists = list(
    items = list(
      list(
        name = "Sufjan Stevens",
        followers = list(total = 2798272L),
        external_urls = list(spotify = "https://open.spotify.com/artist/abc"),
        images = list(
          list(url = "https://i.scdn.co/large"),
          list(url = "https://i.scdn.co/small")
        )
      )
    )
  )
)

test_that("get_spotify_token() requests a token with basic auth", {
  seen <- NULL
  local_mocked_responses(function(req) {
    seen <<- req
    json_response(list(access_token = "tok", expires_in = 3600))
  })

  expect_equal(get_spotify_token("id", "secret"), "tok")
  expect_match(seen$url, "accounts.spotify.com/api/token")
  expect_match(req_get_headers(seen, "reveal")$Authorization, "^Basic ")
})

test_that("search_spotify_artist() sends the token as a header, not in the URL", {
  seen <- NULL
  local_mocked_responses(function(req) {
    seen <<- req
    json_response(artist_body)
  })

  search_spotify_artist("Sufjan Stevens", token = "tok")

  expect_equal(req_get_headers(seen, "reveal")$Authorization, "Bearer tok")
  expect_no_match(seen$url, "access_token")
})

test_that("search_spotify_artist() returns the details shown in the UI", {
  local_mocked_responses(function(req) json_response(artist_body))

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

test_that("search_spotify_artist() returns NULL without a match or images", {
  local_mocked_responses(function(req) {
    json_response(list(artists = list(items = list())))
  })
  expect_null(search_spotify_artist("Nobody", token = "tok"))

  no_images <- artist_body
  no_images$artists$items[[1]]$images <- list()
  local_mocked_responses(function(req) json_response(no_images))
  expect_null(search_spotify_artist("Sufjan Stevens", token = "tok"))
})

test_that("search_spotify_artist() returns NULL for a missing name without a request", {
  local_mocked_responses(function(req) stop("no request expected"))

  expect_null(search_spotify_artist(NA_character_, token = "tok"))
  expect_null(search_spotify_artist("", token = "tok"))
})

test_that("search_spotify_artist() errors on an HTTP failure", {
  local_mocked_responses(function(req) json_response(list(), status = 401))

  expect_error(search_spotify_artist("Sufjan Stevens", token = "tok"))
})
