require 'fileutils'
require 'rspec'
require 'factory_girl'
require './models.rb'

RSpec.configure do |c|
  FactoryGirl.find_definitions
  Models::User.where().delete()
  Models::Bet.where().delete()
  Models::EmailJob.where().delete
  FileUtils.rm(['tmp/test/match_data.json', 'tmp/test/match_open'],
             force: true)
end

