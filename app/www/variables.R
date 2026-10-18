# Settings and constants. All user-facing text lives in strings.R.

# OpenAI ----------------------------------------------------------------------

openai_url <- "https://api.openai.com/v1/responses"
# GPT-4o mini is retired on 2027-01-14. gpt-5.4-nano follows the JSON schema
# (12/12 test requests) at a fraction of a cent per recommendation;
# gpt-5.4-mini is the fallback if its picks ever disappoint.
openai_model <- "gpt-5.4-nano"
openai_max_output_tokens <- 1000

# Limits ----------------------------------------------------------------------

# Seconds to wait for OpenAI or Spotify before giving up
request_timeout_s <- 20

# Longest prompt accepted from the user
prompt_max_chars <- 190
# Seconds before the same session can ask for another recommendation (each one
# costs money, and the app is public)
cooldown_s <- 10

# Spotify ---------------------------------------------------------------------

spotify_token_url <- "https://accounts.spotify.com/api/token"
spotify_search_url <- "https://api.spotify.com/v1/search"

# Brand colours ---------------------------------------------------------------

# The red is 5.8:1 on white but only 3.1:1 on the dark background, so small text
# (links) uses the lighter red in dark mode; large headings keep the brand red.
brand_colours <- list(
  red = "#C1272D",
  red_on_dark = "#F26B70",
  dark_bg = "#191414",
  dark_card = "#1A1A1A",
  dark_border = "#E5E5E5",
  light_card = "#F6F4F4",
  light_border = "#CFC9C9"
)

# Footer ----------------------------------------------------------------------

# Sibling apps linked from the footer (the app itself is left out, see
# create_app_footer() in ui.R)
footer_apps <- list(
  list(id = "bibliostatus", label = "BiblioStatus", url = "https://bibliostatus.youcanbeapirate.com"),
  list(id = "fillaristatus", label = "FillariStatus", url = "https://fillaristatus.youcanbeapirate.com"),
  list(id = "gallery", label = "Gallery of the Day", url = "https://galleryoftheday.youcanbeapirate.com"),
  list(id = "trackteller", label = "TrackTeller", url = "https://trackteller.youcanbeapirate.com"),
  list(id = "tuneteller", label = "TuneTeller", url = "https://tuneteller.youcanbeapirate.com")
)
