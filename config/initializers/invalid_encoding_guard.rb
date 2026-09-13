# Explicit require rather than relying on autoloading being active yet at
# this point in boot — sidesteps Zeitwerk timing entirely.
require Rails.root.join("app/middleware/invalid_encoding_guard")
Rails.application.config.middleware.insert_before Rack::Sendfile, InvalidEncodingGuard
