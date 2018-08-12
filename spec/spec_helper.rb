require 'simplecov'
SimpleCov.start
require 'fileutils'
require 'rspec'
require 'factory_bot'
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
    Models::User.dataset.delete()
    Models::Bet.dataset.delete()
    Models::EmailJob.dataset.delete()
    Models::PasswordResetRequest.dataset.delete()
    FileUtils.rm(['tmp/test/match_data.json', 'tmp/test/match_open'],
                 force: true)
  end

  c.include FactoryBot::Syntax::Methods

  c.before(:suite) do
    FactoryBot.find_definitions
    cleanup.call()
  end
   
  c.after(:all) do
    cleanup.call()
  end
end

