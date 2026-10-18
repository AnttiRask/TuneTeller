# Load the app's code (what global.R does) so the tests can use it

suppressPackageStartupMessages({
  library(bslib)
  library(httr2)
  library(purrr)
  library(shiny)
  library(shinycssloaders)
  library(stringr)
})

app_dir <- normalizePath(test_path("../../app"))

for (file in c("variables.R", "strings.R", "prompt_versions.R", "functions.R", "api.R")) {
  sys.source(file.path(app_dir, "www", file), envir = globalenv())
}

# A parsed Responses API reply with one message holding `text`
openai_reply <- function(text, type = "output_text") {
  list(
    status = "completed",
    output = list(
      list(type = "reasoning", summary = list()),
      list(type = "message", content = list(list(type = type, text = text)))
    )
  )
}

recommendation_json <- function(
  artist = "Sufjan Stevens",
  description = "An indie folk artist.",
  reason = "Fits a rainy day."
) {
  jsonlite::toJSON(
    list(artist = artist, description = description, reason = reason),
    auto_unbox = TRUE
  ) %>%
    as.character()
}

json_response <- function(body, status = 200) {
  response_json(status_code = status, body = body)
}

spotify_artist_body <- function(
  images = list(
    list(url = "https://i.scdn.co/large"),
    list(url = "https://i.scdn.co/small")
  ),
  spotify_url = "https://open.spotify.com/artist/abc"
) {
  list(
    artists = list(
      items = list(
        list(
          name = "Sufjan Stevens",
          followers = list(total = 2798272L),
          external_urls = list(spotify = spotify_url),
          images = images
        )
      )
    )
  )
}

# Replace a function from the app's code for the rest of the calling test
local_mock <- function(name, fn, env = globalenv(), frame = parent.frame()) {
  original <- get(name, envir = env)
  assign(name, fn, envir = env)
  withr::defer(assign(name, original, envir = env), envir = frame)
}
