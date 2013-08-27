ENV['RACK_ENV'] = 'test'
Thread.abort_on_exception=true

require 'yaml'
require 'json'
require 'rspec'
require 'rack/test'
require 'sequel'
require 'factory_girl'
require './app.rb'
require './models.rb'
require './persistence.rb'
require 'spec_helper'

describe 'Main App' do
  include Rack::Test::Methods
  include Models

  def app
    RootApp
  end

  it "has a working index page" do
    get '/'
    last_response.should be_ok
  end

  it "has a working login page" do
    get '/login'
    last_response.should be_ok
  end

  it "has a working signup page" do
    get '/signup'
    last_response.should be_ok
  end

  it "allows users to login" do
    user = FactoryGirl.create(:user)

    # Sign-in
    post '/login', {
      email: user.email,
      password: user.password
    }

    last_response.should be_redirect

    # Try a route requiring login
    get '/api/account'
    last_response.should be_ok

  end

  it "doesn't explode for failed login attempts" do
    user = FactoryGirl.build(:user) # Do not save

    # Sign-in
    post '/login', {
      email: user.email,
      password: user.password
    }

    last_response.should be_redirect

    # Try a route requiring login
    get '/api/account'
    last_response.should_not be_ok

  end

  it "allows users to signup" do
    user_info = FactoryGirl.attributes_for(:user)
    post '/signup', {
      email: user_info[:email],
      password: user_info[:password],
      confirm_password: user_info[:password],
      display_name: user_info[:display_name]
    }

    last_response.should be_redirect

    User.where(email:user_info[:email].downcase).count.should == 1
    EmailJob.where(to: user_info[:email].downcase).count.should == 1

    # Try a route requiring login
    get '/api/account'
    last_response.should be_ok

    # Check to see if starting balance == 400
    new_user = User.first(email:user_info[:email].downcase)
    new_user.should_not == nil
    new_user.balance.should == 400
  end

  it "should not allow /api/account access to anon users" do
    get '/api/account'
    last_response.status.should == 500
    expect(last_response.content_type.include?('application/json')).to be_true
  end

  it "should not allow /api/current_match access to anon users" do
    match_data = {
      status: 'closed',
      winner: '',
      participantA: { name: 'Player A', amount: 0 },
      participantB: { name: 'Player B', amount: 0 },
      odds: ''
    }.to_json

    put '/api/current_match', match_data
    last_response.status.should == 500
    last_response.body.should == "{ error: 'Must be logged-in'}"
  end

  it "should not allow /api/current_match access to non-admin users" do
    # Create User
    user = FactoryGirl.create(:user)
    
    # Sign-in
    post '/login', {
      email: user.email,
      password: user.password
    }

    last_response.should be_redirect

    header "Content-Type", "application/json"

    match_data = {
      status: 'closed',
      winner: '',
      participantA: { name: 'Player A', amount: 0 },
      participantB: { name: 'Player B', amount: 0 },
      odds: ''
    }.to_json

    put '/api/current_match', match_data
    last_response.status.should == 500
    last_response.body.should == "{ error: 'invalid request'}"
  end

  it "allows people to bet their fake money - test #1" do
    # Reset match data
    Persistence::MatchStatusPersistence.save_file({
      :status => 'closed',
      :winner => '',
      :participantA => { :name => '', :amount => 0},
      :participantB => { :name => '', :amount => 0},
      :odds => '',
    })

    Persistence::MatchStatusPersistence.close_bids

    Bet.count.should == 0

    # Create users
    admin = FactoryGirl.create(:admin)
    loser = FactoryGirl.create(:user, balance: 21)
    winner = FactoryGirl.create(:user, balance:10)
 
    loser_browser = Rack::Test::Session.new(Rack::MockSession.new(app))
    winner_browser = Rack::Test::Session.new(Rack::MockSession.new(app))

    # User login
    post '/login', {
      email: admin.email,
      password: admin.password
    }

    loser_browser.post '/login', {
      email: loser.email,
      password: loser.password
    }

    winner_browser.post '/login', {
      email: winner.email,
      password: winner.password
    }

    # Open bidding
    put '/api/current_match', {
      :status => 'open',
      :winner => '',
      :participantA => { :name => 'A', :amount => 0},
      :participantB => { :name => 'B', :amount => 0},
      :odds => '',
    }.to_json

    last_response.should be_ok

    # Bid - loser will bet 10 on B
    loser_browser.post '/api/bet', {
      'forParticipant' => 'b',
      :amount => 10
    }.to_json

    loser_browser.last_response.should be_ok

    # Bid - winner will bet 1 on A
    winner_browser.post '/api/bet', {
      'forParticipant' => 'a',
      :amount => 1
    }.to_json

    winner_browser.last_response.should be_ok

    # Close bidding
    put '/api/current_match', {
      :status => 'inProgress',
      :winner => '',
      :participantA => { :name => 'A', :amount => 0},
      :participantB => { :name => 'B', :amount => 0},
      :odds => '',
    }.to_json

    last_response.should be_ok

    # Ensure that odds & amount are calculated
    match_data_after_close = Persistence::MatchStatusPersistence.get_from_file

    match_data_after_close['participantA']['amount'].to_f.should == 1.0
    match_data_after_close['participantB']['amount'].to_f.should == 10.0
    match_data_after_close['odds'].should == "1:10"

    # TODO: Change after adding user functionality to show 'all bettors'
    match_data_after_close['bettors']['a'].should == []
    match_data_after_close['bettors']['b'].should == []

    Bet.count.should == 2

    # End match - admin client data needs to updated to
    # include bid amounts & odds
    put '/api/current_match', {
      :status => 'payout',
      :winner => 'a',
      :participantA => match_data_after_close['participantA'],
      :participantB => match_data_after_close['participantB'],
      :odds => match_data_after_close['odds'],
    }.to_json

    # Payout is async
    sleep_count = 0
    while Bet.count > 0
      sleep(1)
      sleep_count += 1
      sleep_count.should < 20 # Payout is bugged
    end

    # Check match data
    match_data_after_payout = Persistence::MatchStatusPersistence.get_from_file

    match_data_after_payout['status'].should == 'closed'

    # Check payout amounts
    User.first(email: loser.email).balance.to_i.should == 11
    User.first(email: winner.email).balance.to_i.should == 20

    Bet.count.should == 0
  end

  # This an alternate 'simulate match' test that includes additional
  # tests for the following:
  # - 'Change bet' functionality
  # - 'Cannot bet after betting closes' functionality
  it "allows people to bet their fake money - test #2" do
    # Reset match data
    Persistence::MatchStatusPersistence.save_file({
      :status => 'closed',
      :winner => '',
      :participantA => { :name => '', :amount => 0},
      :participantB => { :name => '', :amount => 0},
      :odds => '',
    })

    Persistence::MatchStatusPersistence.close_bids

    Bet.count.should == 0

    # Create users
    admin = FactoryGirl.create(:admin)
    loser = FactoryGirl.create(:user, balance: 5)
    winner = FactoryGirl.create(:user, balance: 500)

    loser_browser = Rack::Test::Session.new(Rack::MockSession.new(app))
    winner_browser = Rack::Test::Session.new(Rack::MockSession.new(app))

    # User login
    post '/login', {
      email: admin.email,
      password: admin.password
    }

    loser_browser.post '/login', {
      email: loser.email,
      password: loser.password
    }

    winner_browser.post '/login', {
      email: winner.email,
      password: winner.password
    }

    # Open bidding
    put '/api/current_match', {
      :status => 'open',
      :winner => '',
      :participantA => { :name => 'A', :amount => 0},
      :participantB => { :name => 'B', :amount => 0},
      :odds => '',
    }.to_json

    last_response.should be_ok

    # Bid - loser will initially bet 5 on B
    loser_browser.post '/api/bet', {
      'forParticipant' => 'b',
      :amount => 5
    }.to_json

    loser_browser.last_response.should be_ok
    
    # Bid - winner will bet 500 on B
    winner_browser.post '/api/bet', {
      'forParticipant' => 'b',
      :amount => 500
    }.to_json

    winner_browser.last_response.should be_ok

    # Bid - loser will change bid to 5 on A
    loser_browser.post '/api/bet', {
      'forParticipant' => 'a',
      :amount => 5
    }.to_json

    loser_browser.last_response.should be_ok

    # Close bidding
    put '/api/current_match', {
      :status => 'inProgress',
      :winner => '',
      :participantA => { :name => 'A', :amount => 0},
      :participantB => { :name => 'B', :amount => 0},
      :odds => '',
    }.to_json

    last_response.should be_ok

    # Ensure that odds & amount are calculated
    match_data_after_close = Persistence::MatchStatusPersistence.get_from_file

    match_data_after_close['participantA']['amount'].to_f.should == 5.0
    match_data_after_close['participantB']['amount'].to_f.should == 500.0
    match_data_after_close['odds'].should == "1:100"

    # TODO: Change after adding user functionality to show 'all bettors'
    match_data_after_close['bettors']['a'].should == [loser.display_name]
    match_data_after_close['bettors']['b'].should == [winner.display_name]

    Bet.count.should == 2

    # Testing 'cannot bid after deadline' functionality
    winner_browser.post '/api/bet', {
      'forParticipant' => 'b',
      :amount => 499
    }.to_json

    winner_browser.last_response.should_not be_ok


    # End match - admin client data needs to updated to
    # include bid amounts & odds
    put '/api/current_match', {
      :status => 'payout',
      :winner => 'b',
      :participantA => match_data_after_close['participantA'],
      :participantB => match_data_after_close['participantB'],
      :odds => match_data_after_close['odds'],
    }.to_json

    # Payout is async
    sleep_count = 0
    while Bet.count > 0
      sleep(1)
      sleep_count += 1
      sleep_count.should < 20 # Payout is bugged
    end

    # Check match data
    match_data_after_payout = Persistence::MatchStatusPersistence.get_from_file

    match_data_after_payout['status'].should == 'closed'

    # Check payout amounts
    User.first(email: loser.email).balance.to_i.should == 10 # reset
    User.first(email: winner.email).balance.to_i.should == 505

    Bet.count.should == 0
  end

  it "allows match cancellation during match" do
    # Reset match data
    Persistence::MatchStatusPersistence.save_file({
      :status => 'closed',
      :winner => '',
      :participantA => { :name => '', :amount => 0},
      :participantB => { :name => '', :amount => 0},
      :odds => '',
    })

    Persistence::MatchStatusPersistence.close_bids

    Bet.count.should == 0

    # Create users
    admin = FactoryGirl.create(:admin)
    loser = FactoryGirl.create(:user, balance: 5)
    winner = FactoryGirl.create(:user, balance: 500)

    loser_browser = Rack::Test::Session.new(Rack::MockSession.new(app))
    winner_browser = Rack::Test::Session.new(Rack::MockSession.new(app))

    # User login
    post '/login', {
      email: admin.email,
      password: admin.password
    }

    loser_browser.post '/login', {
      email: loser.email,
      password: loser.password
    }

    winner_browser.post '/login', {
      email: winner.email,
      password: winner.password
    }

    # Open bidding
    put '/api/current_match', {
      :status => 'open',
      :winner => '',
      :participantA => { :name => 'A', :amount => 0},
      :participantB => { :name => 'B', :amount => 0},
      :odds => '',
    }.to_json

    last_response.should be_ok

    # Bid - loser will bet 5 on A
    loser_browser.post '/api/bet', {
      'forParticipant' => 'a',
      :amount => 5
    }.to_json

    loser_browser.last_response.should be_ok

    # Bid - winner will bet 500 on B
    winner_browser.post '/api/bet', {
      'forParticipant' => 'b',
      :amount => 500
    }.to_json

    winner_browser.last_response.should be_ok

    # Close bidding
    put '/api/current_match', {
      :status => 'inProgress',
      :winner => '',
      :participantA => { :name => 'A', :amount => 0},
      :participantB => { :name => 'B', :amount => 0},
      :odds => '',
    }.to_json

    last_response.should be_ok

    # Ensure that odds & amount are calculated
    match_data_after_close = Persistence::MatchStatusPersistence.get_from_file

    match_data_after_close['participantA']['amount'].to_f.should == 5.0
    match_data_after_close['participantB']['amount'].to_f.should == 500.0
    match_data_after_close['odds'].should == "1:100"

    # TODO: Change after adding user functionality to show 'all bettors'
    match_data_after_close['bettors']['a'].should == [loser.display_name]
    match_data_after_close['bettors']['b'].should == [winner.display_name]

    # Cancel match - admin client data needs to updated to
    # include bid amounts & odds
    put '/api/current_match', {
      :status => 'closed',
      :winner => 'b',
      :participantA => match_data_after_close['participantA'],
      :participantB => match_data_after_close['participantB'],
      :odds => match_data_after_close['odds'],
    }.to_json

    # Payout is async
    match_data_after_cancel = Persistence::MatchStatusPersistence.get_from_file

    match_data_after_cancel['status'].should == 'closed'

    # Check payout amounts to ensure that there is no payout
    User.first(email: loser.email).balance.to_i.should == 5
    User.first(email: winner.email).balance.to_i.should == 500

    Bet.count.should == 0
  end

  it "allows match cancellation during betting" do
    # Reset match data
    Persistence::MatchStatusPersistence.save_file({
      :status => 'closed',
      :winner => '',
      :participantA => { :name => '', :amount => 0},
      :participantB => { :name => '', :amount => 0},
      :odds => '',
    })

    Persistence::MatchStatusPersistence.close_bids

    Bet.count.should == 0

    # Create users
    admin = FactoryGirl.create(:admin)
    loser = FactoryGirl.create(:user, balance: 5)
    winner = FactoryGirl.create(:user, balance: 500)

    loser_browser = Rack::Test::Session.new(Rack::MockSession.new(app))
    winner_browser = Rack::Test::Session.new(Rack::MockSession.new(app))

    # User login
    post '/login', {
      email: admin.email,
      password: admin.password
    }

    loser_browser.post '/login', {
      email: loser.email,
      password: loser.password
    }

    winner_browser.post '/login', {
      email: winner.email,
      password: winner.password
    }

    # Open bidding
    put '/api/current_match', {
      :status => 'open',
      :winner => '',
      :participantA => { :name => 'A', :amount => 0},
      :participantB => { :name => 'B', :amount => 0},
      :odds => '',
    }.to_json

    last_response.should be_ok

    # Bid - loser will bet 5 on A
    loser_browser.post '/api/bet', {
      'forParticipant' => 'a',
      :amount => 5
    }.to_json

    loser_browser.last_response.should be_ok

    # Bid - winner will bet 500 on B
    winner_browser.post '/api/bet', {
      'forParticipant' => 'b',
      :amount => 500
    }.to_json

    winner_browser.last_response.should be_ok

    # Cancel bidding
    put '/api/current_match', {
      :status => 'closed',
      :winner => '',
      :participantA => { :name => 'A', :amount => 0},
      :participantB => { :name => 'B', :amount => 0},
      :odds => '',
    }.to_json

    last_response.should be_ok

    match_data_after_cancel = Persistence::MatchStatusPersistence.get_from_file

    match_data_after_cancel['status'].should == 'closed'

    # Check payout amounts to ensure that there is no payout
    User.first(email: loser.email).balance.to_i.should == 5
    User.first(email: winner.email).balance.to_i.should == 500

    Bet.count.should == 0
  end

  it "allows people to have matches with no one betting" do
    # Reset match data
    Persistence::MatchStatusPersistence.save_file({
      :status => 'closed',
      :winner => '',
      :participantA => { :name => '', :amount => 0},
      :participantB => { :name => '', :amount => 0},
      :odds => '',
    })

    Persistence::MatchStatusPersistence.close_bids

    Bet.count.should == 0

    # Create users
    admin = FactoryGirl.create(:admin)
    
    # User login
    post '/login', {
      email: admin.email,
      password: admin.password
    }

    # Open bidding
    put '/api/current_match', {
      :status => 'open',
      :winner => '',
      :participantA => { :name => 'A', :amount => 0},
      :participantB => { :name => 'B', :amount => 0},
      :odds => '',
    }.to_json

    last_response.should be_ok

    # Close bidding
    put '/api/current_match', {
      :status => 'inProgress',
      :winner => '',
      :participantA => { :name => 'A', :amount => 0},
      :participantB => { :name => 'B', :amount => 0},
      :odds => '',
    }.to_json

    last_response.should be_ok

    # Ensure that odds & amount are calculated
    match_data_after_close = Persistence::MatchStatusPersistence.get_from_file

    match_data_after_close['participantA']['amount'].to_f.should == 0
    match_data_after_close['participantB']['amount'].to_f.should == 0.0
    match_data_after_close['odds'].should == "0:0"

    # TODO: Change after adding user functionality to show 'all bettors'
    match_data_after_close['bettors']['a'].should == []
    match_data_after_close['bettors']['b'].should == []

    Bet.count.should == 0

    # End match - admin client data needs to updated to
    # include bid amounts & odds
    put '/api/current_match', {
      :status => 'payout',
      :winner => 'a',
      :participantA => match_data_after_close['participantA'],
      :participantB => match_data_after_close['participantB'],
      :odds => match_data_after_close['odds'],
    }.to_json

    # Payout is async, but in this case, it' an expensive no-op
    sleep(1)
    
    # Check match data
    match_data_after_payout = Persistence::MatchStatusPersistence.get_from_file

    match_data_after_payout['status'].should == 'closed'

    # Check payout amounts
    Bet.count.should == 0
  end

  it "allows people to have one-sided matches for winner" do
    # Reset match data
    Persistence::MatchStatusPersistence.save_file({
      :status => 'closed',
      :winner => '',
      :participantA => { :name => '', :amount => 0},
      :participantB => { :name => '', :amount => 0},
      :odds => '',
    })

    Persistence::MatchStatusPersistence.close_bids

    Bet.count.should == 0

    # Create users
    admin = FactoryGirl.create(:admin)
    user = FactoryGirl.create(:user, balance: 2525)
    
    user_browser = Rack::Test::Session.new(Rack::MockSession.new(app))

    # User login
    post '/login', {
      email: admin.email,
      password: admin.password
    }

    user_browser.post '/login', {
      email: user.email,
      password: user.password
    }
    
    # Open bidding
    put '/api/current_match', {
      :status => 'open',
      :winner => '',
      :participantA => { :name => 'A', :amount => 0},
      :participantB => { :name => 'B', :amount => 0},
      :odds => '',
    }.to_json

    last_response.should be_ok

    # Bid - User-5 will bet 10 on A
    user_browser.post '/api/bet', {
      'forParticipant' => 'a',
      :amount => 10
    }.to_json

    user_browser.last_response.should be_ok
    
    # Close bidding
    put '/api/current_match', {
      :status => 'inProgress',
      :winner => '',
      :participantA => { :name => 'A', :amount => 0},
      :participantB => { :name => 'B', :amount => 0},
      :odds => '',
    }.to_json

    last_response.should be_ok

    # Ensure that odds & amount are calculated
    match_data_after_close =  Persistence::MatchStatusPersistence.get_from_file

    match_data_after_close['participantA']['amount'].to_f.should == 10.0
    match_data_after_close['participantB']['amount'].to_f.should == 0.0
    match_data_after_close['odds'].should == "0:0"

    # TODO: Change after adding user functionality to show 'all bettors'
    match_data_after_close['bettors']['a'].should == []
    match_data_after_close['bettors']['b'].should == []

    Bet.count.should == 1

    # End match - admin client data needs to updated to
    # include bid amounts & odds
    put '/api/current_match', {
      :status => 'payout',
      :winner => 'a',
      :participantA => match_data_after_close['participantA'],
      :participantB => match_data_after_close['participantB'],
      :odds => match_data_after_close['odds'],
    }.to_json

    ## Payout is async, but in this case, it' an expensive no-op
    sleep(1)

    # Check match data
    match_data_after_payout = Persistence::MatchStatusPersistence.get_from_file

    match_data_after_payout['status'].should == 'closed'

    # There should be no payout
    User.first(email: user.email).balance.to_i.should == 2525

    Bet.count.should == 0
  end

  # Test covering an issue where ZeroDivisionError was thrown from the
  # payout thread
  it "allows people to have one-sided matches for loser" do
    # Reset match data
    Persistence::MatchStatusPersistence.save_file({
      :status => 'closed',
      :winner => '',
      :participantA => { :name => '', :amount => 0},
      :participantB => { :name => '', :amount => 0},
      :odds => '',
    })

    Persistence::MatchStatusPersistence.close_bids

    Bet.count.should == 0

    # Create users
    admin = FactoryGirl.create(:admin)
    user = FactoryGirl.create(:user, balance: 2525)
    
    user_browser = Rack::Test::Session.new(Rack::MockSession.new(app))

    # User login
    post '/login', {
      email: admin.email,
      password: admin.password
    }

    user_browser.post '/login', {
      email: user.email,
      password: user.password
    }
    
    # Open bidding
    put '/api/current_match', {
      :status => 'open',
      :winner => '',
      :participantA => { :name => 'A', :amount => 0},
      :participantB => { :name => 'B', :amount => 0},
      :odds => '',
    }.to_json

    last_response.should be_ok

    # Bid - User-5 will bet 10 on A
    user_browser.post '/api/bet', {
      'forParticipant' => 'a',
      :amount => 10
    }.to_json

    user_browser.last_response.should be_ok
    
    # Close bidding
    put '/api/current_match', {
      :status => 'inProgress',
      :winner => '',
      :participantA => { :name => 'A', :amount => 0},
      :participantB => { :name => 'B', :amount => 0},
      :odds => '',
    }.to_json

    last_response.should be_ok

    # Ensure that odds & amount are calculated
    match_data_after_close =  Persistence::MatchStatusPersistence.get_from_file

    match_data_after_close['participantA']['amount'].to_f.should == 10.0
    match_data_after_close['participantB']['amount'].to_f.should == 0.0
    match_data_after_close['odds'].should == "0:0"

    # TODO: Change after adding user functionality to show 'all bettors'
    match_data_after_close['bettors']['a'].should == []
    match_data_after_close['bettors']['b'].should == []

    Bet.count.should == 1

    # End match - admin client data needs to updated to
    # include bid amounts & odds
    put '/api/current_match', {
      :status => 'payout',
      :winner => 'b',
      :participantA => match_data_after_close['participantA'],
      :participantB => match_data_after_close['participantB'],
      :odds => match_data_after_close['odds'],
    }.to_json

    ## Payout is async, but in this case, it' an expensive no-op
    sleep(1)

    # Check match data
    match_data_after_payout = Persistence::MatchStatusPersistence.get_from_file

    match_data_after_payout['status'].should == 'closed'

    # There should be no payout
    User.first(email: user.email).balance.to_i.should == 2525

    Bet.count.should == 0
  end

  it "does not allow non-positive integer bet amounts" do
    # Reset match data
    Persistence::MatchStatusPersistence.save_file({
      :status => 'closed',
      :winner => '',
      :participantA => { :name => '', :amount => 0},
      :participantB => { :name => '', :amount => 0},
      :odds => '',
    })

    Persistence::MatchStatusPersistence.close_bids

    Bet.count.should == 0

    # Create users
    admin = FactoryGirl.create(:admin)
    user = FactoryGirl.create(:user, balance: 50)

    user_browser = Rack::Test::Session.new(Rack::MockSession.new(app))

    # User login
    post '/login', {
      email: admin.email,
      password: admin.password
    }

    user_browser.post '/login', {
      email: user.email,
      password: user.password
    }

    # Open bidding
    put '/api/current_match', {
      :status => 'open',
      :winner => '',
      :participantA => { :name => 'A', :amount => 0},
      :participantB => { :name => 'B', :amount => 0},
      :odds => '',
    }.to_json

    last_response.should be_ok

    # Invalid Bet: zero
    user_browser.post '/api/bet', {
      'forParticipant' => 'a',
      :amount => 0
    }.to_json

    user_browser.last_response.should_not be_ok
    user_browser.last_response.body.should include('amount must be a positive integer')

    # Invalid Bet: negative integer
    user_browser.post '/api/bet', {
      'forParticipant' => 'a',
      :amount => -1
    }.to_json

    user_browser.last_response.should_not be_ok
    user_browser.last_response.body.should include('amount must be a positive integer')

    # Invalid Bet: negative float
    user_browser.post '/api/bet', {
      'forParticipant' => 'a',
      :amount => -1.00001
    }.to_json

    user_browser.last_response.should_not be_ok
    user_browser.last_response.body.should include('amount must be a positive integer')

    # Invalid Bet: positive float
    user_browser.post '/api/bet', {
      'forParticipant' => 'a',
      :amount => 1.00001
    }.to_json

    user_browser.last_response.should_not be_ok
    user_browser.last_response.body.should include('amount must be a positive integer')

    # Invalid Bet: over account balance
    user_browser.post '/api/bet', {
      'forParticipant' => 'a',
      :amount => 51
    }.to_json

    user_browser.last_response.should_not be_ok
    user_browser.last_response.body.should include('insufficient funds')

    # Invalid Bet: invalid forParticipantValue
    user_browser.post '/api/bet', {
      'forParticipant' => 'c',
      :amount => 50
    }.to_json

    user_browser.last_response.should_not be_ok
    user_browser.last_response.body.should include('invalid request')

    # Cancel bidding
    put '/api/current_match', {
      :status => 'closed',
      :winner => '',
      :participantA => { :name => 'A', :amount => 0},
      :participantB => { :name => 'B', :amount => 0},
      :odds => '',
    }.to_json

    last_response.should be_ok

    User.first(email: user.email).balance.to_i.should == 50
  end
end

