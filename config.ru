if ENV['RACK_ENV'].nil?
  ENV['RACK_ENV'] = 'development'
end

require 'bundler'
Bundler.require

require './app.rb'
require './angular.rb'

Thread.abort_on_exception=true

map "/" do
 run RootApp
end 

map "/angular/" do
    run AngularTemplateApp
end

