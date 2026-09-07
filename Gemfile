source "https://rubygems.org"

ruby "~> 3.2"

gem "rails", "~> 7.1.3"
gem "pg", "~> 1.5"
gem "puma", ">= 6.0"

# Assets & frontend (no Node required)
gem "sprockets-rails"
gem "importmap-rails"
gem "turbo-rails"
gem "stimulus-rails"

# Auth
gem "devise", "~> 4.9"
gem "omniauth-google-oauth2", "~> 1.1"   # "Continue with Google" for customers
gem "omniauth-rails_csrf_protection", "~> 1.0" # required CSRF guard for OmniAuth 2

# Payments
gem "stripe", "~> 12.0"

# Background jobs + cron (Postgres-backed, no Redis needed)
gem "good_job", "~> 3.29"

# HTTP client for dropshipper adapters
gem "faraday", "~> 2.9"

# Partner API CORS
gem "rack-cors"

# Pagination
gem "pagy", "~> 8.0"

# Image variants for uploaded product photos (requires libvips: apt install libvips)
gem "image_processing", "~> 1.12"

gem "bootsnap", require: false

group :development, :test do
  gem "dotenv-rails"
  gem "debug", platforms: %i[mri]
end

group :development do
  gem "web-console"
end
