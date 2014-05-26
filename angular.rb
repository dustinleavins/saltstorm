# Saltstorm - Fun-Money Betting on the Web
# Copyright (C) 2013, 2014  Dustin Leavins
#
# Full license can be found in 'LICENSE.txt'
require 'rubygems'
require 'bundler'
Bundler.require

# Serves Angular templates
class AngularTemplateApp < Sinatra::Base
  app_settings = Settings::site(settings.environment.to_s)
  set :views, settings.root + '/views/angular' 

  configure :development, :production do
    enable :logging
  end

  get '/bet-info.html' do
    erb :bet_info
  end

  get '/navbar.html' do
    erb :navbar
  end
end
