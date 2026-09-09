# Posts a "new order" message to a Discord channel via an incoming webhook.
# Set DISCORD_WEBHOOK_URL (Discord: channel settings -> Integrations ->
# Webhooks -> New Webhook -> Copy Webhook URL) to enable this. Silently
# skips when unset so stores that don't use Discord pay no cost.
class DiscordOrderNotificationJob < ApplicationJob
  include ActionView::Helpers::NumberHelper

  queue_as :default
  retry_on StandardError, wait: :polynomially_longer, attempts: 5

  def perform(order_id)
    webhook_url = ENV["DISCORD_WEBHOOK_URL"]
    return if webhook_url.blank?

    order = Order.find(order_id)

    resp = Faraday.post(webhook_url) do |req|
      req.headers["Content-Type"] = "application/json"
      req.options.timeout = 15
      req.body = { embeds: [embed_for(order)] }.to_json
    end

    raise "Discord webhook got HTTP #{resp.status}: #{resp.body.to_s.first(300)}" unless resp.success?
  rescue Faraday::Error => e
    raise "Discord webhook request failed: #{e.message}"
  end

  private

  def embed_for(order)
    items = order.order_items.map { |i| "#{i.quantity}× #{i.title}" }.join("\n").presence || "—"

    {
      title: "📦 New order #{order.number}",
      url: order_admin_url(order),
      color: 0xB6FF3C,
      fields: [
        { name: "Total", value: format_money(order.total_cents, order.currency), inline: true },
        { name: "Customer", value: order.customer_name.to_s, inline: true },
        { name: "Email", value: order.customer_email.to_s.presence || "—", inline: true },
        { name: "Items", value: items }
      ],
      timestamp: (order.placed_at || Time.current).iso8601
    }
  end

  def format_money(cents, currency)
    number_to_currency(cents.to_i / 100.0, unit: currency.to_s.downcase == "usd" ? "$" : "#{currency.to_s.upcase} ")
  end

  def order_admin_url(order)
    host = URI(ENV.fetch("APP_HOST", "http://localhost:3000")).host
    protocol = ENV.fetch("APP_HOST", "http://localhost:3000").start_with?("https") ? "https" : "http"
    Rails.application.routes.url_helpers.admin_order_url(order, host:, protocol:)
  end
end
