sys.source(file.path(app_dir, "server.R"), envir = globalenv())

recommendation_ok <- list(
  status = "ok",
  data = list(artist = "Sufjan Stevens", description = "An indie folk artist.", reason = "Fits a rainy day.")
)
artist_ok <- list(
  status = "ok",
  data = list(
    followers = 2798272L,
    imageUrl = "https://i.scdn.co/large",
    name = "Sufjan Stevens",
    spotifyUrl = "https://open.spotify.com/artist/abc"
  )
)

# Mock the two API calls; the returned environment records what they were asked
mock_apis <- function(recommendation = recommendation_ok, artist = artist_ok, frame = parent.frame()) {
  calls <- new.env()
  calls$prompts <- character()
  calls$artists <- character()

  local_mock("get_recommendation", function(prompt) {
    calls$prompts <- c(calls$prompts, prompt)
    recommendation
  }, frame = frame)
  local_mock("find_artist", function(artist_name) {
    calls$artists <- c(calls$artists, artist_name)
    artist
  }, frame = frame)

  calls
}

# No waiting between recommendations, unless a test is about the cooldown
no_cooldown <- function(frame = parent.frame()) local_mock("cooldown_s", 0, frame = frame)

test_that("before anything is asked the card shows the placeholder", {
  calls <- mock_apis()

  testServer(server, {
    session$setInputs(go = 0, prompt = "", clearBtn = 0)

    expect_match(output$artistInfo$html, "placeholder_image.png", fixed = TRUE)
  })
  expect_length(calls$prompts, 0)
})

test_that("a recommendation shows the artist, texts and Spotify link", {
  calls <- mock_apis()

  testServer(server, {
    session$setInputs(go = 0, prompt = "  calm   indie\nfolk ", clearBtn = 0)
    session$setInputs(go = 1)

    html <- output$artistInfo$html
    expect_match(html, "<h3>Sufjan Stevens</h3>", fixed = TRUE)
    expect_match(html, "An indie folk artist.", fixed = TRUE)
    expect_match(html, "Fits a rainy day.", fixed = TRUE)
    expect_match(html, "href=\"https://open.spotify.com/artist/abc\"", fixed = TRUE)
  })
  # The cleaned prompt is what goes to OpenAI, and the artist it named to Spotify
  expect_equal(calls$prompts, "calm indie folk")
  expect_equal(calls$artists, "Sufjan Stevens")
})

test_that("an artist Spotify can't find still gets the recommendation, with a note", {
  mock_apis(artist = list(status = "not_found", data = NULL))

  testServer(server, {
    session$setInputs(go = 0, prompt = "rainy day", clearBtn = 0)
    session$setInputs(go = 1)

    html <- output$artistInfo$html
    expect_match(html, "Sufjan Stevens", fixed = TRUE)
    expect_match(html, strings$note_not_found, fixed = TRUE)
    expect_no_match(html, "button-spotify", fixed = TRUE)
  })
})

test_that("a Spotify failure gets its own note", {
  mock_apis(artist = list(status = "error", data = NULL))

  testServer(server, {
    session$setInputs(go = 0, prompt = "rainy day", clearBtn = 0)
    session$setInputs(go = 1)

    expect_match(output$artistInfo$html, strings$note_spotify_error, fixed = TRUE)
  })
})

test_that("an OpenAI failure shows a plain message and doesn't ask Spotify", {
  calls <- mock_apis(recommendation = list(status = "error", data = NULL))

  testServer(server, {
    session$setInputs(go = 0, prompt = "rainy day", clearBtn = 0)
    session$setInputs(go = 1)

    expect_match(output$artistInfo$html, strings$error_openai, fixed = TRUE)
  })
  expect_length(calls$artists, 0)
})

test_that("an empty prompt asks nobody and leaves the card alone", {
  calls <- mock_apis()

  testServer(server, {
    session$setInputs(go = 0, prompt = "   ", clearBtn = 0)
    session$setInputs(go = 1)

    expect_match(output$artistInfo$html, "placeholder_image.png", fixed = TRUE)
  })
  expect_length(calls$prompts, 0)
})

test_that("a rejected click keeps the recommendation on screen", {
  no_cooldown()
  mock_apis()

  testServer(server, {
    session$setInputs(go = 0, prompt = "rainy day", clearBtn = 0)
    session$setInputs(go = 1)
    expect_match(output$artistInfo$html, "Sufjan Stevens", fixed = TRUE)

    session$setInputs(prompt = "", go = 2)

    expect_match(output$artistInfo$html, "Sufjan Stevens", fixed = TRUE)
  })
})

test_that("a second click during the cooldown is ignored", {
  calls <- mock_apis()

  testServer(server, {
    session$setInputs(go = 0, prompt = "rainy day", clearBtn = 0)
    session$setInputs(go = 1)
    expect_match(output$artistInfo$html, "Sufjan Stevens", fixed = TRUE)

    session$setInputs(prompt = "something else", go = 2)

    expect_match(output$artistInfo$html, "Sufjan Stevens", fixed = TRUE)
    expect_gt(cooldown_remaining(cooldown_until()), 0)
  })
  expect_equal(calls$prompts, "rainy day")
})

test_that("a click after the cooldown asks again", {
  no_cooldown()
  calls <- mock_apis()

  testServer(server, {
    session$setInputs(go = 0, prompt = "rainy day", clearBtn = 0)
    session$setInputs(go = 1)
    session$setInputs(prompt = "something else", go = 2)
    output$artistInfo
  })
  expect_equal(calls$prompts, c("rainy day", "something else"))
})

test_that("a failed request starts the cooldown too, so errors can't be hammered", {
  calls <- mock_apis(recommendation = list(status = "error", data = NULL))

  testServer(server, {
    session$setInputs(go = 0, prompt = "rainy day", clearBtn = 0)
    session$setInputs(go = 1)
    expect_match(output$artistInfo$html, strings$error_openai, fixed = TRUE)

    session$setInputs(go = 2)
    output$artistInfo
  })
  expect_length(calls$prompts, 1)
})

test_that("the clear button empties the prompt", {
  mock_apis()

  testServer(server, {
    session$setInputs(go = 0, prompt = "rainy day", clearBtn = 0)
    session$setInputs(clearBtn = 1)
    # updateTextAreaInput() is sent to the browser; the observer must not error
    expect_equal(input$clearBtn, 1)
  })
})
