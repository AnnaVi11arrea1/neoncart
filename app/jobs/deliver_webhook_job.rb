class DeliverWebhookJob < ApplicationJob
  queue_as :default
  retry_on StandardError, wait: :polynomially_longer, attempts: 6

  def perform(delivery_id)
    delivery = WebhookDelivery.find(delivery_id)
    endpoint = delivery.webhook_endpoint
    return unless endpoint.active?

    body = {
      event: delivery.event,
      created_at: delivery.created_at.iso8601,
      data: delivery.payload
    }.to_json

    signature = OpenSSL::HMAC.hexdigest("SHA256", endpoint.secret, body)

    resp = Faraday.post(endpoint.url) do |req|
      req.headers["Content-Type"] = "application/json"
      req.headers["X-Neoncart-Event"] = delivery.event
      req.headers["X-Neoncart-Signature"] = "sha256=#{signature}"
      req.options.timeout = 15
      req.body = body
    end

    delivery.update!(response_code: resp.status, attempts: delivery.attempts + 1,
                     delivered_at: resp.success? ? Time.current : nil,
                     last_error: resp.success? ? nil : resp.body.to_s.first(300))
    raise "Webhook to #{endpoint.url} got HTTP #{resp.status}" unless resp.success?
  rescue Faraday::Error => e
    delivery&.update(attempts: delivery.attempts + 1, last_error: e.message.first(300))
    raise
  end
end
