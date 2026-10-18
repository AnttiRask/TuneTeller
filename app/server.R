server <- function(input, output, session) {
  # When the next recommendation may be asked for (NULL until the first one)
  cooldown_until <- reactiveVal(NULL)
  # What the card showed last, so a rejected click doesn't wipe it
  previous_result <- list(state = "idle")

  # Ask OpenAI for an artist and Spotify for the details when 'Get
  # Recommendation' is clicked. The result is a list for artist_card_ui(); the
  # spinner shows while this runs because the card output depends on it.
  recommendation_result <- eventReactive(
    input$go,
    {
      prompt <- clean_prompt(input$prompt)

      if (!nzchar(prompt)) {
        showNotification(strings$prompt_empty, type = "warning")
        return(previous_result)
      }
      # The button is disabled during the cooldown; this is the server-side guard
      if (cooldown_remaining(cooldown_until()) > 0) {
        showNotification(strings$cooldown, type = "warning")
        return(previous_result)
      }

      cooldown_until(Sys.time() + cooldown_s)

      recommendation <- get_recommendation(prompt)
      if (recommendation$status != "ok") {
        result <- list(state = "error")
      } else {
        artist <- find_artist(recommendation$data$artist)
        if (artist$status == "ok") {
          result <- list(state = "ok", recommendation = recommendation$data, artist = artist$data)
        } else {
          note <- if (artist$status == "not_found") strings$note_not_found else strings$note_spotify_error
          result <- list(state = "no_artist", recommendation = recommendation$data, note = note)
        }
      }

      previous_result <<- result
      result
    }
  )

  # Disable the button and count down while the cooldown runs
  observe({
    remaining <- cooldown_remaining(cooldown_until())

    if (!is.null(cooldown_until())) {
      session$sendCustomMessage(
        "tt-cooldown",
        list(
          disabled = remaining > 0,
          label = if (remaining > 0) {
            str_glue(strings$button_wait, seconds = ceiling(remaining))
          } else {
            strings$button_go
          }
        )
      )
    }

    if (remaining > 0) {
      invalidateLater(1000)
    }
  })

  # Enforce the character limit on the text prompt
  observeEvent(
    input$prompt,
    {
      if (str_length(input$prompt) > prompt_max_chars) {
        showNotification(str_glue(strings$prompt_too_long), type = "warning")
        updateTextAreaInput(session, "prompt", value = str_sub(input$prompt, end = prompt_max_chars))
      }
    },
    ignoreInit = TRUE
  )

  # Listener for the Clear text button
  observeEvent(
    input$clearBtn,
    updateTextAreaInput(session, "prompt", value = ""),
    ignoreInit = TRUE
  )

  output$artistInfo <- renderUI({
    # Nothing asked yet: show the placeholder picture
    if (input$go == 0) {
      return(artist_card_ui(list(state = "idle")))
    }

    artist_card_ui(recommendation_result())
  })
}
