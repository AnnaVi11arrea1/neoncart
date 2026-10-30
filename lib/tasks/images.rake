namespace :images do
  # Builds the :card and :large renditions (see Product) for every product
  # image that doesn't have them yet. New uploads get them automatically;
  # this backfills the ones uploaded before the renditions existed. Safe to
  # re-run: variants that already exist are skipped.
  desc "Generate WebP renditions for existing product images"
  task variants: :environment do
    built = skipped = failed = 0
    Product.with_attached_images.find_each do |product|
      product.images.each do |image|
        next skipped += 1 unless image.variable?

        %i[card large].each do |name|
          image.variant(name).processed
          built += 1
        rescue StandardError => e
          failed += 1
          warn "#{product.slug} image #{image.id} #{name}: #{e.class}: #{e.message}"
        end
      end
    end
    puts "Renditions: #{built} ready, #{failed} failed, #{skipped} images not resizable"
  end
end
