# XML sitemap for search engines. Listed in public/robots.txt.
class SitemapsController < ApplicationController
  def show
    @products  = Product.where(status: "active").order(:updated_at)
    @paintings = Painting.published.ordered
    respond_to { |format| format.xml }
  end
end
