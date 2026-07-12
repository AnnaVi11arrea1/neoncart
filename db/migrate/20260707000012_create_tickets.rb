class CreateTickets < ActiveRecord::Migration[7.1]
  def change
    create_table :tickets do |t|
      t.references :user, foreign_key: true
      t.references :order, foreign_key: true
      t.string :token, null: false
      t.string :email, null: false
      t.string :name
      t.string :subject, null: false
      t.string :status, null: false, default: "open" # open | pending | resolved | closed
      t.string :priority, null: false, default: "normal" # low | normal | high
      t.datetime :last_message_at
      t.timestamps
    end
    add_index :tickets, :token, unique: true
    add_index :tickets, :status

    create_table :ticket_messages do |t|
      t.references :ticket, null: false, foreign_key: true
      t.references :user, foreign_key: true
      t.string :author_type, null: false, default: "customer" # customer | admin
      t.text :body, null: false
      t.timestamps
    end
  end
end
