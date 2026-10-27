# Google Merchant Center product data, one <item> per purchasable variant.
# Spec: https://support.google.com/merchants/answer/7052112
# The rows come from FeedsHelper#feed_items, shared with the Pinterest feed.
xml.instruct! :xml, version: "1.0"
xml.rss(version: "2.0", "xmlns:g" => "http://base.google.com/ns/1.0") do
  xml.channel do
    xml.title store_name
    xml.link root_url
    xml.description "Original psychedelic art on apparel, tapestries and more."

    feed_items(@products).each do |item|
      xml.item do
        xml.tag! "g:id", item[:id]
        xml.tag! "g:item_group_id", item[:group_id] if item[:group_id]
        xml.tag! "g:title", item[:title]
        xml.tag! "g:description", item[:description]
        xml.tag! "g:link", item[:link]
        xml.tag! "g:image_link", item[:image]
        item[:additional_images].each { |u| xml.tag! "g:additional_image_link", u }
        xml.tag! "g:availability", "in_stock"
        xml.tag! "g:price", item[:price]
        xml.tag! "g:sale_price", item[:sale_price] if item[:sale_price]
        xml.tag! "g:brand", store_name
        xml.tag! "g:condition", "new"
        xml.tag! "g:identifier_exists", "no" # print-on-demand: no GTIN / MPN
        xml.tag! "g:product_type", item[:product_type] if item[:product_type]
        if item[:apparel]
          xml.tag! "g:gender", "unisex"
          xml.tag! "g:age_group", "adult"
          xml.tag! "g:color", "Multicolor"
          xml.tag! "g:size", item[:size]
        end
      end
    end
  end
end
