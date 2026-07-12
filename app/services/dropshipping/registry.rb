module Dropshipping
  # Central list of adapters offered in the admin UI. To integrate a new
  # dropshipper: write an adapter (subclass BaseAdapter or
  # GenericPodAdapter), add it here, create the supplier in Admin.
  module Registry
    ADAPTERS = {
      "Printify (full API)" => "Dropshipping::PrintifyAdapter",
      "ThisNew" => "Dropshipping::ThisNewAdapter",
      "ArtsAdd" => "Dropshipping::ArtsAddAdapter",
      "Yoycol" => "Dropshipping::YoycolAdapter",
      "Generic POD (configurable REST)" => "Dropshipping::GenericPodAdapter"
    }.freeze

    def self.options_for_select = ADAPTERS.map { |label, klass| [label, klass] }
  end
end
