class CreatePublishedPosts < ActiveRecord::Migration[7.1]
  def change
    create_table :published_posts do |t|
      # The Sanity publishAttempt this row records. Unique, because the worker
      # retries and a retry must update the row rather than add a second one.
      t.string :sanity_attempt_id, null: false
      t.string :sanity_post_id
      t.string :platform, null: false
      t.string :post_format

      # The caption AS POSTED. Not a pointer at the Sanity document: that
      # document can be edited afterwards, and an archive that reads through to
      # it would quietly hand back something that never went out.
      t.text :caption, null: false, default: ""
      t.string :permalink
      t.string :asset_url

      # Store product ids, so the archive links to real products here rather
      # than to Sanity references this app cannot resolve.
      t.integer :store_product_ids, array: true, null: false, default: []

      t.datetime :published_at, null: false
      t.timestamps
    end

    add_index :published_posts, :sanity_attempt_id, unique: true
    add_index :published_posts, :published_at
    add_index :published_posts, :platform
  end
end
