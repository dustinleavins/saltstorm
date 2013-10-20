require 'simplecov'
SimpleCov.start
require 'fileutils'
require 'rspec'
require 'factory_girl'
require './models.rb'

module Helpers
  def reset_match_data
    Persistence::MatchStatusPersistence.save_file({
      :status => 'closed',
      :winner => '',
      :participants => {
          'a' => { :name => '', :amount => 0, :odds => ''},
          'b' => { :name => '', :amount => 0, :odds => ''}
      },
      :message => '',
      :bettors => {
          :a => [],
          :b => [] 
      }
    })

    Persistence::MatchStatusPersistence.close_bids
  end
end

RSpec.configure do |c|
  c.include Helpers

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

