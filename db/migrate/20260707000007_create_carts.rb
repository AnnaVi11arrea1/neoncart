class CreateCarts < ActiveRecord::Migration[7.1]
  def change
    create_table :carts do |t|
      t.references :user, foreign_key: true
      t.string :token, null: false
      t.timestamps
    end
    add_index :carts, :token, unique: true

    create_table :cart_items do |t|
      t.references :cart, null: false, foreign_key: true
      t.references :product, null: false, foreign_key: true
      t.references :variant, foreign_key: true
      t.integer :quantity, null: false, default: 1
      t.timestamps
    end
    add_index :cart_items, %i[cart_id product_id variant_id], unique: true
  end
end
