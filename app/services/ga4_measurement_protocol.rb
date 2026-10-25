# Sends GA4 events from the server, via the Measurement Protocol.
#
# The browser fires `purchase` on the confirmation page, but a buyer who
# closes the tab after paying, pays by a method that settles late, or runs
# an ad blocker never sends it. The Stripe webhook always arrives, so the
# purchase is sent from here too. Both carry the order number as
# transaction_id, which is what GA4 uses to drop the duplicate.
#
# Needs GA4_API_SECRET (GA4 → Admin → Data streams → web stream →
# Measurement Protocol API secrets). Without it nothing is sent.
module Ga4MeasurementProtocol
  ENDPOINT = "https://www.google-analytics.com/mp/collect".freeze
  DEFAULT_MEASUREMENT_ID = "G-HKQBLH064J".freeze # the tag in layouts/application

  extend AnalyticsHelper

  def self.measurement_id = ENV.fetch("GA4_MEASUREMENT_ID", DEFAULT_MEASUREMENT_ID)

  def self.enabled? = ENV["GA4_API_SECRET"].present?

  # The `_ga` cookie is "GA1.1.<random>.<timestamp>"; GA4's client_id is the
  # last two parts.
  def self.client_id_from(cookies)
    parts = cookies["_ga"].to_s.split(".")
    parts.last(2).join(".") if parts.size >= 4
  end

  # The `_ga_<stream>` cookie holds the current session id, in either the
  # older "GS1.1.<session_id>.…" or the newer "GS2.1.s<session_id>$o…" form.
  def self.session_id_from(cookies)
    raw = cookies["_ga_#{measurement_id.delete_prefix('G-')}"].to_s.split(".")[2].to_s
    id = raw.split("$").first.to_s.delete_prefix("s")
    id if id.match?(/\A\d+\z/)
  end

  def self.purchase_payload(order)
    params = {
      transaction_id: order.number,
      currency: order.currency.to_s.upcase,
      value: ga_price(order.total_cents),
      tax: ga_price(order.tax_cents),
      shipping: ga_price(order.shipping_cents),
      items: order.order_items.includes(:variant, product: :category).map { |oi| ga_order_item(oi) },
      session_id: order.ga_session_id,
      # GA4 only counts an event towards a session when it has some engagement time.
      engagement_time_msec: 1
    }.compact

    {
      # No cookie (blocked, or a checkout started before this shipped): the sale
      # still counts, just without the visit that led to it.
      client_id: order.ga_client_id.presence || "order.#{order.number}",
      timestamp_micros: ((order.placed_at || Time.current).to_f * 1_000_000).to_i,
      events: [{ name: "purchase", params: params }]
    }
  end

  def self.send_purchase(order)
    return unless enabled?

    resp = Faraday.post(ENDPOINT) do |req|
      req.params = { measurement_id: measurement_id, api_secret: ENV["GA4_API_SECRET"] }
      req.headers["Content-Type"] = "application/json"
      req.options.timeout = 15
      req.body = purchase_payload(order).to_json
    end

    raise "GA4 Measurement Protocol got HTTP #{resp.status}" unless resp.success?
  end
end
