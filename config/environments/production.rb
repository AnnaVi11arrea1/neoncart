require "active_support/core_ext/integer/time"

Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = true
  config.consider_all_requests_local = false

  config.public_file_server.enabled = true
  config.assets.compile = false

  config.active_storage.service = :local

  # SSL is terminated at Nginx; Rails trusts the proxy headers.
  config.assume_ssl = true
  config.force_ssl = ENV.fetch("FORCE_SSL", "true") == "true"

  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")
  config.log_tags = [:request_id]
  config.logger = ActiveSupport::TaggedLogging.new(Logger.new($stdout)) if ENV["RAILS_LOG_TO_STDOUT"].present?

  config.action_controller.perform_caching = true

  config.action_mailer.perform_caching = false
  config.action_mailer.default_url_options = { host: URI(ENV.fetch("APP_HOST", "http://localhost:3000")).host, protocol: "https" }
  config.action_mailer.delivery_method = :smtp
  config.action_mailer.smtp_settings = {
    address: ENV["SMTP_ADDRESS"],
    port: ENV.fetch("SMTP_PORT", 587).to_i,
    user_name: ENV["SMTP_USERNAME"],
    password: ENV["SMTP_PASSWORD"],
    authentication: :plain,
    enable_starttls_auto: true
  }
  config.action_mailer.raise_delivery_errors = false

  config.i18n.fallbacks = true
  config.active_support.report_deprecations = false
  config.active_record.dump_schema_after_migration = false
end
