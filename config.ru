if ENV['RACK_ENV'].nil?
  ENV['RACK_ENV'] = 'development'
end

require 'bundler'
Bundler.require

require './apps/main.rb'
require './apps/angular.rb'

Thread.abort_on_exception=true

map "/" do
 run MainApp
end 

map "/angular/" do
    run AngularTemplateApp
end

