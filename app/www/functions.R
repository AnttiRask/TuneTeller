# Pure helpers: no network, no reactivity.

# Input ------------------------------------------------------------------------

# Make the user's text safe to send on: control characters and runs of
# whitespace become single spaces, the tags we fence the text in are removed,
# and the length is capped
clean_prompt <- function(x, max_chars = prompt_max_chars) {
  if (is.null(x) || length(x) != 1 || is.na(x)) {
    return("")
  }

  x %>%
    str_replace_all("[[:cntrl:]]", " ") %>%
    str_remove_all("(?i)</?request>") %>%
    str_squish() %>%
    str_sub(end = max_chars)
}

# Seconds left of a cooldown that ends at `until` (NULL if none has started)
cooldown_remaining <- function(until, now = Sys.time()) {
  if (is.null(until)) {
    return(0)
  }

  max(0, as.numeric(difftime(until, now, units = "secs")))
}

# OpenAI -------------------------------------------------------------------------

# The JSON body for the Responses API. store = FALSE so OpenAI doesn't keep the
# prompts; GPT-5.4 models reject `temperature` and `reasoning: minimal`
build_openai_body <- function(prompt) {
  list(
    model = openai_model,
    instructions = prompt_ver3$instructions,
    input = str_c("<request>", prompt, "</request>"),
    max_output_tokens = openai_max_output_tokens,
    reasoning = list(effort = "none"),
    store = FALSE,
    text = list(
      format = list(
        type = "json_schema",
        name = "recommendation",
        strict = TRUE,
        schema = prompt_ver3$schema
      )
    )
  )
}

is_nonblank_string <- function(x) {
  is.character(x) && length(x) == 1 && !is.na(x) && nzchar(str_trim(x))
}

# Pull the recommendation (list of artist, description, reason) out of a parsed
# Responses API reply; NULL if the reply isn't a complete, valid recommendation
# (refusal, cut off, not JSON, a field missing or blank)
parse_recommendation <- function(response) {
  text <- response$output %>%
    keep(~ identical(.x$type, "message")) %>%
    pluck(1, "content") %>%
    keep(~ identical(.x$type, "output_text")) %>%
    pluck(1, "text")

  if (!is_nonblank_string(text)) {
    return(NULL)
  }

  recommendation <- tryCatch(
    jsonlite::fromJSON(text, simplifyVector = FALSE),
    error = function(e) NULL
  )

  fields <- c("artist", "description", "reason")
  valid <- is.list(recommendation) &&
    all(map_lgl(fields, ~ is_nonblank_string(recommendation[[.x]])))

  if (!valid) {
    return(NULL)
  }

  map(recommendation[fields], str_squish)
}

# Spotify ------------------------------------------------------------------------

# Only https links are put on the page
is_https_url <- function(x) {
  is_nonblank_string(x) && str_detect(x, "^https://")
}

format_followers <- function(x) {
  if (is.null(x) || length(x) != 1 || is.na(x)) {
    return(NA_character_)
  }

  format(x, big.mark = ",", scientific = FALSE, trim = TRUE)
}

# Theme --------------------------------------------------------------------------

# CSS custom properties for both colour modes, so the colours are defined once
# (variables.R) and styles.css only refers to them. Dark is the default mode.
theme_css <- function(colours = brand_colours) {
  str_c(
    ":root{",
    "--tt-accent:", colours$red, ";",
    "--tt-link:", colours$red, ";",
    "--tt-card-bg:", colours$light_card, ";",
    "--tt-card-border:", colours$light_border, ";",
    "}",
    ":root[data-bs-theme=dark]{",
    "--bs-body-bg:", colours$dark_bg, ";",
    "--bs-body-color:#FFFFFF;",
    "--tt-link:", colours$red_on_dark, ";",
    "--tt-card-bg:", colours$dark_card, ";",
    "--tt-card-border:", colours$dark_border, ";",
    "}"
  )
}

# Artist card --------------------------------------------------------------------

# What the card shows for a result. `result$state` is one of:
#   idle      nothing asked yet
#   ok        recommendation + Spotify details
#   no_artist recommendation, but no Spotify details (`result$note` says why)
#   error     the recommendation failed
artist_card_ui <- function(result) {
  recommendation <- result$recommendation
  artist <- result$artist

  switch(
    result$state,
    idle = tagList(
      img(
        src = "placeholder_image.png",
        alt = strings$placeholder_alt,
        height = "200px"
      )
    ),
    error = h3(strings$error_openai),
    ok = tagList(
      img(
        src = artist$imageUrl,
        alt = str_glue(strings$artist_image_alt, name = artist$name),
        height = "200px"
      ),
      br(),
      br(),
      h3(artist$name),
      p(recommendation$description),
      p(recommendation$reason),
      if (!is.na(format_followers(artist$followers))) {
        p(str_c(strings$followers, " ", format_followers(artist$followers)))
      },
      br(),
      tags$a(
        href = artist$spotifyUrl,
        target = "_blank",
        rel = "noopener noreferrer",
        class = "button-spotify",
        icon("spotify", lib = "font-awesome"),
        strings$spotify_button
      )
    ),
    no_artist = tagList(
      h3(recommendation$artist),
      p(recommendation$description),
      p(recommendation$reason),
      p(class = "text-muted", result$note)
    )
  )
}
