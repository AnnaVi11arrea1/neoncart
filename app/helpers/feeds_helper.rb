# The rows behind both product feeds, so Google and Pinterest always list the
# same items at the same prices. Each builder only decides how to spell them.
module FeedsHelper
  # Google requires gender, age group, colour and size on apparel sold in the
  # US, so items in the clothing categories carry them. The prints are
  # all-over, hence "Multicolor".
  APPAREL_CATEGORIES = %w[pants shirts hoodies hats].freeze

  # One hash per purchasable variant (or per product, when it has none).
  def feed_items(products)
    products.flat_map do |product|
      variants = product.variants.select(&:available)
      # Every variant sold out: leave it out rather than advertise what can't be bought.
      next [] if variants.empty? && product.variants.any?

      description = product.description.is_a?(ActionText::RichText) ? product.description.to_plain_text : product.description.to_s
      description = description.squish.presence || "#{product.title}, original artwork by Anna Villarreal, printed to order."
      images = product.all_image_urls.map { |u| absolute_image_url(u) }
      apparel = APPAREL_CATEGORIES.include?(product.category&.slug)
      # Same id GA4 gets for this product (AnalyticsHelper#ga_item), so Merchant
      # Center, Google Ads and GA4 all join up.
      group_id = product.external_id.presence || product.slug

      (variants.presence || [nil]).map do |variant|
        cents = variant ? variant.price_cents_or_default : product.price_cents
        on_sale = product.compare_at_price_cents.to_i > cents
        {
          id: variant ? (variant.sku.presence || "#{product.slug}-#{variant.id}") : group_id,
          group_id: (group_id if variant && variants.size > 1),
          title: [product.title, (variant.label if variant && variants.size > 1)].compact.join(" - ").first(150),
          description: description.first(5000),
          link: product_url(product),
          image: images.first,
          additional_images: images.drop(1).first(10),
          price: feed_price(on_sale ? product.compare_at_price_cents : cents, product.currency),
          sale_price: (feed_price(cents, product.currency) if on_sale),
          product_type: product.category&.name,
          apparel: apparel,
          size: variant ? variant.label : "One Size"
        }
      end
    end
  end

  def feed_price(cents, currency) = format("%.2f %s", cents.to_i / 100.0, currency.to_s.upcase)

  # The flat rate Stripe Checkout charges (Payments::StripeCheckout.shipping_options).
  def feed_shipping_price = feed_price(ENV.fetch("FLAT_SHIPPING_CENTS", "599"), "USD")
end
