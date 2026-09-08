module Admin
  class PaintingsController < BaseController
    before_action :set_painting, only: %i[edit update destroy]

    def index
      @paintings = Painting.ordered.with_attached_image
    end

    def new = @painting = Painting.new

    def create
      @painting = Painting.new(painting_params)
      if @painting.save
        redirect_to admin_paintings_path, notice: "“#{@painting.title}” added to the gallery."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      # An empty file field must not wipe the existing image.
      attrs = painting_params
      attrs.delete(:image) if attrs[:image].blank?
      if @painting.update(attrs)
        redirect_to admin_paintings_path, notice: "Saved."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @painting.destroy!
      redirect_to admin_paintings_path, notice: "Removed from the gallery."
    end

    private

    def set_painting = @painting = Painting.find_by!(slug: params[:slug])

    def painting_params
      params.require(:painting)
            .permit(:title, :description, :medium, :dimensions, :year, :published, :position, :image)
    end
  end
end
