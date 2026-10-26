# The smallest Airtable client the sync needs: batch upsert, a keyed lookup, and the
# meta API calls that provisioning uses. Upsert merges on a text field, so a retry
# never makes a second row. Airtable allows 10 records a request and 5 requests a
# second per base. It never logs or raises a field value, only a status and a type.
class AirtableClient
  API = "https://api.airtable.com/v0"
  BATCH = 10

  class Error < StandardError; end

  class << self
    # A callable taking (method, url, headers, body) and returning a Web::Response. Nil means the real network,
    # which tests refuse.
    attr_accessor :adapter

    # ENV first (production has no credentials file), then credentials.
    def program_token = ENV["AIRTABLE_PROGRAM_TOKEN"].presence || Rails.application.credentials.dig(:airtable, :program_token).presence
  end

  def initialize(token: self.class.program_token, base: Rails.application.config_for(:airtable)[:base])
    raise ArgumentError, "AIRTABLE_PROGRAM_TOKEN is not set" if token.blank?
    @token = token
    @base = base
  end

  # rows: array of field hashes. Returns { merge value => record }.
  def upsert(table, rows, merge_on:)
    rows.each_slice(BATCH).each_with_object({}) do |slice, out|
      body = call(:patch, table_url(table), json: {
        performUpsert: { fieldsToMergeOn: [ merge_on ] }, typecast: true, records: slice.map { { fields: it } }
      })
      body.fetch("records").each { out[it.dig("fields", merge_on).to_s] = it }
    end
  end

  # Records whose merge field matches one of the values.
  def find_by(table, field, values)
    return {} if values.empty?
    formula = "OR(" + values.map { "{#{field}}='#{it.to_s.gsub("'", "\\\\'")}'" }.join(",") + ")"
    body = call(:get, "#{table_url(table)}?#{{ filterByFormula: formula, pageSize: 100 }.to_query}")
    body.fetch("records").to_h { [ it.dig("fields", field).to_s, it ] }
  end

  # The meta API: the base's tables with their fields.
  def tables = call(:get, "#{API}/meta/bases/#{@base}/tables").fetch("tables")

  def create_table(name, fields) = call(:post, "#{API}/meta/bases/#{@base}/tables", json: { name:, fields: })

  def create_field(table_id, field) = call(:post, "#{API}/meta/bases/#{@base}/tables/#{table_id}/fields", json: field)

  private

  def table_url(table) = "#{API}/#{@base}/#{ERB::Util.url_encode(table)}"

  def call(method, url, json: nil)
    headers = { "Authorization" => "Bearer #{@token}", "Content-Type" => "application/json" }
    body = json&.to_json
    response = self.class.adapter ? self.class.adapter.call(method, url, headers, body) : http(method, url, headers, body)
    raise Error, "Airtable answered #{response.status} #{error_type(response)}".strip unless response.ok?
    response.json
  rescue Web::Error, JSON::ParserError => e
    raise Error, "Airtable could not be reached: #{e.class}"
  end

  def error_type(response)
    error = response.json["error"]
    (error.is_a?(Hash) ? error["type"] : error).to_s.first(60)
  rescue JSON::ParserError
    ""
  end

  def http(method, url, headers, body)
    raise Web::Error, "the network is off in tests" if Rails.env.test?

    uri = URI(url)
    request = { get: Net::HTTP::Get, post: Net::HTTP::Post, patch: Net::HTTP::Patch }.fetch(method).new(uri, headers)
    request.body = body if body
    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 20) { it.request(request) }
    Web::Response.new(status: res.code.to_i, headers: res.each_header.to_h, body: res.body.to_s)
  rescue ::Timeout::Error, SocketError, SystemCallError, IOError, OpenSSL::SSL::SSLError, Net::ProtocolError => e
    raise Web::Error, e.class.name
  end
end
