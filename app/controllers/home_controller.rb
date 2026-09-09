class HomeController < ApplicationController
  def index
    if preview_mode?
      @featured = preview_products.select(&:featured).first(4)
      @latest = preview_products.first(8)
      @categories = preview_categories
      return
    end

    @featured = Product.storefront.where(featured: true).includes(:product_images).limit(4)
    @latest = Product.storefront.includes(:product_images).limit(8)
    @categories = Category.joins(:products).where(products: { status: "active" }).distinct
  rescue ActiveRecord::ConnectionNotEstablished, PG::ConnectionBad
    @featured = preview_products.select(&:featured).first(4)
    @latest = preview_products.first(8)
    @categories = preview_categories
    flash.now[:alert] = "Database unavailable. Showing preview data."
  end

  private

  CategoryPreview = Struct.new(:name, :slug)
  ProductPreview = Struct.new(
    :id,
    :slug,
    :title,
    :price_cents,
    :compare_at_price_cents,
    :description,
    :tags,
    :category,
    :featured,
    :all_image_urls,
    keyword_init: true
  ) do
    def primary_image_url
      all_image_urls.first
    end
  end

  def preview_categories
    [
      CategoryPreview.new("Pants", "pants"),
      CategoryPreview.new("Shirts", "shirts"),
      CategoryPreview.new("Hoodies", "hoodies"),
      CategoryPreview.new("Hats", "hats"),
      CategoryPreview.new("Tech", "tech"),
      CategoryPreview.new("Blankets", "blankets"),
      CategoryPreview.new("Tapestries", "tapestries")
    ]
  end

  def preview_products
    @preview_products ||= begin
      categories = preview_categories
      [
        ProductPreview.new(
          id: 1,
          slug: "reactor-ink-tee",
          title: "Reactor Ink Tee",
          price_cents: 3200,
          compare_at_price_cents: 3900,
          description: "Soft cotton tee with UV-reactive cyan print.",
          tags: ["uv", "tee"],
          category: categories[1],
          featured: true,
          all_image_urls: []
        ),
        ProductPreview.new(
          id: 2,
          slug: "night-bloom-poster",
          title: "Night Bloom Poster",
          price_cents: 2400,
          compare_at_price_cents: nil,
          description: "Fluorescent gallery print with deep blacklight contrast.",
          tags: ["poster", "wall-art"],
          category: categories[6],
          featured: true,
          all_image_urls: []
        ),
        ProductPreview.new(
          id: 3,
          slug: "afterglow-cap",
          title: "Afterglow Cap",
          price_cents: 2800,
          compare_at_price_cents: nil,
          description: "Structured cap with stitched phosphor emblem.",
          tags: ["cap", "streetwear"],
          category: categories[3],
          featured: false,
          all_image_urls: []
        )
      ]
    end
  end
end
