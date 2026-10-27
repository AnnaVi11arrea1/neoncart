# Product feeds, built fresh from the database on every request.
#
# Google: Merchant Center puts products in the free Shopping listings and lets
# Shopping / Performance Max ads use them. Merchant Center → Products → Add
# products → From a file → scheduled fetch of
# https://www.everfluorescent.com/feeds/google.xml.
#
# Pinterest: Catalogs turns each item into a product pin linking to the shop.
# Pinterest Business → Catalogs → Add data source → XML, scheduled fetch of
# https://www.everfluorescent.com/feeds/pinterest.xml.
class FeedsController < ApplicationController
  before_action :load_products

  def google
    respond_to { |format| format.xml }
  end

  def pinterest
    respond_to { |format| format.xml }
  end

  private

  def load_products
    @products = Product.storefront.with_card_images
                       .includes(:category, :rich_text_description, :variants)
                       .select { |p| p.all_image_urls.any? } # both reject items without an image
  end
end
