# Spotify API helpers.
# Replaces {spotifyr}: version 2.2.5 sends the access token as a URL query
# parameter (access_token=...), which Spotify now rejects with HTTP 401.
# Here the token goes in an Authorization header instead.

# Get an app-only access token with the client credentials flow
get_spotify_token <- function(
  client_id = Sys.getenv("SPOTIFY_CLIENT_ID"),
  client_secret = Sys.getenv("SPOTIFY_CLIENT_SECRET")
) {
  request("https://accounts.spotify.com/api/token") %>%
    req_auth_basic(client_id, client_secret) %>%
    req_body_form(grant_type = "client_credentials") %>%
    req_perform() %>%
    resp_body_json() %>%
    pluck("access_token")
}

# Search for an artist by name; returns a list with the details shown in the
# UI, or NULL if the artist wasn't found or has no images
search_spotify_artist <- function(artist_name, token = get_spotify_token()) {
  if (is.na(artist_name) || !nzchar(artist_name)) {
    return(NULL)
  }

  artist <- request("https://api.spotify.com/v1/search") %>%
    req_url_query(q = artist_name, type = "artist", limit = 1) %>%
    req_auth_bearer_token(token) %>%
    req_retry(max_tries = 3) %>%
    req_perform() %>%
    resp_body_json() %>%
    pluck("artists", "items", 1)

  if (is.null(artist) || length(artist$images) == 0) {
    return(NULL)
  }

  list(
    followers = pluck(artist, "followers", "total"),
    # Spotify lists the largest image first
    imageUrl = pluck(artist, "images", 1, "url"),
    name = pluck(artist, "name"),
    spotifyUrl = pluck(artist, "external_urls", "spotify")
  )
}
