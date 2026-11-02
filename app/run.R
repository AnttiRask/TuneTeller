library(shiny)

# Run from the app directory so ui.R / global.R find their www/ and scripts/ files
source("app/scripts/security.R")
source("app/scripts/health.R")
setwd("app")

port <- as.integer(Sys.getenv("PORT", "8080"))
# /health first, then the security headers around everything the handler answers
app <- with_security_headers(with_health_check(shinyAppDir(".")))
runApp(app, host = "0.0.0.0", port = port)
