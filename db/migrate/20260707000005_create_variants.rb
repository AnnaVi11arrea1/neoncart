class CreateVariants < ActiveRecord::Migration[7.1]
  def change
    create_table :variants do |t|
      t.references :product, null: false, foreign_key: true
      t.string :external_id
      t.string :sku
      t.string :title, null: false, default: "Default"
      t.jsonb :options, null: false, default: {}
      t.integer :price_cents
      t.boolean :available, null: false, default: true
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :variants, %i[product_id external_id], unique: true, where: "external_id IS NOT NULL"
  end
end
