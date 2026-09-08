class GalleryController < ApplicationController
  def index
    @paintings = Painting.published.ordered.with_attached_image
  end

  def show
    @painting = Painting.published.find_by!(slug: params[:slug])
    @others   = Painting.published.ordered.where.not(id: @painting.id).limit(6).with_attached_image
  end
end
