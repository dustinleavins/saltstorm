require './settings.rb'

module Helpers
  def base_url(url='')
    URI.join(request.base_url, url).to_s
  end

  def json_response(status_code, hash)
    content_type :json
    return [status_code, hash.to_json]
  end

  def titleize(page_title='')
    site_name = Settings::site(ENV['RACK_ENV'])['site_name']
    if page_title.nil? or page_title.empty?
      return site_name
    else
      return "#{site_name} - #{page_title}"
    end
  end
end
