class ProductsController < ApplicationController
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

  def index
    if preview_mode?
      @categories = preview_categories
      @products = preview_products

      if params[:category].present?
        @products = @products.select { |p| p.category&.slug == params[:category] }
      end

      if params[:q].present?
        needle = params[:q].downcase
        @products = @products.select { |p| p.title.downcase.include?(needle) }
      end

      @pagy = nil
      return
    end

    scope = Product.storefront.includes(:product_images, :category)
    scope = scope.where(categories: { slug: params[:category] }).references(:category) if params[:category].present?
    scope = scope.search(params[:q])
    @pagy, @products = pagy(scope)
    @categories = Category.all
  rescue ActiveRecord::ConnectionNotEstablished, PG::ConnectionBad
    @categories = preview_categories
    @products = preview_products
    @pagy = nil
    flash.now[:alert] = "Database unavailable. Showing preview data."
  end

  def show
    if preview_mode?
      @product = preview_products.find { |p| p.slug == params[:slug] }
      raise ActiveRecord::RecordNotFound unless @product

      @variants = []
      @sold_out = false
      @related = preview_products.reject { |p| p.slug == @product.slug }.first(4)
      return
    end

    @product = Product.active.find_by(slug: params[:slug])
    if @product.nil?
      redirect_target = Product.active.find_by_old_slug(params[:slug])
      return redirect_to product_path(redirect_target), status: :moved_permanently if redirect_target

      raise ActiveRecord::RecordNotFound
    end
    @variants = @product.variants.available
    # A product whose variants all came back unavailable from the supplier has
    # nothing to pick from — sell it and the order arrives with no size.
    @sold_out = @variants.empty? && @product.variants.exists?
    @related = Product.storefront.where(category_id: @product.category_id).where.not(id: @product.id).limit(4)
  rescue ActiveRecord::ConnectionNotEstablished, PG::ConnectionBad
    @product = preview_products.find { |p| p.slug == params[:slug] }
    raise ActiveRecord::RecordNotFound unless @product

    @variants = []
    @sold_out = false
    @related = preview_products.reject { |p| p.slug == @product.slug }.first(4)
    flash.now[:alert] = "Database unavailable. Showing preview data."
  end

  private

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
