class WidenPublishedPostProductIds < ActiveRecord::Migration[7.1]
  # products.id is a bigint, so an integer[] here would raise
  # PG::NumericValueOutOfRange on any id past 2,147,483,647. That will never
  # happen with this catalogue, but the table is empty today and changing the
  # type of an array column on a full one is a different job.
  def up
    change_column :published_posts, :store_product_ids, :bigint,
                  array: true, null: false, default: [],
                  using: "store_product_ids::bigint[]"
  end

  def down
    change_column :published_posts, :store_product_ids, :integer,
                  array: true, null: false, default: [],
                  using: "store_product_ids::integer[]"
  end
end
