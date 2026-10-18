## Security headers for the HTML page.
##
## Shiny has no built-in hook for response headers (the `shiny.http.response.filter`
## option does nothing), so run.R wraps the app's page handler instead. Static
## assets are served by other handlers and don't need these headers.

# Hosts the page legitimately loads things from. Artist images come from
# Spotify's image CDNs (i.scdn.co today; the wildcards cover the other
# scdn.co / spotifycdn.com hosts it uses, so a picture can't be blocked).
image_hosts <- c("https://*.scdn.co", "https://*.spotifycdn.com")
font_host <- "https://fonts.cdnfonts.com"

# The policy, enforced. Shiny and bslib use inline scripts and styles, hence
# 'unsafe-inline'; wss: is the Shiny websocket. 'unsafe-eval' is not allowed:
# nothing in the app needs it (checked in the browser in both colour modes).
# frame-ancestors is the modern clickjacking protection (X-Frame-Options below
# is the fallback).
csp <- paste(
    "default-src 'self'",
    "script-src 'self' 'unsafe-inline'",
    paste("style-src 'self' 'unsafe-inline'", font_host),
    paste("font-src 'self' data:", font_host),
    paste("img-src 'self' data: blob:", paste(image_hosts, collapse = " ")),
    "connect-src 'self' wss:",
    "frame-ancestors 'none'",
    "base-uri 'self'",
    "object-src 'none'",
    "form-action 'self'",
    sep = "; "
)

security_headers <- function() {
    list(
        "Content-Security-Policy"   = csp,
        "X-Frame-Options"           = "DENY",
        "X-Content-Type-Options"    = "nosniff",
        "Referrer-Policy"           = "strict-origin-when-cross-origin",
        # The app needs no device features
        "Permissions-Policy"        = "geolocation=(), camera=(), microphone=(), payment=(), usb=()",
        # Cloud Run only serves HTTPS; one year, no subdomains, no preload
        "Strict-Transport-Security" = "max-age=31536000"
    )
}

add_headers <- function(response, headers) {
    if (inherits(response, "httpResponse")) {
        for (name in names(headers)) {
            response$headers[[name]] <- headers[[name]]
        }
    }
    response
}

# Wrap a Shiny app object so every page response carries the headers. Handles
# the three things a handler can return: NULL, a response, or a promise.
with_security_headers <- function(app, headers = security_headers()) {
    original <- app$httpHandler
    app$httpHandler <- function(req) {
        res <- original(req)
        if (promises::is.promising(res)) {
            promises::then(res, function(value) add_headers(value, headers))
        } else {
            add_headers(res, headers)
        }
    }
    app
}
