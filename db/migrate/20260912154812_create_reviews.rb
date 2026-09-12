class CreateReviews < ActiveRecord::Migration[7.1]
  def change
    create_table :reviews do |t|
      t.references :product, null: false, foreign_key: true
      # unique: a purchased line item can only be reviewed once — this is
      # what makes a review provably tied to a verified purchase.
      t.references :order_item, null: false, foreign_key: true, index: { unique: true }
      t.references :user, null: true, foreign_key: true
      t.string :reviewer_name, null: false
      t.string :guest_email
      t.integer :rating, null: false
      t.string :title
      t.text :body, null: false
      t.string :status, null: false, default: "pending"
      t.string :rejection_reason

      t.timestamps
    end

    add_index :reviews, :status
  end
end
