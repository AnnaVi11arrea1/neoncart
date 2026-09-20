module Api
  module V1
    class PaintingsController < BaseController
      before_action { require_scope!("products:read") }

      # Unlike products, every painting is returned and `published` is sent
      # alongside. The gallery is small enough to report its real state, which
      # beats making consumers infer an unpublish from a record's absence.
      def index
        paintings = Painting.ordered.with_attached_image
        render json: { paintings: paintings.map { |p| serialize(p) } }
      end

      def show
        painting = Painting.find_by!(slug: params[:slug])
        render json: { painting: serialize(painting) }
      end

      private

      def serialize(p)
        {
          id: p.id,
          slug: p.slug,
          title: p.title,
          description: p.description,
          medium: p.medium,
          dimensions: p.dimensions,
          year: p.year,
          published: p.published,
          position: p.position,
          image_url: p.image_url,
          url: Rails.configuration.x.store_url + "/gallery/#{p.slug}"
        }
      end
    end
  end
end
