# Pinterest Catalogs product data, one <item> per purchasable variant.
# Follows Pinterest's sample XML feed: title, description and link are plain RSS
# tags, the rest are in the g: namespace, and shipping is stated per item.
# Spec: https://help.pinterest.com/en/business/article/data-source-ingestion
# The rows come from FeedsHelper#feed_items, shared with the Google feed.
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
        xml.title item[:title]
        xml.description item[:description]
        xml.tag! "g:product_type", item[:product_type] if item[:product_type]
        xml.link item[:link]
        xml.tag! "g:image_link", item[:image]
        xml.tag! "g:condition", "new"
        xml.tag! "g:availability", "in stock"
        xml.tag! "g:price", item[:price]
        xml.sale_price item[:sale_price] if item[:sale_price]
        xml.tag! "g:brand", store_name
        xml.tag! "g:shipping" do
          xml.tag! "g:country", "US"
          xml.tag! "g:price", feed_shipping_price
        end
        xml.tag! "g:identifier_exists", "FALSE" # print-on-demand: no GTIN / MPN
        if item[:apparel]
          xml.tag! "g:gender", "unisex"
          xml.tag! "g:age_group", "adult"
          xml.tag! "g:color", "Multicolor"
          xml.tag! "g:size", item[:size]
        end
        item[:additional_images].each { |u| xml.tag! "g:additional_image_link", u }
      end
    end
  end
end
