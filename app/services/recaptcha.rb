# Google reCAPTCHA v2, the "I'm not a robot" checkbox, on forms anyone can
# submit without signing in (support tickets).
#
# Needs RECAPTCHA_SITE_KEY and RECAPTCHA_SECRET_KEY (google.com/recaptcha/admin
# → create a v2 "I'm not a robot" key for www.everfluorescent.com). In
# production a missing key fails closed, so a forgotten key blocks the form
# rather than opening it to spam. In development and test it's skipped.
module Recaptcha
  VERIFY_URL = "https://www.google.com/recaptcha/api/siteverify".freeze

  def self.site_key = ENV["RECAPTCHA_SITE_KEY"].presence

  def self.configured? = site_key.present? && ENV["RECAPTCHA_SECRET_KEY"].present?

  def self.required? = configured? || Rails.env.production?

  # `token` is the g-recaptcha-response field the widget adds to the form.
  def self.verified?(token, remote_ip: nil)
    return true unless required?
    return false if token.blank? || !configured?

    resp = Faraday.post(VERIFY_URL) do |req|
      req.options.timeout = 10
      req.body = URI.encode_www_form(secret: ENV["RECAPTCHA_SECRET_KEY"], response: token, remoteip: remote_ip)
    end
    resp.success? && JSON.parse(resp.body)["success"] == true
  rescue Faraday::Error, JSON::ParserError => e
    Rails.logger.warn("reCAPTCHA verify failed: #{e.class}: #{e.message}")
    false
  end
end
