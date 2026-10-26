# Links and images from addresses a participant typed (a repo, a demo) or that came from another system (the Unified
# YSWS DB). The models only accept http(s) now, but older rows and outside data may not, so nothing becomes an href or
# src unless it is http(s). Anything else prints as plain text, which a browser never runs.
module SafeLinksHelper
  # True for an absolute http or https URL with a host. False for javascript:, data:, vbscript:, file: and the rest.
  def safe_http_url?(url)
    uri = URI.parse(url.to_s.strip)
    uri.is_a?(URI::HTTP) && uri.host.present?
  rescue URI::InvalidURIError
    false
  end

  # link_to for a URL that may be unsafe. A link when it is http(s). Otherwise the text, escaped, with no link.
  # Forms: safe_link_to(name, url, **options) and safe_link_to(url, **options) { block }. The block is dropped when
  # the URL is unsafe, so give it text that makes sense as a link only.
  def safe_link_to(name_or_url, url_or_options = nil, options = {}, &block)
    name, url, options = block ? [ nil, name_or_url, url_or_options || {} ] : [ name_or_url, url_or_options, options ]
    return (block ? nil : name.to_s) unless safe_http_url?(url)

    block ? link_to(url.to_s.strip, options, &block) : link_to(name, url.to_s.strip, options)
  end

  # image_tag for a URL that may be unsafe: nothing unless it is http(s).
  def safe_image_tag(url, **options)
    image_tag(url.to_s.strip, **options) if safe_http_url?(url)
  end
end
