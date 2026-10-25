# Product feed for Google Merchant Center, which puts products in the free
# Shopping listings and lets Shopping / Performance Max ads use them.
# Merchant Center → Products → Add products → From a file → scheduled fetch
# of https://www.everfluorescent.com/feeds/google.xml.
class FeedsController < ApplicationController
  def google
    @products = Product.storefront.with_card_images
                       .includes(:category, :rich_text_description, :variants)
                       .select { |p| p.all_image_urls.any? } # Google rejects items without an image
    respond_to { |format| format.xml }
  end
end
