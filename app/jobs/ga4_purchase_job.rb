# Reports a paid web order to GA4 from the server — see Ga4MeasurementProtocol.
class Ga4PurchaseJob < ApplicationJob
  queue_as :default
  # GA4 accepts events up to 72 hours old, so retries well inside that still land.
  retry_on StandardError, wait: :polynomially_longer, attempts: 5

  def perform(order_id)
    order = Order.find(order_id)
    # Web checkouts only. Terminal (in-person) sales never touched the site,
    # and counting them would skew the website's conversion rate.
    return if order.stripe_session_id.blank?

    Ga4MeasurementProtocol.send_purchase(order)
  rescue Faraday::Error => e
    raise "GA4 Measurement Protocol request failed: #{e.message}"
  end
end
