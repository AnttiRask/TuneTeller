library(rsconnect)

source("app/www/secret.R")

setAccountInfo(
  name = SHINY_APPS_NAME,
  token = SHINY_APPS_TOKEN,
  secret = SHINY_APPS_SECRET
)

deployApp(
  appDir = "app/",
  appName = "TuneTeller",
  account = "youcanbeapirate",
  forceUpdate = TRUE
)
