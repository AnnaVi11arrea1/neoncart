module Dropshipping
  # ArtsAdd (artsadd.com) — all-over-print POD. ArtsAdd exposes no public
  # pull API for storefronts, so products are imported from the seller-center
  # export file (Seller Center → Products → Export), which is Excel-2003 XML.
  #
  # Import/sync it in Admin → Suppliers → ArtsAdd → "Import / Sync now".
  # Re-upload a fresh export any time to pull in your latest changes: existing
  # products update in place (matched on ArtsAdd product id), newly added
  # products come in as drafts to review, and sizes you removed on ArtsAdd are
  # marked unavailable.
  #
  # Order fulfillment stays manual — paid ArtsAdd items land in the
  # Fulfillment Queue (keep fulfillment_mode = "manual").
  #
  # Prices in the export are ArtsAdd's COST. On import we set retail =
  # cost × markup (rounded to a .99 ending) and stash the cost in metadata,
  # so re-syncing to pull ArtsAdd changes re-prices consistently instead of
  # clobbering your retail prices with cost. Override the multiplier per
  # supplier via settings JSON, e.g. {"markup": 2.5}. Default 3.0.
  #
  # The multiplier can be TIERED by cost, so cheap items carry a fatter margin
  # than expensive ones (a $7 tee at 3.5x still reads as a fair price; a $34
  # hoodie at 3.5x does not). Set all three keys to enable it:
  #   {"markup": 3.5, "markup_above": 2.5, "tier_threshold_cents": 1333}
  # meaning: cost under $13.33 -> 3.5x, cost at or above it -> 2.5x. With
  # markup_above unset the single "markup" applies to everything.
  DEFAULT_MARKUP = 3.0

  class ArtsAddAdapter < BaseAdapter
    # Parse an uploaded ArtsAdd export and upsert products/variants.
    # Accepts a file path or an IO. Returns the number of products imported.
    def import_file!(io_or_path)
      products = ArtsAddSpreadsheet.parse(io_or_path)
      raise Error, "No products found — is this an ArtsAdd product export (.xls)?" if products.empty?

      low        = (supplier.settings["markup"].presence || DEFAULT_MARKUP).to_f
      high       = supplier.settings["markup_above"].presence&.to_f
      threshold  = supplier.settings["tier_threshold_cents"].presence&.to_i

      products.each do |attrs|
        # ArtsAdd-specific fields go on product.metadata (upsert_product!
        # doesn't take them) so the fulfillment queue can deep-link to ArtsAdd
        # and we can show cost/margin.
        cost_cents = attrs[:price_cents].to_i
        meta = {
          "source_url" => attrs.delete(:source_url),
          "product_type" => attrs.delete(:product_type),
          "cost_cents" => cost_cents
        }.compact

        # Cost -> retail markup, applied to the product and every variant.
        attrs[:price_cents] = retail_cents(cost_cents, markup_for(cost_cents, low, high, threshold))
        attrs[:variants] = Array(attrs[:variants]).map do |v|
          vc = v[:price_cents].to_i
          v.merge(price_cents: retail_cents(vc, markup_for(vc, low, high, threshold)))
        end

        product = upsert_product!(**attrs)
        product.update!(metadata: product.metadata.merge(meta)) unless product.metadata.slice(*meta.keys) == meta
      end
      products.size
    end

    # Which multiplier applies to a given cost. Tiering is active only when
    # both markup_above and tier_threshold_cents are configured.
    def markup_for(cost_cents, low, high, threshold)
      return low if high.nil? || threshold.nil?

      cost_cents.to_i >= threshold ? high : low
    end

    # cost × markup, rounded up to the nearest whole dollar minus 1¢ (.99).
    def retail_cents(cost_cents, markup)
      return cost_cents.to_i if cost_cents.to_i <= 0

      (cost_cents * markup / 100.0).round * 100 - 1
    end

    def sync_products!
      raise Error,
            "ArtsAdd has no pull API. Download your export from ArtsAdd " \
            "(Seller Center → Products → Export) and upload it with Import / Sync now."
    end

    def test_connection!
      raise Error,
            "ArtsAdd is file-import based — nothing to connect to. Use " \
            "Import / Sync now to upload your product export (.xls)."
    end

    # ArtsAdd runs in manual fulfillment mode; the SubmitOrderToSuppliersJob
    # routes its items to the Fulfillment Queue, so these are never called.
    def submit_order!(*)
      raise NotConfigured, "ArtsAdd runs in manual fulfillment mode — see the Fulfillment Queue."
    end

    def fetch_tracking(*) = []
  end
end
