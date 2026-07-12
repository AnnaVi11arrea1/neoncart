class CreateOrderItems < ActiveRecord::Migration[7.1]
  def change
    create_table :order_items do |t|
      t.references :order, null: false, foreign_key: true
      t.references :product, foreign_key: true
      t.references :variant, foreign_key: true
      t.references :supplier, foreign_key: true
      t.string :title, null: false
      t.string :sku
      t.integer :quantity, null: false, default: 1
      t.integer :unit_price_cents, null: false, default: 0
      t.string :external_order_id # id at the supplier once submitted
      t.string :fulfillment_status, null: false, default: "unfulfilled"
      # unfulfilled | submitted | awaiting_manual | fulfilled | cancelled
      t.timestamps
    end
  end
end
