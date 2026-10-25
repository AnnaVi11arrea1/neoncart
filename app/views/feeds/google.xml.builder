# Google Merchant Center product data, one <item> per purchasable variant.
# Spec: https://support.google.com/merchants/answer/7052112
#
# Google requires gender, age group, colour and size on apparel sold in the
# US, so items in the clothing categories carry them. The prints are
# all-over, hence "Multicolor".
apparel_categories = %w[pants shirts hoodies hats]

feed_price = ->(cents, currency) { format("%.2f %s", cents.to_i / 100.0, currency.to_s.upcase) }

xml.instruct! :xml, version: "1.0"
xml.rss(version: "2.0", "xmlns:g" => "http://base.google.com/ns/1.0") do
  xml.channel do
    xml.title store_name
    xml.link root_url
    xml.description "Original psychedelic art on apparel, tapestries and more."

    @products.each do |product|
      variants = product.variants.select(&:available)
      # Every variant sold out: leave it out rather than advertise what can't be bought.
      next if variants.empty? && product.variants.any?

      description = product.description.is_a?(ActionText::RichText) ? product.description.to_plain_text : product.description.to_s
      description = description.squish.presence || "#{product.title}, original artwork by Anna Villarreal, printed to order."
      images = product.all_image_urls.map { |u| absolute_image_url(u) }
      apparel = apparel_categories.include?(product.category&.slug)
      # Same id GA4 gets for this product (AnalyticsHelper#ga_item), so Merchant
      # Center, Google Ads and GA4 all join up.
      group_id = product.external_id.presence || product.slug

      (variants.presence || [nil]).each do |variant|
        cents = variant ? variant.price_cents_or_default : product.price_cents
        xml.item do
          xml.tag! "g:id", variant ? (variant.sku.presence || "#{product.slug}-#{variant.id}") : group_id
          xml.tag! "g:item_group_id", group_id if variant && variants.size > 1
          xml.tag! "g:title", [product.title, (variant.label if variant && variants.size > 1)].compact.join(" - ").first(150)
          xml.tag! "g:description", description.first(5000)
          xml.tag! "g:link", product_url(product)
          xml.tag! "g:image_link", images.first
          images.drop(1).first(10).each { |u| xml.tag! "g:additional_image_link", u }
          xml.tag! "g:availability", "in_stock"
          if product.compare_at_price_cents.to_i > cents
            xml.tag! "g:price", feed_price.call(product.compare_at_price_cents, product.currency)
            xml.tag! "g:sale_price", feed_price.call(cents, product.currency)
          else
            xml.tag! "g:price", feed_price.call(cents, product.currency)
          end
          xml.tag! "g:brand", store_name
          xml.tag! "g:condition", "new"
          xml.tag! "g:identifier_exists", "no" # print-on-demand: no GTIN / MPN
          xml.tag! "g:product_type", product.category.name if product.category
          if apparel
            xml.tag! "g:gender", "unisex"
            xml.tag! "g:age_group", "adult"
            xml.tag! "g:color", "Multicolor"
            xml.tag! "g:size", variant ? variant.label : "One Size"
          end
        end
      end
    end
  end
end
