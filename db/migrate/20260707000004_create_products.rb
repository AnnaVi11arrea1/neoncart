class CreateProducts < ActiveRecord::Migration[7.1]
  def change
    create_table :products do |t|
      t.string :title, null: false
      t.string :slug, null: false
      t.text :description
      t.references :category, foreign_key: true
      t.references :supplier, foreign_key: true # nil = in-house / manual product
      t.string :external_id # supplier's product id
      t.string :status, null: false, default: "draft" # draft | active | archived
      t.integer :price_cents, null: false, default: 0
      t.integer :compare_at_price_cents
      t.string :currency, null: false, default: "usd"
      t.boolean :featured, null: false, default: false
      t.string :tags, array: true, null: false, default: []
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_index :products, :slug, unique: true
    add_index :products, %i[supplier_id external_id], unique: true, where: "external_id IS NOT NULL"
    add_index :products, :status
    add_index :products, :tags, using: :gin
  end
end
