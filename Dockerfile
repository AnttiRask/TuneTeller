# Use rocker/shiny as base image
FROM rocker/shiny:4.5.0

# Install system dependencies
RUN apt-get update && apt-get install -y \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    && rm -rf /var/lib/apt/lists/*

# Create app directory
WORKDIR /srv/shiny-server/app

# Copy renv infrastructure first for caching
COPY renv.lock renv.lock
COPY .Rprofile .Rprofile
COPY renv/activate.R renv/activate.R
COPY renv/settings.json renv/settings.json

# Install renv and restore packages from lock file
RUN R -e "install.packages('renv', repos = 'https://cloud.r-project.org/')" && \
    R -e "renv::restore(prompt = FALSE)"

# Copy application files
COPY . .

# Set permissions
RUN chown -R shiny:shiny /srv/shiny-server/app

# Expose port
EXPOSE 8080

# Set environment variables
ENV PORT=8080
ENV SHINY_ENV=production

# Run the application
CMD ["R", "-e", "source('app/run.R')"]
