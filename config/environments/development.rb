require "active_support/core_ext/integer/time"

Rails.application.configure do
  config.enable_reloading = true
  config.eager_load = false
  config.consider_all_requests_local = true
  config.server_timing = true

  config.action_controller.perform_caching = false
  config.cache_store = :memory_store

  config.active_storage.service = :local

  config.action_mailer.raise_delivery_errors = false
  config.action_mailer.perform_caching = false
  config.action_mailer.default_url_options = { host: "localhost", port: 3000 }
  config.action_mailer.delivery_method = :test

  config.active_support.deprecation = :log
  preview_mode = ENV.fetch("PREVIEW_MODE", "1") == "1"
  config.active_record.migration_error = preview_mode ? false : :page_load
  config.active_record.verbose_query_logs = true
  config.assets.quiet = true
end
