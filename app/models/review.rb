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

  # Distinguishes "wrong format, honest mistake" (e.g. a HEIC or PDF — just a
  # validation error) from "this looks like an attack" (an executable/script
  # extension disguised as a photo upload) — only the latter pages security.
  SUSPICIOUS_EXTENSION = /\.(php\d?|phtml|phar|asp|aspx|jsp|jspx|cgi|pl|sh|bash|exe|bat|cmd|dll|jar|war|htaccess)$/i
  SUSPICIOUS_CONTENT_TYPE = /php|script|executable|x-sh|x-msdownload/i

  private

  def photos_are_valid
    return unless photos.attached?

    errors.add(:photos, "can only have up to #{MAX_PHOTOS}") if photos.count > MAX_PHOTOS

    photos.each do |photo|
      unless photo.content_type.in?(CONTENT_TYPES)
        errors.add(:photos, "must be a JPEG, PNG, WebP, GIF, or AVIF")
        flag_if_suspicious(photo)
      end
      errors.add(:photos, "must be smaller than 15 MB") if photo.byte_size > MAX_BYTES
    end
  end

  def flag_if_suspicious(photo)
    filename = photo.filename.to_s
    return unless filename.match?(SUSPICIOUS_EXTENSION) || photo.content_type.to_s.match?(SUSPICIOUS_CONTENT_TYPE)

    SecurityAlertJob.perform_later(
      "🚨 neoncart: rejected review-photo upload `#{filename}` (#{photo.content_type}) — looks like a malicious file type, not just a wrong format."
    )
  end
end
