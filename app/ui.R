# Shared footer component for cross-linking between apps
create_app_footer <- function(current_app = "") {
    tags$footer(
        class = "app-footer mt-5 py-4 border-top",
        div(
            class = "container text-center",
            div(
                class = "footer-apps mb-3",
                div(
                    class = "d-flex justify-content-center gap-3 flex-wrap",
                    footer_apps %>%
                        discard(~ .x$id == current_app) %>%
                        map(~ a(href = .x$url, .x$label))
                )
            ),
            div(
                class = "footer-credit",
                p(
                    strings$footer_created_by,
                    a(href = "https://www.linkedin.com/in/AnttiRask/", strings$footer_author),
                    " | ",
                    a(href = "https://youcanbeapirate.com", strings$footer_site)
                )
            )
        )
    )
}

ui <- page_fluid(
    theme = bs_theme(
        version = 5,
        primary = brand_colours$red,
        base_font = font_link(
            family = "Gotham",
            href = "https://fonts.cdnfonts.com/css/gotham-6"
        )
    ),

    # The tab title, favicon, colours of both modes and the cooldown script
    tags$head(
        tags$title(strings$title),
        tags$link(rel = "shortcut icon", type = "image/png", href = "favicon.png"),
        tags$style(HTML(theme_css())),
        tags$script(src = "cooldown.js")
    ),

    # Custom CSS styles
    includeCSS("www/styles.css"),

    # Main container
    div(
        class = "container",
        # The app title and the light/dark switch (dark is the default)
        div(
            class = "tt-header",
            h2(strings$title),
            div(class = "tt-mode-toggle", input_dark_mode(id = "dark_mode", mode = "dark"))
        ),
        sidebarLayout(
            sidebarPanel(
                # Text prompt input
                textAreaInput(
                    inputId     = "prompt",
                    label       = NULL,
                    height      = "200px",
                    placeholder = strings$prompt_placeholder,
                    resize      = "none"
                ),
                # Button to get the recommendation
                actionButton(
                    inputId = "go",
                    label   = strings$button_go,
                    width   = "100%",
                    class   = "button-recommendation"
                ),
                br(),
                br(),
                # Button to clear the text area
                actionButton(
                    inputId = "clearBtn",
                    label   = strings$button_clear,
                    class   = "button-clear"
                )
            ),
            mainPanel(
                # The artist card
                div(
                    class = "artist-card",
                    withSpinner(
                        uiOutput("artistInfo"),
                        type             = 3,
                        color            = brand_colours$red,
                        color.background = "var(--tt-card-bg)"
                    )
                ) # div
            ) # mainPanel
        ) # sidebarLayout
    ), # div

    # Add footer with cross-linking
    create_app_footer("tuneteller")
) # page_fluid
