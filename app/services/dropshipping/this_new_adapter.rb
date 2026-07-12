module Dropshipping
  # ThisNew (thisnew.com) — POD dropshipper. Their API is partner-gated;
  # request access via their support/partner channel. Until then, run this
  # supplier in "manual" fulfillment_mode. Once you have docs, set
  # api_base_url + api_key and tune `settings` per GenericPodAdapter.
  class ThisNewAdapter < GenericPodAdapter
  end
end
