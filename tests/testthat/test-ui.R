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

test_that("the page starts in dark mode with a light/dark switch and the colours of both modes", {
  rendered <- htmltools::renderTags(ui)

  expect_match(rendered$html, "<bslib-input-dark-mode", fixed = TRUE)
  expect_match(rendered$html, "mode=\"dark\"", fixed = TRUE)
  # The head holds the colours of both modes and the cooldown script
  expect_match(rendered$head, ":root[data-bs-theme=dark]{", fixed = TRUE)
  expect_match(rendered$head, "<script src=\"cooldown.js\"></script>", fixed = TRUE)
  expect_match(rendered$head, "<title>TuneTeller</title>", fixed = TRUE)
})
