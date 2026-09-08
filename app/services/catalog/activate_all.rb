module Catalog
  # Flip listings live in bulk.
  #
  # After an ArtsAdd import there are always two reasons a listing is hidden
  # from the storefront: `upsert_product!` files every *new* product as a
  # "draft" for review, and the export's Status column maps anything that
  # isn't "On sale" (ArtsAdd's "Saved" = designed but not yet listed) to an
  # unavailable variant, which the storefront renders as sold out.
  #
  # This puts everything live: non-archived products go active, every variant
  # goes available. Archived products are left alone — archiving is a
  # deliberate retirement, not an import artifact.
  module ActivateAll
    def self.call(supplier: nil)
      products = Product.where.not(status: %w[active archived])
      variants = Variant.where(available: false)
      if supplier
        products = products.where(supplier: supplier)
        variants = variants.where(product: Product.where(supplier: supplier))
      end

      { products: products.update_all(status: "active", updated_at: Time.current),
        variants: variants.update_all(available: true, updated_at: Time.current) }
    end
  end
end
