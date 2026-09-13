# A malformed percent-encoded query param key (e.g. a bot fuzzing URLs) can
# decode into a String tagged UTF-8 that isn't actually valid UTF-8.
# ActiveSupport::ParameterFilter#value_for_key runs Regexp#match? against that
# key when scrubbing sensitive params for logging, which raises ArgumentError
# instead of failing gracefully — turning a bad request into an unhandled 500
# (Rails' own ActionDispatch::ShowExceptions middleware sits below this point
# in the stack, so it can't be caught by a Rack-level middleware upstream).
# String#scrub replaces invalid bytes with the U+FFFD replacement character,
# which is enough to make the regex match safe.
require "active_support/parameter_filter"

module ParameterFilterInvalidEncodingFix
  def value_for_key(key, value, full_parent_key = nil, original_params = nil)
    key = key.scrub if key.is_a?(String)
    super(key, value, full_parent_key, original_params)
  end
end

ActiveSupport::ParameterFilter.prepend(ParameterFilterInvalidEncodingFix)
