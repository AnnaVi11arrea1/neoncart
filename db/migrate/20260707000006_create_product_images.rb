class CreateProductImages < ActiveRecord::Migration[7.1]
  def change
    create_table :product_images do |t|
      t.references :product, null: false, foreign_key: true
      t.string :remote_url # supplier CDN image; uploads use ActiveStorage
      t.integer :position, null: false, default: 0
      t.timestamps
    end
  end
end
