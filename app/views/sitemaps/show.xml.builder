xml.instruct! :xml, version: "1.0"
xml.urlset(xmlns: "http://www.sitemaps.org/schemas/sitemap/0.9") do
  # Static, crawlable pages. Cart/checkout/account pages are excluded on purpose.
  [[root_url, "daily", "1.0"],
   [products_url, "daily", "0.9"],
   [gallery_url, "weekly", "0.8"],
   [order_lookup_url, "monthly", "0.3"]].each do |loc, freq, priority|
    xml.url do
      xml.loc loc
      xml.changefreq freq
      xml.priority priority
    end
  end

  @products.each do |product|
    xml.url do
      xml.loc product_url(product)
      xml.lastmod product.updated_at.iso8601
      xml.changefreq "weekly"
      xml.priority "0.8"
    end
  end

  @paintings.each do |painting|
    xml.url do
      xml.loc painting_url(painting)
      xml.lastmod painting.updated_at.iso8601
      xml.changefreq "monthly"
      xml.priority "0.6"
    end
  end
end
