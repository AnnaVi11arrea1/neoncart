require_relative "boot"

require "rails"
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_text/engine"
require "action_view/railtie"
require "rails/test_unit/railtie"

Bundler.require(*Rails.groups)

module Neoncart
  class Application < Rails::Application
    config.load_defaults 7.1

    config.autoload_lib(ignore: %w[assets tasks])

    # All secrets come from ENV — no encrypted credentials required.
    config.secret_key_base = ENV["SECRET_KEY_BASE"] if ENV["SECRET_KEY_BASE"].present?

    config.active_job.queue_adapter = :good_job

    config.time_zone = ENV.fetch("TIME_ZONE", "America/Chicago")

    # Store-wide settings, overridable via ENV
    config.x.store_name  = ENV.fetch("STORE_NAME", "Ever Fluorescent")
    config.x.store_email = ENV.fetch("STORE_EMAIL", "shop@example.com")
    config.x.store_url   = ENV.fetch("APP_HOST", "http://localhost:3000")

    # The publisher that drafts and sends social posts. It holds the CMS
    # credential; this app holds none, so the admin approve queue goes through
    # it. Both must be set before the queue page can show anything.
    config.x.post_worker_url   = ENV["POST_WORKER_URL"]
    config.x.post_worker_token = ENV["POST_WORKER_TOKEN"]

    # Where the CMS Studio is reachable, for the link out to the pixel-accurate
    # preview. Defaults to the local Studio, which is how it runs today.
    config.x.studio_url = ENV.fetch("CMS_STUDIO_URL", "http://localhost:3333")
  end
end
