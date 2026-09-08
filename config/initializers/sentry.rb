Sentry.init do |config|
  config.dsn = ENV["SENTRY_DSN"]
  config.spotlight = Rails.env.development?
  config.breadcrumbs_logger = [:active_support_logger, :http_logger]
  # Off for production: orders carry real customer emails and shipping
  # addresses, and those should not leave the box for Sentry.
  config.send_default_pii = false
  # 100% tracing is too heavy for the Jetson (8GB shared with the GPU) and
  # burns the Sentry quota fast. 10% still surfaces slow checkouts.
  config.traces_sample_rate = ENV.fetch("SENTRY_TRACES_SAMPLE_RATE", "0.1").to_f
  # NB: `config.enable_logs` was removed in sentry-ruby 7.0 — structured
  # logging is on by default now (config.rails.structured_logging.enabled).
end
