# Posts a message to the server-wide security-alerts Discord webhook —
# deliberately separate from DISCORD_WEBHOOK_URL (order notifications).
# The webhook URL lives outside any single app's .env, at a shared path on
# the box, since this alert covers every app running here, not just neoncart.
class SecurityAlertJob < ApplicationJob
  queue_as :default
  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  WEBHOOK_ENV_FILE = "/home/anna/.config/security-alerts.env"

  def perform(message)
    webhook_url = shared_webhook_url
    return if webhook_url.blank?

    resp = Faraday.post(webhook_url) do |req|
      req.headers["Content-Type"] = "application/json"
      req.options.timeout = 15
      req.body = { content: message }.to_json
    end

    raise "Security alert webhook got HTTP #{resp.status}" unless resp.success?
  rescue Faraday::Error => e
    raise "Security alert webhook request failed: #{e.message}"
  end

  private

  def shared_webhook_url
    return nil unless File.readable?(WEBHOOK_ENV_FILE)

    line = File.readlines(WEBHOOK_ENV_FILE).find { |l| l.start_with?("SECURITY_ALERTS_WEBHOOK_URL=") }
    line&.split("=", 2)&.last&.strip
  end
end
