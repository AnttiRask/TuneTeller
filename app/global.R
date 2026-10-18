# Load needed packages
library(bslib) # Bootstrap 5 theming and the dark mode switch
library(httr2) # HTTP requests made simple
library(purrr) # For keep(), map(), pluck() and the pipe
library(shiny) # Core Shiny package
library(shinycssloaders) # For adding CSS loaders/spinners
library(stringr) # For string manipulation

# Settings, text, prompts and helpers (www/ is also served as static files, so
# nothing secret may go in these: keys come from the environment)
source("www/variables.R")
source("www/strings.R")
source("www/prompt_versions.R")
source("www/functions.R")
source("www/api.R")
