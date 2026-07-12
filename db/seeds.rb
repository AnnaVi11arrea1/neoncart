# Idempotent seeds — safe to run repeatedly.

puts "== Admin user =="
admin_email = ENV.fetch("ADMIN_EMAIL", "admin@example.com")
admin_password = ENV.fetch("ADMIN_PASSWORD", "changeme-now!")
admin = User.find_or_initialize_by(email: admin_email)
if admin.new_record?
  admin.assign_attributes(name: "Admin", password: admin_password, password_confirmation: admin_password, admin: true)
  admin.save!
  puts "Created admin #{admin_email} (password from ADMIN_PASSWORD env — change it!)"
else
  admin.update!(admin: true)
  puts "Admin #{admin_email} already exists"
end

puts "== Categories =="
%w[Apparel Prints Accessories Home].each_with_index do |name, i|
  Category.find_or_create_by!(slug: name.parameterize) { |c| c.name = name; c.position = i }
end

puts "== Suppliers =="
[
  { name: "Printify", adapter: "Dropshipping::PrintifyAdapter", fulfillment_mode: "auto",
    note: "Paste your Personal Access Token, then Test connection + Sync." },
  { name: "ThisNew", adapter: "Dropshipping::ThisNewAdapter", fulfillment_mode: "manual",
    note: "Partner API gated — manual mode until credentials arrive." },
  { name: "ArtsAdd", adapter: "Dropshipping::ArtsAddAdapter", fulfillment_mode: "manual",
    note: "Partner API gated — manual mode until credentials arrive." },
  { name: "Yoycol", adapter: "Dropshipping::YoycolAdapter", fulfillment_mode: "manual",
    note: "Partner API gated — manual mode until credentials arrive." }
].each do |attrs|
  s = Supplier.find_or_initialize_by(slug: attrs[:name].parameterize)
  next unless s.new_record?

  s.assign_attributes(name: attrs[:name], adapter: attrs[:adapter], fulfillment_mode: attrs[:fulfillment_mode])
  s.save!
  puts "  #{attrs[:name]} — #{attrs[:note]}"
end

puts "Done. Sign in at /admin with #{admin_email}."
