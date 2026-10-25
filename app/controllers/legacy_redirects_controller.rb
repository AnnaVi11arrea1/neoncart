# 301s for URLs from the old Shopify store and Etsy shop, so links still out
# in search results and old posts land on a live page instead of a 404.
class LegacyRedirectsController < ApplicationController
  # /listing/:id(/:slug), with or without a /uk/, /de-en/ … prefix
  def listing
    moved_to LegacyRedirects.for_listing(params[:id])
  end

  # /collections/:handle — and Shopify's /collections/:handle/products/:slug,
  # which is a product page reached through a collection.
  def collection
    if (slug = params[:product_slug]).present?
      moved_to LegacyRedirects.for_product(slug) || product_path(slug)
    else
      moved_to LegacyRedirects.for_collection(params[:handle])
    end
  end

  def search
    moved_to params[:q].present? ? products_path(q: params[:q]) : products_path
  end

  # /product/:slug/:id — the old site's painting pages
  def painting
    moved_to Painting.published.exists?(slug: params[:slug]) ? painting_path(params[:slug]) : gallery_path
  end

  def path
    target = LegacyRedirects.for_path(request.path)
    raise ActionController::RoutingError, "No route matches #{request.path}" unless target

    moved_to target
  end

  private

  def moved_to(target) = redirect_to(target, status: :moved_permanently)
end
