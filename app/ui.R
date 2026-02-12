# Load needed packages
library(shiny)              # Core Shiny package
library(bslib)              # For modern Bootstrap 5 theming
library(shinyBS)            # For Bootstrap components in Shiny
library(shinycssloaders)    # For adding CSS loaders/spinners

# Shared footer component for cross-linking between apps
create_app_footer <- function(current_app = "") {
    tags$footer(
        class = "app-footer mt-5 py-4 border-top",
        div(
            class = "container text-center",
            div(
                class = "footer-apps mb-3",
                p(class = "text-muted mb-2", "youcanbeapiRate apps:"),
                div(
                    class = "d-flex justify-content-center gap-3 flex-wrap",
                    if(current_app != "trackteller")
                        a(href = "https://trackteller.youcanbeapirate.com", "TrackTeller"),
                    if(current_app != "tuneteller")
                        a(href = "https://tuneteller.youcanbeapirate.com", "TuneTeller"),
                    if(current_app != "bibliostatus")
                        a(href = "https://bibliostatus.youcanbeapirate.com", "BiblioStatus"),
                    if(current_app != "gallery")
                        a(href = "https://galleryoftheday.youcanbeapirate.com", "Gallery of the Day")
                )
            ),
            div(
                class = "footer-credit",
                p(
                    "Created by ",
                    a(href = "https://anttirask.github.io", "Antti Rask"),
                    " | ",
                    a(href = "https://youcanbeapirate.com", "youcanbeapirate.com")
                )
            )
        )
    )
}

ui <- page_fluid(
    theme = bs_theme(
        version = 5,
        bg = "#191414",
        fg = "#FFFFFF",
        primary = "#C1272D",
        base_font = font_link(
            family = "Gotham",
            href = "https://fonts.cdnfonts.com/css/gotham-6"
        )
    ),

    # The tab title and favicon
    tags$head(
        tags$title("TuneTeller"),
        tags$link(rel = "shortcut icon", type = "image/png", href = "favicon.png")
    ),
    
    # Custom CSS styles
    includeCSS("www/styles.css"),
    
    # Main container
    div(
        class = "container",
        # The app title
        titlePanel(title = "TuneTeller"),
        sidebarLayout(
            sidebarPanel(
                # Text prompt input
                textAreaInput(
                    inputId     = "prompt",
                    label       = NULL,
                    height      = "200px",
                    placeholder = "Describe to me, in 190 characters or less, what kind of music you would like to hear. \n\nI will then recommend you an artist to listen to!",
                    resize      = "none"
                ),
                # Button to get the recommendation
                actionButton(
                    inputId = "go",
                    label   = "Get Recommendation",
                    width   = "100%",
                    class   = "button-recommendation"
                ),
                br(),
                br(),
                # Button to clear the text area
                actionButton(
                    inputId = "clearBtn",
                    label   = "Clear Text",
                    class   = "button-clear"
                ),
                br(),
                br(),
                # Bootstrap alert placeholder
                bsAlert("alert_anchor")
            ),
            mainPanel(
                # The artist card
                div(
                    class = "artist-card",
                    withSpinner(
                        uiOutput("artistInfo"),
                        type             = 3,
                        color            = "#C1272D",
                        color.background = "#191919"
                    ),
                    br(),
                    # Output for the Spotify button (dynamically rendered)
                    uiOutput("spotifyButton")
                ) # div
            ) # mainPanel
        ) # sidebarLayout
    ), # div

    # Add footer with cross-linking
    create_app_footer("tuneteller")
) # page_fluid