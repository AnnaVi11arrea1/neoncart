# Partner sites allowed to call the JSON API from the browser.
# Comma-separated in ENV, e.g.
# ALLOWED_ORIGINS=https://festconnect.trickell.digital,https://govend.ing
Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins(*ENV.fetch("ALLOWED_ORIGINS", "").split(",").map(&:strip).reject(&:empty?))
    resource "/api/*",
             headers: :any,
             methods: %i[get post options],
             expose: %w[X-Request-Id]
  end
end
