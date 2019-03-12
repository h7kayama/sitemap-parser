require 'nokogiri'
require 'faraday'
require 'faraday_middleware'

class SitemapParser

  def initialize(url, opts = {})
    @url = url
    @options = {:recurse => false, :url_regex => nil}.merge(opts)
  end

  def raw_sitemap
    @raw_sitemap ||= begin
      if @url =~ /\Ahttp/i
        request_options = @options.dup.tap { |opts| opts.delete(:recurse); opts.delete(:url_regex) }
        request = Faraday.new(@url, request_options){|request|
          request.use FaradayMiddleware::FollowRedirects
          request.adapter :net_http
        }
        response = request.get
        if response.success?
          response.body
        else
          raise "HTTP request to #{@url} failed"
        end
      elsif File.exist?(@url) && @url =~ /[\\\/]sitemap\.xml\Z/i
        open(@url) { |f| f.read }
      end
    end
  end

  def sitemap
    @sitemap ||= Nokogiri::XML(raw_sitemap)
  end

  def urls
    if sitemap.at('urlset')
      filter_sitemap_urls(sitemap.at("urlset").search("url"))
    elsif sitemap.at('sitemapindex')
      found_urls = []
      if @options[:recurse]
        urls = sitemap.at('sitemapindex').search('sitemap')
        filter_sitemap_urls(urls).each do |sitemap|
          child_sitemap_location = sitemap.at('loc').content
          found_urls << self.class.new(child_sitemap_location, @options.merge(:recurse => false)).urls
        end
      end
      return found_urls.flatten
    else
      raise 'Malformed sitemap, no urlset'
    end
  end

  def to_a
    urls.map { |url| url.at("loc").content }
  rescue NoMethodError
    raise 'Malformed sitemap, url without loc'
  end

  private

  def filter_sitemap_urls(urls)
    return urls if @options[:url_regex].nil?
    urls.select {|url| url.at("loc").content.strip =~ @options[:url_regex] }
  end
end
