# A post that actually went out, kept here so it can be found and reused later.
#
# This is a record of an event, not a mirror of the Sanity document it came
# from. The document keeps changing; what was published does not. So every
# value that matters is copied in at publish time — above all the caption.
class PublishedPost < ApplicationRecord
  validates :sanity_attempt_id, presence: true, uniqueness: true
  validates :platform, :published_at, presence: true

  scope :on_platform, ->(platform) { platform.blank? ? all : where(platform:) }

  # Same shape as Product.search: ILIKE, no search gem, nothing to install.
  def self.search(q)
    return all if q.blank?

    where("caption ILIKE :q OR permalink ILIKE :q OR platform ILIKE :q",
          q: "%#{sanitize_sql_like(q)}%")
  end

  # Whichever of the products are still here. A product deleted since does not
  # invalidate the record of the post that featured it.
  def products
    return Product.none if store_product_ids.blank?

    Product.where(id: store_product_ids)
  end
end
