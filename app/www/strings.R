# All user-facing text. Templates with {name} are filled with str_glue().

strings <- list(
  title = "TuneTeller",

  # Input
  prompt_placeholder = str_glue(
    "Describe to me, in {prompt_max_chars} characters or less, what kind of music you would like to hear. \n\nI will then recommend you an artist to listen to!"
  ),
  button_go = "Get Recommendation",
  button_wait = "Please wait ({seconds} s)",
  button_clear = "Clear Text",

  # Notifications
  prompt_empty = "Describe the music you would like to hear first.",
  prompt_too_long = "You exceeded the {prompt_max_chars} character limit!",
  cooldown = "Give me a moment before the next recommendation.",

  # Artist card
  placeholder_alt = "Illustration of a fortune teller with a crystal ball",
  artist_image_alt = "Photo of {name}",
  followers = "Spotify Followers:",
  spotify_button = "View on Spotify",
  error_openai = "Sorry, I couldn't come up with a recommendation just now. Please try again in a moment.",
  note_not_found = "I couldn't find this artist on Spotify.",
  note_spotify_error = "I couldn't reach Spotify just now, so there is no picture or link.",

  # Footer
  footer_created_by = "Created by ",
  footer_author = "Antti Rask",
  footer_site = "youcanbeapirate.com"
)
