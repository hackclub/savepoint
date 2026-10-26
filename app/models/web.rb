require "net/http"
require "ipaddr"
require "resolv"

# The one place the ship checker and the review page reach the internet (GitHub, Airtable, a participant's links).
# Tests set Web.adapter to a lambda, so none of them touches the network, and Web refuses a real request in test.
module Web
  Response = Data.define(:status, :headers, :body) do
    def ok? = status.between?(200, 299)
    def json = JSON.parse(body.to_s)
  end

  # Anything that stops a request from getting an answer: a timeout, a refused connection, a private address.
  class Error < StandardError; end
  # The answer didn't come in time. Unlike a refused connection or a missing host, that says nothing about the link (D-022).
  class Timeout < Error; end

  PRIVATE = %w[
    0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12 192.0.0.0/24 192.168.0.0/16
    198.18.0.0/15 224.0.0.0/3 ::/96 64:ff9b::/96 fc00::/7 fe80::/10 ff00::/8
  ].map { IPAddr.new(it) }.freeze

  class << self
    # A callable taking (method, url, headers) and returning a Response. Nil means the real network.
    attr_accessor :adapter
  end

  module_function

  # public_only: the URL came from a participant, so it may only reach public addresses (and follows no redirects
  # to anywhere else).
  # body: a String sent with a :post. The adapter gets it as a fourth argument, only when there is one.
  def request(method, url, headers: {}, public_only: false, timeout: 6, redirects: 3, read_body: true, body: nil)
    return (body ? adapter.call(method, url, headers, body) : adapter.call(method, url, headers)) if adapter
    raise Error, "the network is off in tests" if Rails.env.test?

    uri = URI(url)
    raise Error, "only http and https links" unless uri.is_a?(URI::HTTP) && uri.hostname.present?
    ip = public_ip(uri.hostname) if public_only
    klass = { get: Net::HTTP::Get, head: Net::HTTP::Head, post: Net::HTTP::Post }.fetch(method)
    http = Net::HTTP.new(uri.hostname, uri.port)
    http.ipaddr = ip if ip
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 4
    http.read_timeout = timeout
    req = klass.new(uri, { "User-Agent" => "save-point.hackclub.com", "Accept" => "*/*" }.merge(headers))
    req.body = body if body
    answer = +""
    res = http.start { |connection| connection.request(req) { |r| answer = r.read_body.to_s if read_body && method != :head } }
    if res.is_a?(Net::HTTPRedirection) && res["location"] && redirects.positive?
      target = URI.join(url, res["location"]).to_s
      headers = headers.reject { |name, _| name.to_s.casecmp?("authorization") } unless URI(target).host == uri.host
      return request(method, target, headers:, public_only:, timeout:, redirects: redirects - 1, read_body:, body:)
    end
    Response.new(status: res.code.to_i, headers: res.each_header.to_h, body: answer)
  rescue ::Timeout::Error => e
    raise Web::Timeout, e.message.first(120)
  rescue SocketError, SystemCallError, IOError, OpenSSL::SSL::SSLError, Net::ProtocolError, URI::InvalidURIError => e
    raise Error, e.message.first(120)
  end

  def get(url, **) = request(:get, url, **)
  def head(url, **) = request(:head, url, **)
  def post(url, **) = request(:post, url, **)

  def public_ip(host)
    ips = Addrinfo.getaddrinfo(host, nil, nil, :STREAM).map(&:ip_address).uniq
    raise Error, "#{host} is not a public address" if ips.empty? || ips.any? { |ip| PRIVATE.any? { it.include?(IPAddr.new(ip).native) } }
    ips.first
  rescue SocketError
    raise Error, "#{host} does not exist"
  end
end
