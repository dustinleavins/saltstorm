# Saltstorm - Fun-Money Betting on the Web
# Copyright (C) 2013, 2014  Dustin Leavins
#
# Full license can be found in 'LICENSE.txt'
require 'uri'
require 'cgi'
require 'json'
require 'rubygems'
require 'bundler'
Bundler.require
require 'sinatra/asset_pipeline'
require './apps/helpers.rb'
require './models.rb'
require './persistence.rb'
require './settings.rb'
include Models

class MainApp < Sinatra::Base
  app_settings = Settings::site(settings.environment.to_s)
  
  configure do
    set :views, 'views/' 
    set :static_cache_control, [:private]
    set :public_folder, './public/'

    enable :sessions
    register Sinatra::Flash
    set :session_secret, Settings::secret_token

    register Sinatra::AssetPipeline

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
    return erb :index
  end
 
  get '/login' do
    return erb :login
  end

  post '/login' do
    auth_ok = authenticate(params[:email], params[:password])

    if (auth_ok && params[:mobile])
      redirect to('/main_mobile')
    elsif (auth_ok)
      redirect to('/main')
    else
      flash.next[:error] = true
      redirect to('/login'), 303
    end
  end

  get '/signup' do
    return erb :signup
  end

  post '/signup' do
    @email = CGI::escapeHTML(params[:email].downcase)
    password = params[:password]
    confirm_password = params[:confirm_password]
    @display_name = CGI::escapeHTML(params[:display_name])
    balance = app_settings['user_signup_balance']

    if (password != confirm_password)
      flash.now[:error] = { :password => true }
      return erb :signup
    elsif (User.where(:email => @email).count > 0)
      flash.now[:error] = { :email_not_unique => true }
      return erb :signup
    elsif (User.where(:display_name => @display_name).count > 0)
      flash.now[:error] = { :display_name_not_unique => true }
      return erb :signup
    end

    user = User.new(:email => @email,
                    :password => password,
                    :display_name => @display_name,
                    :balance => balance)

    if (!user.valid?)
      flash.now[:error] = user.errors
      return erb :signup
    end

    user.save()

    # Send the introductory e-mail at a later time
    site_url = app_settings['site_url']
    template_locals = {
      :site_url => site_url,
      :display_name => user.display_name,
      :email => user.email,
      :balance => user.balance 
    }

    EmailJob.create(:to => @email,
                    :subject => "Welcome to #{site_url}!",
                    :body => erb(:'email/intro', :locals => template_locals))

    session[:uid] = user.id 
    return redirect to('/main')
  end

  get '/request_password_reset' do
    return erb :request_password_reset
  end

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

  get '/logout' do
    session[:uid] = nil
    return redirect to('/')
  end

  get '/main' do
    if (!is_authenticated?)
      return redirect '/login', 303
    end

    @video_link = app_settings['main_video_html']
    @bettors_strategy = app_settings['bettors_show']
    return erb :main_page
  end

  get '/main_mobile' do
    if (!is_authenticated?)
      return redirect '/login', 303
    end

    return erb :main_page_mobile
  end

  get '/account' do
    redirect to('/account/')
  end

  get '/account/' do
    if (!is_authenticated?)
      return redirect '/login', 303
    end

    user = User.first(:id => session[:uid])
    if (user.nil?)
      return redirect '/login', 303
    end

    @original = {
      :display_name => CGI::escapeHTML(user.display_name),
      :email => CGI::escapeHTML(user.email),
      :post_url => CGI::escapeHTML(user.post_url.to_s) # post_url might be nil
    }

    @current = flash[:current] || @original
    erb :account
  end

  post '/account/info' do
    if (!is_authenticated?)
      return redirect '/login', 303
    end

    user = User.first(:id => session[:uid])
    if (user.nil?)
      return redirect '/login', 303
    end

    # Check password
    password = params[:password].to_s
    password_hash = User.generate_password_digest(password, user.password_salt)

    flash.next[:current] = {
      :display_name => CGI::escapeHTML(params[:display_name].to_s),
      :email => CGI::escapeHTML(params[:email].to_s),
      :post_url => CGI::escapeHTML(params[:post_url].to_s)
    }

    if (user.password_hash != password_hash)
      flash.next[:info] = { :error => {:password => true } }
      return redirect to('/account/')
    end

    user.display_name = flash.next[:current][:display_name]
    user.email = flash.next[:current][:email]
    user.post_url = flash.next[:current][:post_url]

    if (!user.valid?)
      error_info = {
        :display_name =>  !(user.errors[:display_name].nil?),
        :email =>  !(user.errors[:email].nil?),
        :post_url => !(user.errors[:post_url].nil?)
      }

      flash.next[:info] = { :error => error_info }

      redirect to('/account/')
    end

    user.save()

    flash.next[:info] = { :success => true }
    redirect to('/account/') 
  end

  post '/account/password' do
    if (!is_authenticated?)
      return redirect '/login', 303
    end

    user = User.first(:id => session[:uid])
    if (user.nil?)
      return redirect '/login', 303
    end

    password = params[:password].to_s
    confirm_password = params[:confirm_password].to_s

    if (password.empty? || password != confirm_password)
      flash.next[:password] = { :error => true }
      return redirect to('/account/')
    end

    user.password = password
    user.save()

    flash.next[:password] = { :success => true }
    return redirect to('/account/')
  end

  get '/payments' do
    if (!is_authenticated?)
      return redirect '/login', 303
    end

    user = User.first(:id => session[:uid])
    if (user.nil?)
      return redirect '/login', 303
    end

    @current_rank = user.rank
    @max_rank = app_settings['rankup']['max_rank']

    if (@current_rank == @max_rank)
      @next_rank_amount = nil # should be unused
    elsif (app_settings['rankup']['amounts'].length < (@current_rank + 1))
      @next_rank_amount = app_settings['rankup']['amounts'].last
    else
      @next_rank_amount = app_settings['rankup']['amounts'][@current_rank]
    end

    erb :payments
  end
end
