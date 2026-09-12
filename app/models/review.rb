# A verified-purchase product review. The order_item association (see the
# unique index in the reviews migration) is what proves the reviewer actually
# bought this item — one review per purchased line, guest or signed-in.
class Review < ApplicationRecord
  belongs_to :product
  belongs_to :order_item
  belongs_to :user, optional: true
  has_many_attached :photos

  enum :status, { pending: "pending", approved: "approved", rejected: "rejected" }

  validates :reviewer_name, :body, presence: true
  validates :rating, inclusion: { in: 1..5 }
  validates :order_item_id, uniqueness: true
  validate :photos_are_valid

  before_validation { self.status ||= "pending" }

  scope :visible, -> { approved }

  CONTENT_TYPES = %w[image/jpeg image/png image/webp image/gif image/avif].freeze
  MAX_BYTES = 15.megabytes
  MAX_PHOTOS = 2

  private

  def photos_are_valid
    return unless photos.attached?

    errors.add(:photos, "can only have up to #{MAX_PHOTOS}") if photos.count > MAX_PHOTOS

    photos.each do |photo|
      errors.add(:photos, "must be a JPEG, PNG, WebP, GIF, or AVIF") unless photo.content_type.in?(CONTENT_TYPES)
      errors.add(:photos, "must be smaller than 15 MB") if photo.byte_size > MAX_BYTES
    end
  end
end
