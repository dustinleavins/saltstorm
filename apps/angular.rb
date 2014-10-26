# Saltstorm - Fun-Money Betting on the Web
# Copyright (C) 2013, 2014  Dustin Leavins
#
# Full license can be found in 'LICENSE.txt'
require 'uri'
require 'rubygems'
require 'bundler'
Bundler.require
require './apps/helpers.rb'

# Serves Angular templates
class AngularTemplateApp < Sinatra::Base
  app_settings = Settings::site(settings.environment.to_s)

  configure do
    set :views,  'views/angular' 
    helpers Helpers
  end

  configure :development, :production do
    enable :logging
  end

  before do
    cache_control :private
    @site_name = app_settings['site_name']
    @site_description = app_settings['site_description']
    @video_link = app_settings['main_video_html']
    @bettors_strategy = app_settings['bettors_show']
  end

  routes = ['index', 'bet_info', 'navbar', 'login',
            'request_password_reset', 'main', 'main_mobile',
            'logout', 'payments', 'register', 'manage_account']

  routes.each do |route|
    get '/' + route + '.html' do
      erb route.to_sym
    end
  end
end

