ENV['RACK_ENV'] = 'test'
Thread.abort_on_exception=true

require 'yaml'
require 'json'
require 'uri'
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
    expect(last_response).to be_ok 
  end

  it "has a working login page" do
    get '/login'
    expect(last_response).to be_ok
  end

  it "has a working signup page" do
    get '/signup'
    expect(last_response).to be_ok
  end

  it "allows users to login" do
    user = FactoryGirl.create(:user)

    # Sign-in
    post '/login', {
      :email => user.email,
      :password => user.password
    }

    expect(last_response).to be_redirect

    # Try a route requiring login
    get '/api/account'
    expect(last_response).to be_ok
  end

  it "doesn't explode for failed login attempts" do
    user = FactoryGirl.build(:user) # Do not save

    # Sign-in
    post '/login', {
      :email => user.email,
      :password => user.password
    }

    expect(last_response).to be_redirect

    # Try a route requiring login
    get '/api/account'
    expect(last_response).not_to be_ok
  end

  it "allows users to signup" do
    user_info = FactoryGirl.attributes_for(:user)
    post '/signup', {
      :email => user_info[:email],
      :password => user_info[:password],
      confirm_password: user_info[:password],
      display_name: user_info[:display_name]
    }

    expect(last_response).to be_redirect

    expect(User.where(:email =>user_info[:email].downcase).count).to eq(1)
    expect(EmailJob.where(:to => user_info[:email].downcase).count).to eq(1)

    # Try a route requiring login
    get '/api/account'
    expect(last_response).to be_ok

    # Check to see if starting balance == 400
    new_user = User.first(:email => user_info[:email].downcase)
    expect(new_user).to_not be_nil
    expect(new_user.balance).to eq(400)
  end

  it "has a working 'request password reset' page" do
    get '/request_password_reset'
    expect(last_response).to be_ok
  end

  it "allows users to reset password" do
    user = FactoryGirl.create(:user)
    new_password = "password5"
    expect(user.password).to_not be_nil
    expect(new_password).to_not eq(user.password)

    # Request Reset
    post '/request_password_reset', {
      :email => user.email
    }

    expect(last_response).to be_ok
    expect(EmailJob.where(:to => user.email.downcase).count).to eq(1)
    expect(PasswordResetRequest.count(:email => user.email.downcase)).to eq(1)
    code = PasswordResetRequest.first(:email => user.email.downcase).code

    # GET reset page
    reset_password_url = "/reset_password?" + URI.encode_www_form([["email", user.email], ["code", code]])
    get reset_password_url
    expect(last_response).to be_ok

    # Reset
    post '/reset_password', {
      :email => user.email,
      :code => code,
      :password => new_password,
      :confirm_password => new_password
    }

    expect(last_response).to be_ok
    updated_user = User.first(:email => user.email)
    expect(updated_user.password_hash).to_not eq(user.password_hash)
    expect(updated_user.password_salt).to_not eq(user.password_salt)

    # Sign-in
    post '/login', {
      :email => updated_user.email,
      :password => 'password5'
    }

    expect(last_response).to be_redirect

    # Try a route requiring login
    get '/api/account'
    expect(last_response).to be_ok

    expect(EmailJob.where(:to => user.email.downcase).count).to eq(2)
    expect(PasswordResetRequest.count(:email => user.email.downcase)).to eq(0)
  end

  it "handles /request_password_reset errors" do
    invalid_email = FactoryGirl.attributes_for(:user)[:email]

    # Illegal - empty email field
    post '/request_password_reset', {
      :email => nil
    }

    expect(last_response).to be_ok
    expect(EmailJob.where(:to => '').count).to eq(0)
    expect(PasswordResetRequest.where(:email => '').count).to eq(0)

    # Illegal - non-registered user
    post '/request_password_reset', {
      :email => invalid_email
    }

    expect(last_response).to be_ok
    expect(EmailJob.where(:to => invalid_email.downcase).count).to eq(0)
    expect(PasswordResetRequest.where(:email => invalid_email.downcase).count).to eq(0)
  end

  it "handles /reset_password errors" do
    user = FactoryGirl.create(:user)

    # Request Reset
    post '/request_password_reset', {
      :email => user.email
    }

    expect(last_response).to be_ok
    # There's another test that checks to see if reset request is OK
    code = PasswordResetRequest.first(:email => user.email.downcase).code

    # Invalid GET - no params
    get "/reset_password"
    expect(last_response).to be_redirect

    # Invalid GET - no email
    get "/reset_password?#{URI.encode_www_form([["code", code]])}"
    expect(last_response).to be_redirect
    expect(PasswordResetRequest.count(:email => user.email.downcase)).to eq(1)

    # Invalid GET - no code
    get "/reset_password?#{URI.encode_www_form([["email", user.email]])}"
    expect(last_response).to be_redirect
    expect(PasswordResetRequest.count(:email => user.email.downcase)).to eq(1)

    # Invalid GET - wrong code
    get "/reset_password?#{URI.encode_www_form([['email', user.email], ['code', code.reverse]])}"
    expect(last_response).to be_redirect
    expect(PasswordResetRequest.count(:email => user.email.downcase)).to eq(1)

    # Invalid POST - no email
    post '/reset_password', {
      :code => code,
      :password => 'password',
      :confirm_password => 'password'
    }

    expect(last_response).to be_ok
    expect(PasswordResetRequest.count(:email => user.email.downcase)).to eq(1)

    # Invalid POST - no code
    post '/reset_password', {
      :email => user.email,
      :password => 'password',
      :confirm_password => 'password'
    }

    expect(last_response).to be_ok
    expect(PasswordResetRequest.count(:email => user.email.downcase)).to eq(1)

    # Invalid POST - password mismatch
    post '/reset_password', {
      :email => user.email,
      :code => code,
      :password => 'new password',
      :confirm_password => 'different password'
    }

    expect(last_response).to be_ok
    expect(PasswordResetRequest.count(:email => user.email.downcase)).to eq(1)
  end


  it "should not allow /api/account access to anon users" do
    get '/api/account'
    expect(last_response.status).to eq(500)
    expect(last_response.content_type.include?('application/json')).to be_true
  end

  it "should not allow /api/current_match access to anon users" do
    match_data = {
      :status => 'closed',
      :winner => '',
      :participantA => { :name => 'Player A', :amount => 0 },
      :participantB => { :name => 'Player B', :amount => 0 },
      :odds => ''
    }.to_json

    put '/api/current_match', match_data
    expect(last_response.status).to eq(500)
    expect(last_response.body).to eq("{ error: 'Must be logged-in'}")
  end

  it "should not allow /api/current_match access to non-admin users" do
    # Create User
    user = FactoryGirl.create(:user)
    
    # Sign-in
    post '/login', {
      :email => user.email,
      :password => user.password
    }

    expect(last_response).to be_redirect

    header "Content-Type", "application/json"

    match_data = {
      :status => 'closed',
      :winner => '',
      :participantA => { :name => 'Player A', :amount => 0 },
      :participantB => { :name => 'Player B', :amount => 0 },
      :odds => ''
    }.to_json

    put '/api/current_match', match_data
    expect(last_response.status).to eq(500)
    expect(last_response.body).to eq("{ error: 'invalid request'}")
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

    expect(Bet.count).to eq(0)

    # Create users
    admin = FactoryGirl.create(:admin)
    loser = FactoryGirl.create(:user, :balance => 21)
    winner = FactoryGirl.create(:user, :balance => 10)
 
    loser_browser = Rack::Test::Session.new(Rack::MockSession.new(app))
    winner_browser = Rack::Test::Session.new(Rack::MockSession.new(app))

    # User login
    post '/login', {
      :email => admin.email,
      :password => admin.password
    }

    loser_browser.post '/login', {
      :email => loser.email,
      :password => loser.password
    }

    winner_browser.post '/login', {
      :email => winner.email,
      :password => winner.password
    }

    # Open bidding
    put '/api/current_match', {
      :status => 'open',
      :winner => '',
      :participantA => { :name => 'A', :amount => 0},
      :participantB => { :name => 'B', :amount => 0},
      :odds => '',
    }.to_json

    expect(last_response).to be_ok

    # Bid - loser will bet 10 on B
    loser_browser.post '/api/bet', {
      'forParticipant' => 'b',
      :amount => 10
    }.to_json

    expect(loser_browser.last_response).to be_ok

    # Bid - winner will bet 1 on A
    winner_browser.post '/api/bet', {
      'forParticipant' => 'a',
      :amount => 1
    }.to_json

    expect(winner_browser.last_response).to be_ok

    # Close bidding
    put '/api/current_match', {
      :status => 'inProgress',
      :winner => '',
      :participantA => { :name => 'A', :amount => 0},
      :participantB => { :name => 'B', :amount => 0},
      :odds => '',
    }.to_json

    expect(last_response).to be_ok

    # Ensure that odds & amount are calculated
    match_data_after_close = Persistence::MatchStatusPersistence.get_from_file

    expect(match_data_after_close['participantA']['amount'].to_f).to eq(1.0)
    expect(match_data_after_close['participantB']['amount'].to_f).to eq(10.0)
    expect(match_data_after_close['odds']).to eq("1:10")

    # TODO: Change after adding user functionality to show 'all bettors'
    expect(match_data_after_close['bettors']['a']).to match_array([])
    expect(match_data_after_close['bettors']['b']).to match_array([])

    expect(Bet.count).to eq(2)

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
      expect(sleep_count).to be < 20 # Payout is bugged
    end

    # Check match data
    match_data_after_payout = Persistence::MatchStatusPersistence.get_from_file

    expect(match_data_after_payout['status']).to  eq('closed')

    # Check payout amounts
    expect(User.first(:email => loser.email).balance.to_i).to eq(11)
    expect(User.first(:email => winner.email).balance.to_i).to eq(20)

    expect(Bet.count).to eq(0)
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

    expect(Bet.count).to eq(0)

    # Create users
    admin = FactoryGirl.create(:admin)
    loser = FactoryGirl.create(:user, :balance => 5)
    winner = FactoryGirl.create(:user, :balance => 500)

    loser_browser = Rack::Test::Session.new(Rack::MockSession.new(app))
    winner_browser = Rack::Test::Session.new(Rack::MockSession.new(app))

    # User login
    post '/login', {
      :email => admin.email,
      :password => admin.password
    }

    loser_browser.post '/login', {
      :email => loser.email,
      :password => loser.password
    }

    winner_browser.post '/login', {
      :email => winner.email,
      :password => winner.password
    }

    # Open bidding
    put '/api/current_match', {
      :status => 'open',
      :winner => '',
      :participantA => { :name => 'A', :amount => 0},
      :participantB => { :name => 'B', :amount => 0},
      :odds => '',
    }.to_json

    expect(last_response).to be_ok

    # Bid - loser will initially bet 5 on B
    loser_browser.post '/api/bet', {
      'forParticipant' => 'b',
      :amount => 5
    }.to_json

    expect(loser_browser.last_response).to be_ok
    
    # Bid - winner will bet 500 on B
    winner_browser.post '/api/bet', {
      'forParticipant' => 'b',
      :amount => 500
    }.to_json

    expect(winner_browser.last_response).to be_ok

    # Bid - loser will change bid to 5 on A
    loser_browser.post '/api/bet', {
      'forParticipant' => 'a',
      :amount => 5
    }.to_json

    expect(loser_browser.last_response).to be_ok

    # Close bidding
    put '/api/current_match', {
      :status => 'inProgress',
      :winner => '',
      :participantA => { :name => 'A', :amount => 0},
      :participantB => { :name => 'B', :amount => 0},
      :odds => '',
    }.to_json

    expect(last_response).to be_ok

    # Ensure that odds & amount are calculated
    match_data_after_close = Persistence::MatchStatusPersistence.get_from_file

    expect(match_data_after_close['participantA']['amount'].to_f).to eq(5.0)
    expect(match_data_after_close['participantB']['amount'].to_f).to eq(500.0)
    expect(match_data_after_close['odds']).to eq("1:100")

    # TODO: Change after adding user functionality to show 'all bettors'
    expect(match_data_after_close['bettors']['a']).to match_array([loser.display_name])
    expect(match_data_after_close['bettors']['b']).to match_array([winner.display_name])

    expect(Bet.count).to eq(2)

    # Testing 'cannot bid after deadline' functionality
    winner_browser.post '/api/bet', {
      'forParticipant' => 'b',
      :amount => 499
    }.to_json

    expect(winner_browser.last_response).to_not be_ok


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
      expect(sleep_count).to be < 20 # Payout is bugged
    end

    # Check match data
    match_data_after_payout = Persistence::MatchStatusPersistence.get_from_file

    expect(match_data_after_payout['status']).to eq('closed')

    # Check payout amounts
    expect(User.first(:email => loser.email).balance.to_i).to eq(10) # reset
    expect(User.first(:email => winner.email).balance.to_i).to eq(505)

    expect(Bet.count).to eq(0)
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

    expect(Bet.count).to eq(0)

    # Create users
    admin = FactoryGirl.create(:admin)
    loser = FactoryGirl.create(:user, :balance => 5)
    winner = FactoryGirl.create(:user, :balance => 500)

    loser_browser = Rack::Test::Session.new(Rack::MockSession.new(app))
    winner_browser = Rack::Test::Session.new(Rack::MockSession.new(app))

    # User login
    post '/login', {
      :email => admin.email,
      :password => admin.password
    }

    loser_browser.post '/login', {
      :email => loser.email,
      :password => loser.password
    }

    winner_browser.post '/login', {
      :email => winner.email,
      :password => winner.password
    }

    # Open bidding
    put '/api/current_match', {
      :status => 'open',
      :winner => '',
      :participantA => { :name => 'A', :amount => 0},
      :participantB => { :name => 'B', :amount => 0},
      :odds => '',
    }.to_json

    expect(last_response).to be_ok

    # Bid - loser will bet 5 on A
    loser_browser.post '/api/bet', {
      'forParticipant' => 'a',
      :amount => 5
    }.to_json

    expect(loser_browser.last_response).to be_ok

    # Bid - winner will bet 500 on B
    winner_browser.post '/api/bet', {
      'forParticipant' => 'b',
      :amount => 500
    }.to_json

    expect(winner_browser.last_response).to be_ok

    # Close bidding
    put '/api/current_match', {
      :status => 'inProgress',
      :winner => '',
      :participantA => { :name => 'A', :amount => 0},
      :participantB => { :name => 'B', :amount => 0},
      :odds => '',
    }.to_json

    expect(last_response).to be_ok

    # Ensure that odds & amount are calculated
    match_data_after_close = Persistence::MatchStatusPersistence.get_from_file

    expect(match_data_after_close['participantA']['amount'].to_f).to eq(5.0)
    expect(match_data_after_close['participantB']['amount'].to_f).to eq(500.0)
    expect(match_data_after_close['odds']).to eq("1:100")

    # TODO: Change after adding user functionality to show 'all bettors'
    expect(match_data_after_close['bettors']['a']).to match_array([loser.display_name])
    expect(match_data_after_close['bettors']['b']).to match_array([winner.display_name])

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

    expect(match_data_after_cancel['status']).to eq('closed')

    # Check payout amounts to ensure that there is no payout
    expect(User.first(:email => loser.email).balance.to_i).to eq(5)
    expect(User.first(:email => winner.email).balance.to_i).to eq(500)

    expect(Bet.count).to eq(0)
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

    expect(Bet.count).to eq(0)

    # Create users
    admin = FactoryGirl.create(:admin)
    loser = FactoryGirl.create(:user, :balance => 5)
    winner = FactoryGirl.create(:user,:balance => 500)

    loser_browser = Rack::Test::Session.new(Rack::MockSession.new(app))
    winner_browser = Rack::Test::Session.new(Rack::MockSession.new(app))

    # User login
    post '/login', {
      :email => admin.email,
      :password => admin.password
    }

    loser_browser.post '/login', {
      :email => loser.email,
      :password => loser.password
    }

    winner_browser.post '/login', {
      :email => winner.email,
      :password => winner.password
    }

    # Open bidding
    put '/api/current_match', {
      :status => 'open',
      :winner => '',
      :participantA => { :name => 'A', :amount => 0},
      :participantB => { :name => 'B', :amount => 0},
      :odds => '',
    }.to_json

    expect(last_response).to be_ok

    # Bid - loser will bet 5 on A
    loser_browser.post '/api/bet', {
      'forParticipant' => 'a',
      :amount => 5
    }.to_json

    expect(loser_browser.last_response).to be_ok

    # Bid - winner will bet 500 on B
    winner_browser.post '/api/bet', {
      'forParticipant' => 'b',
      :amount => 500
    }.to_json

    expect(winner_browser.last_response).to be_ok

    # Cancel bidding
    put '/api/current_match', {
      :status => 'closed',
      :winner => '',
      :participantA => { :name => 'A', :amount => 0},
      :participantB => { :name => 'B', :amount => 0},
      :odds => '',
    }.to_json

    expect(last_response).to be_ok

    match_data_after_cancel = Persistence::MatchStatusPersistence.get_from_file

    expect(match_data_after_cancel['status']).to  eq('closed')

    # Check payout amounts to ensure that there is no payout
    expect(User.first(:email => loser.email).balance.to_i).to eq(5)
    expect(User.first(:email => winner.email).balance.to_i).to eq(500)

    expect(Bet.count).to eq(0)
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

    expect(Bet.count).to eq(0)

    # Create users
    admin = FactoryGirl.create(:admin)
    
    # User login
    post '/login', {
      :email => admin.email,
      :password => admin.password
    }

    # Open bidding
    put '/api/current_match', {
      :status => 'open',
      :winner => '',
      :participantA => { :name => 'A', :amount => 0},
      :participantB => { :name => 'B', :amount => 0},
      :odds => '',
    }.to_json

    expect(last_response).to be_ok

    # Close bidding
    put '/api/current_match', {
      :status => 'inProgress',
      :winner => '',
      :participantA => { :name => 'A', :amount => 0},
      :participantB => { :name => 'B', :amount => 0},
      :odds => '',
    }.to_json

    expect(last_response).to be_ok

    # Ensure that odds & amount are calculated
    match_data_after_close = Persistence::MatchStatusPersistence.get_from_file

    expect(match_data_after_close['participantA']['amount'].to_f).to eq(0)
    expect(match_data_after_close['participantB']['amount'].to_f).to eq(0.0)
    expect(match_data_after_close['odds']).to eq("0:0")

    # TODO: Change after adding user functionality to show 'all bettors'
    expect(match_data_after_close['bettors']['a']).to match_array([])
    expect(match_data_after_close['bettors']['b']).to match_array([])

    expect(Bet.count).to eq(0)

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

    expect(match_data_after_payout['status']).to eq('closed')

    # Check payout amounts
    expect(Bet.count).to eq(0)
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

    expect(Bet.count).to eq(0)

    # Create users
    admin = FactoryGirl.create(:admin)
    user = FactoryGirl.create(:user, balance: 2525)
    
    user_browser = Rack::Test::Session.new(Rack::MockSession.new(app))

    # User login
    post '/login', {
      :email => admin.email,
      :password => admin.password
    }

    user_browser.post '/login', {
      :email => user.email,
      :password => user.password
    }
    
    # Open bidding
    put '/api/current_match', {
      :status => 'open',
      :winner => '',
      :participantA => { :name => 'A', :amount => 0},
      :participantB => { :name => 'B', :amount => 0},
      :odds => '',
    }.to_json

    expect(last_response).to be_ok

    # Bid - User-5 will bet 10 on A
    user_browser.post '/api/bet', {
      'forParticipant' => 'a',
      :amount => 10
    }.to_json

    expect(user_browser.last_response).to be_ok
    
    # Close bidding
    put '/api/current_match', {
      :status => 'inProgress',
      :winner => '',
      :participantA => { :name => 'A', :amount => 0},
      :participantB => { :name => 'B', :amount => 0},
      :odds => '',
    }.to_json

    expect(last_response).to be_ok

    # Ensure that odds & amount are calculated
    match_data_after_close =  Persistence::MatchStatusPersistence.get_from_file

    expect(match_data_after_close['participantA']['amount'].to_f).to eq(10.0)
    expect(match_data_after_close['participantB']['amount'].to_f).to eq(0.0)
    expect(match_data_after_close['odds']).to eq("0:0")

    # TODO: Change after adding user functionality to show 'all bettors'
    expect(match_data_after_close['bettors']['a']).to match_array([])
    expect(match_data_after_close['bettors']['b']).to match_array([])

    expect(Bet.count).to eq(1)

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

    expect(match_data_after_payout['status']).to eq('closed')

    # There should be no payout
    expect(User.first(email: user.email).balance.to_i).to eq(2525)

    expect(Bet.count).to eq(0)
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

    expect(Bet.count).to eq(0)

    # Create users
    admin = FactoryGirl.create(:admin)
    user = FactoryGirl.create(:user, balance: 2525)
    
    user_browser = Rack::Test::Session.new(Rack::MockSession.new(app))

    # User login
    post '/login', {
      :email => admin.email,
      :password => admin.password
    }

    user_browser.post '/login', {
      :email => user.email,
      :password => user.password
    }
    
    # Open bidding
    put '/api/current_match', {
      :status => 'open',
      :winner => '',
      :participantA => { :name => 'A', :amount => 0},
      :participantB => { :name => 'B', :amount => 0},
      :odds => '',
    }.to_json

    expect(last_response).to be_ok

    # Bid - User-5 will bet 10 on A
    user_browser.post '/api/bet', {
      'forParticipant' => 'a',
      :amount => 10
    }.to_json

    expect(user_browser.last_response).to be_ok
    
    # Close bidding
    put '/api/current_match', {
      :status => 'inProgress',
      :winner => '',
      :participantA => { :name => 'A', :amount => 0},
      :participantB => { :name => 'B', :amount => 0},
      :odds => '',
    }.to_json

    expect(last_response).to be_ok

    # Ensure that odds & amount are calculated
    match_data_after_close =  Persistence::MatchStatusPersistence.get_from_file

    expect(match_data_after_close['participantA']['amount'].to_f).to eq(10.0)
    expect(match_data_after_close['participantB']['amount'].to_f).to eq(0.0)
    expect(match_data_after_close['odds']).to eq("0:0")

    # TODO: Change after adding user functionality to show 'all bettors'
    expect(match_data_after_close['bettors']['a']).to match_array([])
    expect(match_data_after_close['bettors']['b']).to match_array([])

    expect(Bet.count).to eq(1)

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

    expect(match_data_after_payout['status']).to eq('closed')

    # There should be no payout
    expect(User.first(:email => user.email).balance.to_i).to eq(2525)

    expect(Bet.count).to eq(0)
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

    expect(Bet.count).to eq(0)

    # Create users
    admin = FactoryGirl.create(:admin)
    user = FactoryGirl.create(:user, balance: 50)

    user_browser = Rack::Test::Session.new(Rack::MockSession.new(app))

    # User login
    post '/login', {
      :email => admin.email,
      :password => admin.password
    }

    user_browser.post '/login', {
      :email => user.email,
      :password => user.password
    }

    # Open bidding
    put '/api/current_match', {
      :status => 'open',
      :winner => '',
      :participantA => { :name => 'A', :amount => 0},
      :participantB => { :name => 'B', :amount => 0},
      :odds => '',
    }.to_json

    expect(last_response).to be_ok

    # Invalid Bet: zero
    user_browser.post '/api/bet', {
      'forParticipant' => 'a',
      :amount => 0
    }.to_json

    expect(user_browser.last_response).to_not be_ok
    expect(user_browser.last_response.body).to include('amount must be a positive integer')

    # Invalid Bet: negative integer
    user_browser.post '/api/bet', {
      'forParticipant' => 'a',
      :amount => -1
    }.to_json

    expect(user_browser.last_response).to_not be_ok
    expect(user_browser.last_response.body).to include('amount must be a positive integer')

    # Invalid Bet: negative float
    user_browser.post '/api/bet', {
      'forParticipant' => 'a',
      :amount => -1.00001
    }.to_json

    expect(user_browser.last_response).to_not be_ok
    expect(user_browser.last_response.body).to include('amount must be a positive integer')

    # Invalid Bet: positive float
    user_browser.post '/api/bet', {
      'forParticipant' => 'a',
      :amount => 1.00001
    }.to_json

    expect(user_browser.last_response).to_not be_ok
    expect(user_browser.last_response.body).to include('amount must be a positive integer')

    # Invalid Bet: over account balance
    user_browser.post '/api/bet', {
      'forParticipant' => 'a',
      :amount => 51
    }.to_json

    expect(user_browser.last_response).to_not be_ok
    expect(user_browser.last_response.body).to include('insufficient funds')

    # Invalid Bet: invalid forParticipantValue
    user_browser.post '/api/bet', {
      'forParticipant' => 'c',
      :amount => 50
    }.to_json

    expect(user_browser.last_response).to_not be_ok
    expect(user_browser.last_response.body).to include('invalid request')

    # Cancel bidding
    put '/api/current_match', {
      :status => 'closed',
      :winner => '',
      :participantA => { :name => 'A', :amount => 0},
      :participantB => { :name => 'B', :amount => 0},
      :odds => '',
    }.to_json

    expect(last_response).to be_ok

    expect(User.first(:email => user.email).balance.to_i).to eq(50)
  end
end

