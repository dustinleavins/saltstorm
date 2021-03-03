# Saltstorm - Fun-Money Betting on the Web
# Copyright (C) 2013, 2014, 2021  Dustin Leavins
#
# Full license can be found in 'LICENSE.txt'
require 'uri'
require 'cgi'
require 'json'
require 'rubygems'
require 'bundler'
Bundler.require
require './apps/helpers.rb'
require './models.rb'
require './persistence.rb'
require './settings.rb'
include Models

class MainApp < Sinatra::Base
  app_settings = ::Settings::site(settings.environment.to_s)

  configure do
    set :views, 'views/' 
    set :static_cache_control, [:private]
    set :public_folder, './dist/'

    enable :sessions
    register Sinatra::Flash
    set :session_secret, ::Settings::secret_token
    helpers Helpers
  end

  configure :development, :production do
    enable :logging
  end

  before do
    cache_control :private
    @site_name = app_settings['site_name']
    @site_description = app_settings['site_description']
  end

  get '/' do
    return send_file File.join(settings.public_folder, 'index.html')
  end

  # TODO: Remove once /reset_password route gets moved
  get '/request_password_reset' do
    return erb :request_password_reset
  end

  # TODO: Remove once /reset_password route gets moved
  post '/request_password_reset' do
    @email = params[:email]

    if (@email.nil?)
      return erb :request_password_reset
    end

    @email.downcase!

    user = User.first(:email => @email)

    if user.nil?
      # This behavior might change in the future.
      # For now, just act like invalid requests went through.
      return erb :request_password_reset_success
    end

    reset_request = PasswordResetRequest.create(:email => @email)

    @reset_url = ::URI.join(app_settings['site_url'], '/reset_password').to_s +
        ::URI::encode_www_form([["email", user.email], ["code", reset_request.code]])

    @site_url = app_settings['site_url']

    template_locals = {
      :site_url => @site_url,
      :reset_url => @reset_url,
      :display_name => user.display_name
    }

    EmailJob.create(:to => @email,
                    :subject => "#{@site_url} - Password Reset",
                    :body => erb(:'email/reset_request', :locals => template_locals))

    return erb :request_password_reset_success
  end


  get '/reset_password' do
    @email = params[:email]
    @code = params[:code]

    if (@email.nil? || @code.nil?)
      return redirect to('/request_password_reset')
    end

    reset_request = PasswordResetRequest.first(:email => @email, :code => @code)
    if (reset_request.nil?)
      redirect to('/request_password_reset')
    else
      erb :reset_password
    end
  end

  post '/reset_password' do
    @email = params[:email].to_s.downcase
    @code = params[:code].to_s
    @new_password = params[:password].to_s
    @confirm_new_password = params[:confirm_password].to_s
    
    reset_request = PasswordResetRequest.first(:email => @email, :code => @code)
    if (reset_request.nil?)
      # /reset_password view has an error in it
      return 500
    end

    user = User.first(:email => @email)
    if (user.nil?)
      return 500
    end

    if (@email.empty? || @code.empty? ||
        @new_password.empty? || @new_password != @confirm_new_password)
      # Something's wrong; it's likely an invalid password
      flash.now[:error] = true
      return erb :reset_password
    end

    # Update password
    user.password = @new_password
    user.save()

    # Send e-mail notification later
    @site_url = app_settings['site_url']

    template_locals = {
      :display_name => user.display_name,
      :site_url => @site_url
    }

    EmailJob.create(:to => @email,
                    :subject => "#{@site_url} - Password Reset Successful",
                    :body => erb(:'email/password_changed', :locals => template_locals))

    # Delete requests for reset
    PasswordResetRequest.where(:email => @email).delete()

    @display_name = user.display_name
    return erb :reset_password_success
  end
end
