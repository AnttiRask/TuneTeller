library(shiny)

# Run the application
port <- as.integer(Sys.getenv("PORT", "8080"))
runApp("app/", host = "0.0.0.0", port = port)