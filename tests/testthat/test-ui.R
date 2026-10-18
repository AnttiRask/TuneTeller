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
