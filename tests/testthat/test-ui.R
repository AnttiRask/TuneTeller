# ui.R reads www/styles.css relative to the app directory, as Shiny runs it
withr::with_dir(app_dir, sys.source("ui.R", envir = globalenv()))

footer_links <- function(current_app) {
  as.character(create_app_footer(current_app)) %>%
    str_extract_all("href=\"[^\"]+\"") %>%
    pluck(1)
}

test_that("the footer links the sibling apps, including FillariStatus, but not the app itself", {
  links <- footer_links("tuneteller")

  expect_true("href=\"https://fillaristatus.youcanbeapirate.com\"" %in% links)
  expect_true("href=\"https://bibliostatus.youcanbeapirate.com\"" %in% links)
  expect_true("href=\"https://galleryoftheday.youcanbeapirate.com\"" %in% links)
  expect_true("href=\"https://trackteller.youcanbeapirate.com\"" %in% links)
  expect_false("href=\"https://tuneteller.youcanbeapirate.com\"" %in% links)
  # no source-repo link
  expect_false(any(str_detect(links, "github")))
})

test_that("the footer keeps the cross-app format", {
  html <- as.character(create_app_footer("tuneteller"))

  expect_match(html, "<footer class=\"app-footer", fixed = TRUE)
  expect_match(html, "footer-apps", fixed = TRUE)
  expect_match(html, "Created by", fixed = TRUE)
  expect_match(html, "https://www.linkedin.com/in/AnttiRask/", fixed = TRUE)
  expect_match(html, "https://youcanbeapirate.com", fixed = TRUE)
})

test_that("the page has the colours of both modes and loads the mode switch before the body", {
  rendered <- htmltools::renderTags(ui)

  expect_match(rendered$head, ":root[data-bs-theme=dark]{", fixed = TRUE)
  expect_match(rendered$head, "<script src=\"mode-toggle.js\"></script>", fixed = TRUE)
  expect_match(rendered$head, "<script src=\"cooldown.js\"></script>", fixed = TRUE)
  expect_match(rendered$head, "<title>TuneTeller</title>", fixed = TRUE)
  # bslib's own switch is gone: its icon always shows the current mode
  expect_no_match(rendered$html, "bslib-input-dark-mode", fixed = TRUE)
  expect_match(rendered$html, "id=\"mode-toggle\"", fixed = TRUE)
})

test_that("the mode switch is a labelled button with a sun and a moon", {
  html <- as.character(mode_toggle_button())

  expect_match(html, "<button id=\"mode-toggle\" type=\"button\"", fixed = TRUE)
  expect_match(html, str_c("data-label-to-light=\"", strings$mode_to_light, "\""), fixed = TRUE)
  expect_match(html, str_c("data-label-to-dark=\"", strings$mode_to_dark, "\""), fixed = TRUE)
  expect_match(html, "tt-icon-sun", fixed = TRUE)
  expect_match(html, "tt-icon-moon", fixed = TRUE)
  # decorative icons are hidden from screen readers; the button carries the label
  expect_equal(str_count(html, "aria-hidden=\"true\""), 2)
})

test_that("the stylesheet shows the sun in dark mode and the moon in light mode", {
  css <- paste(readLines(file.path(app_dir, "www", "styles.css")), collapse = "\n")

  expect_match(css, "\\.tt-icon-sun \\{\\s*display: none;")
  expect_match(css, ":root[data-bs-theme=dark] .tt-icon-sun {\n    display: block;", fixed = TRUE)
  expect_match(css, ":root[data-bs-theme=dark] .tt-icon-moon {\n    display: none;", fixed = TRUE)
})

test_that("the Spotify button uses dark text on its green, not white (contrast)", {
  css <- paste(readLines(file.path(app_dir, "www", "styles.css")), collapse = "\n")
  block <- function(selector) {
    str_match(css, str_c(str_replace_all(selector, "([.:])", "\\\\\\1"), " \\{([^}]*)\\}"))[, 2]
  }

  for (selector in c(".button-spotify", ".button-spotify:hover", ".button-spotify:focus")) {
    expect_match(block(selector), "color: #191414", fixed = TRUE, info = selector)
    expect_no_match(block(selector), "color: #FFFFFF", fixed = TRUE, info = selector)
  }
})

test_that("the session-ended dialog is in the page, hidden, with its text from strings.R", {
  html <- as.character(session_ended_dialog())

  expect_match(html, "id=\"session-ended\"", fixed = TRUE)
  expect_match(html, "role=\"alertdialog\"", fixed = TRUE)
  expect_match(html, "aria-labelledby=\"session-ended-title\"", fixed = TRUE)
  # hidden until session-ended.js shows it
  expect_match(html, "<div id=\"session-ended\"[^>]* hidden", perl = FALSE)
  expect_match(html, strings$session_ended_title, fixed = TRUE)
  expect_match(html, strings$session_ended_text, fixed = TRUE)
  expect_match(html, str_c(">", strings$session_ended_button, "<"), fixed = TRUE)

  rendered <- htmltools::renderTags(ui)
  expect_match(rendered$html, "id=\"session-ended\"", fixed = TRUE)
  expect_match(rendered$head, "<script src=\"session-ended.js\"></script>", fixed = TRUE)
})

test_that("session-ended.js shows the dialog on Shiny's disconnect event and never reloads by itself", {
  js <- paste(readLines(file.path(app_dir, "www", "session-ended.js")), collapse = "\n")

  # Shiny triggers this through jQuery; a native listener never receives it
  expect_match(js, "$(document).on(\"shiny:disconnected\"", fixed = TRUE)
  expect_match(js, "box.hidden = false", fixed = TRUE)
  # only the button reloads, and closing or reloading the page is not a lost session
  expect_equal(str_count(js, "location.reload\\(\\)"), 1)
  expect_match(js, "beforeunload", fixed = TRUE)
})

test_that("the dialog sits above Shiny's grey layer, and the hidden attribute still hides it", {
  css <- paste(readLines(file.path(app_dir, "www", "styles.css")), collapse = "\n")

  expect_match(css, "#session-ended[hidden] {\n    display: none;", fixed = TRUE)
  z <- as.integer(str_match(css, "#session-ended \\{[^}]*z-index: ([0-9]+)")[, 2])
  # Shiny's #shiny-disconnected-overlay uses z-index 99999
  expect_gt(z, 99999L)
})
