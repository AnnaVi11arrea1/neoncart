namespace :catalog do
  desc "Import a supplier export file and put every listing live. " \
       "Usage: rake 'catalog:import[/path/to/export.xls]' or " \
       "rake 'catalog:import[/path/to/export.xls,printify]'"
  task :import, %i[path supplier_slug] => :environment do |_t, args|
    path = args[:path].presence or abort "Usage: rake 'catalog:import[/path/to/export.xls]'"
    abort "No such file: #{path}" unless File.exist?(path)

    supplier = Supplier.find_by!(slug: args[:supplier_slug].presence || "artsadd")
    before = Product.count

    count = supplier.adapter_instance.import_file!(path)
    supplier.update!(last_synced_at: Time.current,
                     last_sync_log: "OK — imported #{count} products from file #{Time.current.strftime('%b %-d, %H:%M')}")
    puts "Imported #{count} products from #{File.basename(path)} (#{Product.count - before} new)."

    Rake::Task["catalog:activate_all"].invoke
  end

  desc "Put every listing live: non-archived products -> active, all variants -> available"
  task activate_all: :environment do
    result = Catalog::ActivateAll.call
    puts "Activated #{result[:products]} products, made #{result[:variants]} variants available."
    puts "Catalog now: #{Product.group(:status).count}, " \
         "#{Variant.where(available: true).count}/#{Variant.count} variants available."
  end

  desc "Export active products to .xlsx for TikTok Shop's Product Upload Accelerator. " \
       "Usage: rake 'catalog:export_tiktok[/path/to/output.xlsx]' (defaults to tmp/tiktok_export.xlsx)"
  task :export_tiktok, [:path] => :environment do |_t, args|
    require "caxlsx"

    path = args[:path].presence || Rails.root.join("tmp/tiktok_export.xlsx").to_s
    # No product here has a real GTIN/UPC/EAN/ASIN — ArtsAdd (and every other
    # supplier so far) never assigns one to print-on-demand items, and this
    # column is left blank pending a GTIN exemption from TikTok rather than
    # stuffing in an internal SKU that doesn't match any real barcode format.
    #
    # One row per variant, not per product: the Accelerator's 5 columns have
    # no notion of "variant/size" at all, so the only way to give each size
    # its own price/quantity is to make each one its own row, with the size
    # folded into the product name to tell rows for the same product apart.
    package = Axlsx::Package.new
    package.workbook.add_worksheet(name: "Products") do |sheet|
      sheet.add_row ["Identifier code", "Product name", "Product description", "Price", "Quantity"]

      Product.active.includes(:variants).find_each do |product|
        description = product.description.to_plain_text
        multi_variant = product.variants.size > 1

        product.variants.each do |variant|
          name = multi_variant ? "#{product.title} — #{variant.label}" : product.title
          price = variant.price_cents_or_default / 100.0
          quantity = variant.available? ? 999 : 0
          sheet.add_row [nil, name, description, price, quantity]
        end
      end
    end
    package.serialize(path)

    rows = Variant.joins(:product).merge(Product.active).count
    puts "Wrote #{rows} row(s) (one per variant) to #{path}."
    puts "Identifier code column is blank — fill it in once your GTIN exemption is confirmed."
  end
end
