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
    return !(session[:uid].nil?)
  end
end
