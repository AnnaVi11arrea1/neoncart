# Malformed percent-encoding in a query string (e.g. a bot fuzzing URLs) can
# decode into a String tagged UTF-8 that isn't actually valid UTF-8. Rails
# doesn't check for this until deep inside parameter filtering/logging, where
# Regexp#match? raises ArgumentError instead of failing gracefully — turning
# a bad request into an unhandled 500. Catch it here and answer 400 instead.
class InvalidEncodingGuard
  MESSAGE_PATTERN = /invalid byte sequence in UTF-8|invalid %-encoding/

  def initialize(app)
    @app = app
  end

  def call(env)
    @app.call(env)
  rescue ArgumentError => e
    raise unless e.message.match?(MESSAGE_PATTERN)

    [400, { "Content-Type" => "text/plain" }, ["Bad Request"]]
  end
end
