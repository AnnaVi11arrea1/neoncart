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
end
