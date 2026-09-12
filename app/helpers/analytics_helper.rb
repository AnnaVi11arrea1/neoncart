# GA4 ecommerce events.
#
# The layout loads gtag.js and calls gtag('config', ...) itself, so events are
# sent with gtag() rather than a dataLayer push — a push only reaches GA4 if a
# matching tag exists in the GTM container, which nothing in this repo can
# guarantee. gtag() queues into dataLayer, so firing before the async script
# has finished loading is safe.
#
# Nothing is emitted in preview mode: the preview structs aren't real products,
# and dev traffic has no business in the reports.
module AnalyticsHelper
  # Renders <script>gtag('event', name, params)</script>.
  # `once_key` guards a refresh from re-sending the event (purchase).
  def ga_event(name, params = {}, once_key: nil)
    return if preview_mode?

    call = "gtag('event',#{ga_json(name.to_s)},#{ga_json(params.compact)});"
    tag.script(raw(once_key ? ga_once(once_key, call) : call))
  end

  # One GA4 `items` entry for a catalogue product.
  def ga_item(product, variant: nil, quantity: 1, price_cents: nil)
    cents = price_cents || product.display_price_cents(variant)
    {
      item_id: product.external_id.presence || product.slug,
      item_name: product.title,
      item_category: product.category&.name,
      item_variant: variant&.label,
      price: ga_price(cents),
      quantity: quantity
    }.compact
  end

  # One GA4 `items` entry for a line on a placed order.
  #
  # item_id and item_name have to match what ga_item sent for the same product
  # at view_item/add_to_cart time, or GA4 treats them as different items and
  # the funnel never joins up. So this is product-level (external_id + product
  # title) with the size in item_variant — NOT the order line's SKU and
  # "Title — XXL" display string, which are per-variant. The order line is only
  # the fallback, for when the product row is gone.
  def ga_order_item(order_item)
    product = order_item.product
    {
      item_id: product&.external_id.presence || product&.slug || order_item.sku,
      item_name: product&.title.presence || order_item.title,
      item_category: product&.category&.name,
      item_variant: order_item.variant&.label,
      price: ga_price(order_item.unit_price_cents),
      quantity: order_item.quantity
    }.compact
  end

  def ga_price(cents) = (cents.to_i / 100.0).round(2)

  # Shared payload for view_cart and begin_checkout — the same basket, counted
  # once on view and once on intent to pay.
  def ga_cart_payload(cart, items)
    {
      currency: "USD",
      value: ga_price(cart.subtotal_cents),
      items: items.map { |i| ga_item(i.product, variant: i.variant, quantity: i.quantity, price_cents: i.unit_price_cents) }
    }
  end

  # Rails escapes <, > and & to \uXXXX in JSON, so a product title containing
  # "</script>" can't break out of the tag.
  def ga_json(value) = ActiveSupport::JSON.encode(value)

  private

  def ga_once(key, call)
    <<~JS
      try {
        var k = #{ga_json("ga4:#{key}")};
        if (!sessionStorage.getItem(k)) { sessionStorage.setItem(k, '1'); #{call} }
      } catch (e) { #{call} }
    JS
  end
end
