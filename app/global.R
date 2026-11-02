# Load needed packages
library(bslib) # Bootstrap 5 theming and the dark mode switch
library(httr2) # HTTP requests made simple
library(purrr) # For keep(), map(), pluck() and the pipe
library(shiny) # Core Shiny package
library(shinycssloaders) # For adding CSS loaders/spinners
library(stringr) # For string manipulation

# Settings, text, prompts and helpers. They live in scripts/, not www/: everything
# in www/ is served to the browser, and these should not be public
source("scripts/variables.R")
source("scripts/strings.R")
source("scripts/prompt_versions.R")
source("scripts/functions.R")
source("scripts/api.R")
