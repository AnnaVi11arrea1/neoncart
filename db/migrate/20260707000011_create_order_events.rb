class CreateOrderEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :order_events do |t|
      t.references :order, null: false, foreign_key: true
      t.string :kind, null: false # placed | paid | submitted | shipped | delivered | cancelled | note | error
      t.string :message
      t.jsonb :data, null: false, default: {}
      t.timestamps
    end
    add_index :order_events, %i[order_id created_at]
  end
end
