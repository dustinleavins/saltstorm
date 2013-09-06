require 'simplecov'

SimpleCov.start
require 'fileutils'
require 'rspec'
require 'factory_girl'
require './models.rb'

RSpec.configure do |c|
  cleanup = -> do
    Models::User.where().delete()
    Models::Bet.where().delete()
    Models::EmailJob.where().delete()
    Models::PasswordResetRequest.where().delete()
    FileUtils.rm(['tmp/test/match_data.json', 'tmp/test/match_open'],
                 force: true)
  end

  FactoryGirl.find_definitions

  c.before(:suite) do
    cleanup.call()
  end
   
  c.after(:all) do
    cleanup.call()
  end
end

