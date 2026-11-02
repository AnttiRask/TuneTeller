# GET /health: is this instance configured to work? 200 "ok", or 503 naming what is wrong
# (names only, never values). No call to OpenAI or Spotify: an outage there must not make
# a deploy or an uptime check fail, and every probe would cost a request.

# What is wrong with the configuration, as a character vector (empty when all is well).
# A Spotify client id or secret is 32 lowercase hex characters; an OpenAI key is a long
# string without whitespace or quotes (a key that arrives wrapped in quotes, as values in
# a .env file can, is the mistake this catches).
health_problems <- function(openai_key, spotify_id, spotify_secret) {
  is_openai_key <- function(x) {
    is.character(x) && length(x) == 1 && !is.na(x) && nchar(x) >= 20 && !grepl("[[:space:]\"']", x)
  }
  is_spotify_credential <- function(x) {
    is.character(x) && length(x) == 1 && !is.na(x) && grepl("^[a-f0-9]{32}$", x)
  }

  problems <- character(0)
  if (!is_openai_key(openai_key)) problems <- c(problems, "OPENAI_API_KEY")
  if (!is_spotify_credential(spotify_id)) problems <- c(problems, "SPOTIFY_CLIENT_ID")
  if (!is_spotify_credential(spotify_secret)) problems <- c(problems, "SPOTIFY_CLIENT_SECRET")
  problems
}

health_response <- function(problems) {
  headers <- list(`Cache-Control` = "no-store")

  if (length(problems) == 0) {
    shiny::httpResponse(200L, "text/plain; charset=utf-8", "ok", headers = headers)
  } else {
    shiny::httpResponse(
      503L,
      "text/plain; charset=utf-8",
      paste0("unhealthy: ", paste(problems, collapse = ", ")),
      headers = headers
    )
  }
}

# The shinyApp() object, answering /health itself. `check` is a function returning the
# problems (the tests give their own). The environment is read on every request, so a
# changed secret shows up on the next revision and nowhere else.
with_health_check <- function(
  app,
  check = function() {
    health_problems(
      Sys.getenv("OPENAI_API_KEY"),
      Sys.getenv("SPOTIFY_CLIENT_ID"),
      Sys.getenv("SPOTIFY_CLIENT_SECRET")
    )
  }
) {
  handler <- app$httpHandler
  app$httpHandler <- function(req) {
    if (identical(req$PATH_INFO, "/health") && req$REQUEST_METHOD %in% c("GET", "HEAD")) {
      return(health_response(check()))
    }
    handler(req)
  }
  app
}
