class CreateWebhookEndpoints < ActiveRecord::Migration[7.1]
  def change
    create_table :webhook_endpoints do |t|
      t.string :name, null: false
      t.string :url, null: false
      t.string :secret, null: false
      t.string :events, array: true, null: false, default: ["order.status_changed"]
      t.boolean :active, null: false, default: true
      t.timestamps
    end

    create_table :webhook_deliveries do |t|
      t.references :webhook_endpoint, null: false, foreign_key: true
      t.string :event, null: false
      t.jsonb :payload, null: false, default: {}
      t.integer :response_code
      t.integer :attempts, null: false, default: 0
      t.datetime :delivered_at
      t.text :last_error
      t.timestamps
    end
    add_index :webhook_deliveries, %i[webhook_endpoint_id created_at]
  end
end
