module Webhooks
  # Fans an event out to every registered partner endpoint (e.g.
  # festconnect.trickell.digital, govend.ing). Payloads are signed with
  # HMAC-SHA256 so partners can verify authenticity.
  module Dispatcher
    def self.publish(event, payload)
      WebhookEndpoint.for_event(event).find_each do |endpoint|
        delivery = endpoint.deliveries.create!(event:, payload:)
        DeliverWebhookJob.perform_later(delivery.id)
      end
    rescue ActiveRecord::StatementInvalid, ActiveRecord::RecordInvalid => e
      Rails.logger.error("Webhook publish failed: #{e.message}")
    end
  end
end
