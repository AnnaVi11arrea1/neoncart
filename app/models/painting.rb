# A painting in the public gallery. Unlike Product images (remote ArtsAdd CDN
# URLs), gallery images are uploaded by Anna and stored with ActiveStorage on
# local disk, so they need no supplier and never sync.
class Painting < ApplicationRecord
  has_one_attached :image

  validates :title, presence: true
  validates :slug, presence: true, uniqueness: true
  validates :image, presence: true
  validate  :image_must_be_a_supported_type

  scope :published, -> { where(published: true) }
  scope :ordered,   -> { order(:position, created_at: :desc) }

  before_validation :generate_slug, on: :create

  CONTENT_TYPES = %w[image/jpeg image/png image/webp image/gif image/avif].freeze
  MAX_BYTES = 15.megabytes

  def to_param = slug

  # Sized for the gallery grid; the show page uses a larger limit.
  def thumb  = image.variant(resize_to_limit: [800, 800]).processed
  def large  = image.variant(resize_to_limit: [1800, 1800]).processed

  # The original, not a variant: consumers outside the site (the CMS) do their
  # own resizing and want the full-quality file, not one sized for our grid.
  def image_url
    return nil unless image.attached?

    Rails.application.routes.url_helpers.rails_blob_path(image, only_path: true)
  end

  def caption_line
    [medium, dimensions, year].compact_blank.join(" · ")
  end

  private

  def generate_slug
    return if slug.present?

    base = title.to_s.parameterize.presence || "painting"
    candidate = base
    n = 1
    candidate = "#{base}-#{n += 1}" while self.class.exists?(slug: candidate)
    self.slug = candidate
  end

  def image_must_be_a_supported_type
    return unless image.attached?

    errors.add(:image, "must be a JPEG, PNG, WebP, GIF, or AVIF") unless image.content_type.in?(CONTENT_TYPES)
    errors.add(:image, "must be smaller than 15 MB") if image.byte_size > MAX_BYTES
  end
end
