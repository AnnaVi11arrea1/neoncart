Devise.setup do |config|
  config.mailer_sender = ENV.fetch("STORE_EMAIL", "shop@example.com")

  require "devise/orm/active_record"

  config.case_insensitive_keys = [:email]
  config.strip_whitespace_keys = [:email]
  config.skip_session_storage = [:http_auth]
  config.stretches = Rails.env.test? ? 1 : 12
  config.reconfirmable = true
  config.expire_all_remember_me_on_sign_out = true
  config.password_length = 8..128
  config.email_regexp = /\A[^@\s]+@[^@\s]+\z/
  config.reset_password_within = 6.hours
  config.sign_out_via = :delete
  config.responder.error_status = :unprocessable_entity
  config.responder.redirect_status = :see_other

  # ==> OmniAuth — "Continue with Google"
  # Create OAuth credentials at https://console.cloud.google.com/apis/credentials
  # (OAuth client ID → Web application). Authorized redirect URI must be:
  #   <your-host>/users/auth/google_oauth2/callback
  # Then set GOOGLE_CLIENT_ID / GOOGLE_CLIENT_SECRET in .env.
  config.omniauth :google_oauth2,
                  ENV["GOOGLE_CLIENT_ID"],
                  ENV["GOOGLE_CLIENT_SECRET"],
                  { scope: "email,profile", prompt: "select_account" }
end
