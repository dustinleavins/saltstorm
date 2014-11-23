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

  def authenticate(email, password)
    if (email.nil? || password.nil?)
      return nil
    end

    user = User.first(:email => email.downcase)

    if user.nil?
      return nil
    end

    password_hash = User.generate_password_digest(password, user.password_salt)

    if (password_hash != user.password_hash)
      return nil
    end

    session[:uid] = user.id
    return user
  end

  def is_authenticated?
    return !(authentication_api_key.nil? and session[:uid].nil?)
  end

  def authentication_user_id
    api_key = authentication_api_key

    if api_key
      return api_key.user_id
    else
      return session[:uid]
    end
  end

  def authentication_api_key
    # The AUTHENTICATION header is the current 'real' one.
    # But for some reason, setting the AUTHENTICATION header using Rack::Test
    # actually sets the HTTP_AUTHENTICATION header.
    if request.env['AUTHENTICATION'] and !request.env['AUTHENTICATION'].empty?
      full_key = request.env['AUTHENTICATION']
    elsif request.env['HTTP_AUTHENTICATION'] and !request.env['HTTP_AUTHENTICATION'].empty?
      full_key = request.env['HTTP_AUTHENTICATION']
    else
      return nil
    end

    parts = full_key.sub('key=', '').split(ApiKey.key_separator, 2)
    if parts.length != 2
      return nil
    end

    user_id = parts[0].to_i
    api_key_identifier = parts[1]

    results = ApiKey.where(:user_id => user_id)
    results.each do |user_api_key|
      api_hash = Models.generate_digest(api_key_identifier, user_api_key.key_salt)
      return user_api_key if api_hash == user_api_key.key_hash
    end

    return nil
  end
end
