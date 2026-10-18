# API calls: OpenAI (the recommendation) and Spotify (the artist's details).
# get_recommendation() and find_artist() never throw: they return
# list(status, data), with status "ok" / "error" (and "not_found" for Spotify).

# First line of an error message only: httr2 appends the response body, which
# we don't want in the logs
error_summary <- function(e) {
  str_extract(conditionMessage(e), "^[^\n]*")
}

# OpenAI -----------------------------------------------------------------------

call_openai <- function(prompt) {
  request(openai_url) %>%
    req_auth_bearer_token(Sys.getenv("OPENAI_API_KEY")) %>%
    req_body_json(build_openai_body(prompt)) %>%
    req_timeout(request_timeout_s) %>%
    req_retry(max_tries = 2) %>%
    req_perform() %>%
    resp_body_json()
}

# Ask for one artist; data is list(artist, description, reason)
get_recommendation <- function(prompt) {
  tryCatch(
    {
      recommendation <- call_openai(prompt) %>% parse_recommendation()

      if (is.null(recommendation)) {
        message("OpenAI request failed: no valid recommendation in the reply")
        return(list(status = "error", data = NULL))
      }

      list(status = "ok", data = recommendation)
    },
    error = function(e) {
      message("OpenAI request failed: ", error_summary(e))
      list(status = "error", data = NULL)
    }
  )
}

# Spotify ----------------------------------------------------------------------
# Not {spotifyr}: version 2.2.5 sends the access token as a URL query parameter
# (access_token=...), which Spotify now rejects with HTTP 401. Here the token
# goes in an Authorization header instead.

# Get an app-only access token with the client credentials flow
get_spotify_token <- function(
  client_id = Sys.getenv("SPOTIFY_CLIENT_ID"),
  client_secret = Sys.getenv("SPOTIFY_CLIENT_SECRET")
) {
  request(spotify_token_url) %>%
    req_auth_basic(client_id, client_secret) %>%
    req_body_form(grant_type = "client_credentials") %>%
    req_timeout(request_timeout_s) %>%
    req_perform() %>%
    resp_body_json() %>%
    pluck("access_token")
}

# Search for an artist by name; returns a list with the details shown in the
# UI, or NULL if the artist wasn't found, has no image, or the links aren't https
search_spotify_artist <- function(artist_name, token = get_spotify_token()) {
  if (!is_nonblank_string(artist_name)) {
    return(NULL)
  }

  artist <- request(spotify_search_url) %>%
    req_url_query(q = artist_name, type = "artist", limit = 1) %>%
    req_auth_bearer_token(token) %>%
    req_timeout(request_timeout_s) %>%
    req_retry(max_tries = 3) %>%
    req_perform() %>%
    resp_body_json() %>%
    pluck("artists", "items", 1)

  details <- list(
    followers = pluck(artist, "followers", "total"),
    # Spotify lists the largest image first
    imageUrl = pluck(artist, "images", 1, "url"),
    name = pluck(artist, "name"),
    spotifyUrl = pluck(artist, "external_urls", "spotify")
  )

  if (is.null(artist) || !is_https_url(details$imageUrl) || !is_https_url(details$spotifyUrl)) {
    return(NULL)
  }

  details
}

find_artist <- function(artist_name) {
  tryCatch(
    {
      details <- search_spotify_artist(artist_name)

      if (is.null(details)) {
        return(list(status = "not_found", data = NULL))
      }

      list(status = "ok", data = details)
    },
    error = function(e) {
      message("Spotify request failed: ", error_summary(e))
      list(status = "error", data = NULL)
    }
  )
}
