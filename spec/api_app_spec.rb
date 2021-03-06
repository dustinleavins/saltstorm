ENV['RACK_ENV'] = 'test'
Thread.abort_on_exception=true

require 'spec_helper'
require 'json'
require 'uri'
require 'rspec'
require 'rack/test'
require './apps/api.rb'
require './models.rb'
require './persistence.rb'

describe 'Api App' do
  include Rack::Test::Methods
  include Models

  def app
    ApiApp
  end

  it "allows api users to login and logout" do
    user = FactoryBot.create(:user)

    # Sign-in
    post '/login', {
      :email => user.email,
      :password => user.password
    }.to_json

    expect(last_response).to be_ok

    # Try a route requiring login
    get '/account'
    expect(last_response).to be_ok

    # Logout
    post '/logout'
    expect(last_response).to be_ok

    # Try a route requiring login
    get '/account'
    expect(last_response).to_not be_ok
  end

  it "allows authentication via api key" do
    user = FactoryBot.create(:user)

    put '/session', {
      :email => user.email,
      :password => user.password
    }.to_json

    expect(last_response).to be_ok
    actual_key = JSON.parse(last_response.body)['key']
    expect(actual_key).to_not be_nil

    expect(ApiKey.where(:user => user).count).to eq(1)
    api_key_record = ApiKey.first(:user => user)

    actual_hash = Models.generate_digest(actual_key.split('+', 2)[1], api_key_record.key_salt)
    expect(actual_hash).to eq(api_key_record.key_hash)

    # TODO - Test authentication with a real route
  end

  it "allows deletion of api keys" do
    api_key = FactoryBot.create(:api_key)
    expect(api_key.user.exists?).to be_truthy
    header('AUTHENTICATION', api_key.full_key)
    delete('/session')
    expect(last_response).to be_ok
    expect(ApiKey.where(:user => api_key.user).count).to eq(0)
  end

  it "allows users to register" do
    user_info = FactoryBot.attributes_for(:user)
    post '/register', {
      :email => user_info[:email],
      :password => user_info[:password],
      :confirmPassword => user_info[:password],
      :displayName => user_info[:display_name]
    }.to_json

    expect(last_response).to be_ok

    expect(User.where(:email =>user_info[:email].downcase).count).to eq(1)
    expect(EmailJob.where(:to => user_info[:email].downcase).count).to eq(1)

    # Try a route requiring login
    get '/account'
    expect(last_response).to be_ok

    # Check to see if starting balance == 400
    new_user = User.first(:email => user_info[:email].downcase)
    expect(new_user).to_not be_nil
    expect(new_user.balance).to eq(400)
  end

  it "does not allows user to register with incorrect confirm password" do
    user_info = FactoryBot.attributes_for(:user)
    post '/register', {
      :email => user_info[:email],
      :password => user_info[:password],
      :confirmPassword => user_info[:password].reverse,
      :displayName => user_info[:display_name]
    }.to_json

    expect(last_response.status).to eq(500)

    expect(User.where(:email =>user_info[:email].downcase).count).to eq(0)
    expect(EmailJob.where(:to => user_info[:email].downcase).count).to eq(0)

    # Try a route requiring login
    get '/account'
    expect(last_response).to_not be_ok
  end

  it "does not allows user to register with empty password" do
    user_info = FactoryBot.attributes_for(:user)
    post '/register', {
      :email => user_info[:email],
      :password => '',
      :confirmPassword => '',
      :displayName => user_info[:display_name]
    }.to_json

    expect(last_response.status).to eq(500)

    expect(User.where(:email =>user_info[:email].downcase).count).to eq(0)
    expect(EmailJob.where(:to => user_info[:email].downcase).count).to eq(0)

    # Try a route requiring login
    get '/account'
    expect(last_response).to_not be_ok
  end

  it "does not allows user to register with empty email" do
    user_info = FactoryBot.attributes_for(:user)
    post '/register', {
      :email => '',
      :password => user_info[:password],
      :confirmPassword => user_info[:password],
      :displayName => user_info[:display_name]
    }.to_json

    expect(last_response.status).to eq(500)

    expect(User.where(:email =>user_info[:email].downcase).count).to eq(0)
    expect(EmailJob.where(:to => user_info[:email].downcase).count).to eq(0)

    # Try a route requiring login
    get '/main'
    expect(last_response).to_not be_ok
  end

  it "does not allows user to register with empty name" do
    user_info = FactoryBot.attributes_for(:user)
    post '/register', {
      :email => user_info[:email],
      :password => user_info[:password],
      :confirmPassword => user_info[:password],
      :displayName => ''
    }.to_json

    expect(last_response.status).to eq(500)

    expect(User.where(:email =>user_info[:email].downcase).count).to eq(0)
    expect(EmailJob.where(:to => user_info[:email].downcase).count).to eq(0)

    # Try a route requiring login
    get '/account'
    expect(last_response).to_not be_ok
  end

  it "does not allows user to register with duplicate e-mail" do
    existing_user_email = FactoryBot.create(:user).email
    user_info = FactoryBot.attributes_for(:user)
    post '/register', {
      :email => existing_user_email,
      :password => user_info[:password],
      :confirmPassword => user_info[:password],
      :displayName => user_info[:display_name]
    }.to_json

    expect(last_response.status).to eq(500)

    expect(User.where(:display_name =>user_info[:display_name]).count).to eq(0)
    expect(EmailJob.where(:to => user_info[:email].downcase).count).to eq(0)

    # Try a route requiring login
    get '/account'
    expect(last_response).to_not be_ok
  end

  it "does not allows user to register with duplicate name" do
    existing_user_name = FactoryBot.create(:user).display_name
    user_info = FactoryBot.attributes_for(:user)
    post '/register', {
      :email => user_info[:email],
      :password => user_info[:password],
      :confirmPassword => user_info[:password],
      :displayName => existing_user_name 
    }.to_json

    expect(last_response.status).to eq(500)

    expect(User.where(:email =>user_info[:email]).count).to eq(0)
    expect(EmailJob.where(:to => user_info[:email].downcase).count).to eq(0)

    # Try a route requiring login
    get '/account'
    expect(last_response).to_not be_ok
  end

  it "allows user to update password" do
    user = FactoryBot.create(:user)

    # Login
    post '/login', {
      :email => user.email,
      :password => user.password
    }.to_json

    post '/account/password', {
      :password => 'password10',
      :confirmPassword => 'password10'
    }.to_json

    expect(last_response).to be_ok

    updated_user = User.first(:email => user.email.downcase)
    expected_pw_hash = User.generate_password_digest('password10',
                                                     updated_user.password_salt)

    expect(updated_user.password_hash).to eq(expected_pw_hash)
  end

  it "prevents anonymous user from updating password" do
    post '/account/password', {
      :password => 'password10',
      :confirmPassword => 'password10'
    }.to_json

    expect(last_response.status).to eq(500)
  end

  it "prevents user from updating password with invalid password" do
    user = FactoryBot.create(:user)

    # Login
    post '/login', {
      :email => user.email,
      :password => user.password
    }.to_json

    post '/account/password', {
      :password => '',
      :confirmPassword => ''
    }.to_json

    expect(last_response.status).to eq(500)

    updated_user = User.first(:email => user.email.downcase)
    unexpected_pw_hash = User.generate_password_digest('',
                                                       updated_user.password_salt)

    expect(updated_user.password_hash).to_not eq(unexpected_pw_hash)
  end


  it "allows user to update info" do
    user = FactoryBot.create(:user)

    # Login
    post '/login', {
      :email => user.email,
      :password => user.password
    }.to_json

    post '/account/info', {
      :displayName => user.display_name.reverse,
      :email => 'changed_email@example.com',
      :password => user.password
    }.to_json

    expect(last_response).to be_ok

    updated_user = User.first(:email => 'changed_email@example.com')
    expect(updated_user).to_not be_nil

    expect(updated_user.display_name).to eq(user.display_name.reverse)
  end

  it "prevents anonymous users from updating info" do
    post '/account/info', {
      :displayName => 'n/a',
      :email => 'n/a',
      :password => 'n/a'
    }.to_json

    expect(last_response.status).to eq(500)
  end

  it "prevents user from updating info with incorrect password" do
    user = FactoryBot.create(:user)

    # Login
    post '/login', {
      :email => user.email,
      :password => user.password
    }.to_json

    post '/account/info', {
      :displayName => user.display_name.reverse,
      :email => 'changed_email@example.com',
      :password => user.password.reverse
    }.to_json

    expect(last_response.status).to eq(500)
    expect(User.first(:display_name => user.display_name.reverse)).to be_nil
  end

  it "prevents user from updating info with invalid name" do
    user = FactoryBot.create(:user)

    # Login
    post '/login', {
      :email => user.email,
      :password => user.password
    }.to_json

    post '/account/info', {
      :displayName => '',
      :email => 'changed_email@example.com',
      :password => user.password
    }.to_json

    expect(last_response.status).to eq(500)

    # Ensure that the display name wasn't updated
    expect(User.first(:email => user.email).display_name).to_not be_nil
    expect(User.first(:email => user.email).display_name).to_not eq('')
  end

  it "prevents user from updating info with invalid email" do
    user = FactoryBot.create(:user)

    # Login
    post '/login', {
      :email => user.email,
      :password => user.password
    }.to_json

    post '/account/info', {
      :displayName => user.display_name.reverse,
      :email => '',
      :password => user.password
    }.to_json

    expect(last_response.status).to eq(500)

    # Ensure that the display name wasn't updated
    expect(User.first(:email => user.email)).to_not be_nil
    expect(User.first(:email => user.email).display_name).to_not eq(user.display_name.reverse)
  end

  it "prevents user from updating info with invalid email" do
    user = FactoryBot.create(:user)

    # Login
    post '/login', {
      :email => user.email,
      :password => user.password
    }.to_json

    post '/account/info', {
      :display_name => user.display_name.reverse,
      :email => '',
      :password => user.password
    }.to_json

    expect(last_response.status).to eq(500)

    # Ensure that the display name wasn't updated
    expect(User.first(:email => user.email)).to_not be_nil
    expect(User.first(:email => user.email).display_name).to_not eq(user.display_name.reverse)
  end

  it "prevents user from updating info with invalid post_url" do
    user = FactoryBot.create(:user)

    # Login
    post '/login', {
      :email => user.email,
      :password => user.password
    }.to_json

    post '/account/info', {
      :displayName => user.display_name,
      :email => user.email,
      :password => user.password,
      :postUrl => 'invalid'
    }.to_json

    expect(last_response.status).to eq(500)

    # Ensure that the post_url wasn't updated
    expect(User.first(:email => user.email)).to_not be_nil
    expect(User.first(:email => user.email).post_url).to_not eq('invalid')
  end

  it "handles /request_password_reset errors" do
    invalid_email = FactoryBot.attributes_for(:user)[:email]

    # Illegal - empty email field
    post '/request_password_reset', {
      :email => nil
    }.to_json

    expect(last_response.status).to eq(500)
    expect(EmailJob.where(:to => '').count).to eq(0)
    expect(PasswordResetRequest.where(:email => '').count).to eq(0)

    # Accepted but does nothing: non-registered user
    post '/request_password_reset', {
      :email => invalid_email
    }.to_json

    expect(last_response).to be_ok
    expect(EmailJob.where(:to => invalid_email.downcase).count).to eq(0)
    expect(PasswordResetRequest.where(:email => invalid_email.downcase).count).to eq(0)
  end

  it "allows users to request password reset" do
    user = FactoryBot.create(:user)
    new_password = "password5"
    expect(user.password).to_not be_nil
    expect(new_password).to_not eq(user.password)

    # Request Reset
    post '/request_password_reset', {
      :email => user.email
    }.to_json

    expect(last_response).to be_ok
    expect(EmailJob.where(:to => user.email.downcase).count).to eq(1)
    expect(PasswordResetRequest.count(:email => user.email.downcase)).to eq(1)

    reset_request = PasswordResetRequest.first(:email => user.email.downcase)
    expect(reset_request.code.to_s.length).to be > 1
  end

  it "doesn't explode for failed api login attempts" do
    user = FactoryBot.build(:user) # Do not save

    # Sign-in
    post '/login', {
      :email => user.email,
      :password => user.password
    }.to_json

    expect(last_response.status).to eq(500)

    # Try a route requiring login
    get '/account'
    expect(last_response).not_to be_ok
  end

  it "should not allow /account access to anon users" do
    get '/account'
    expect(last_response.status).to eq(500)
    expect(last_response.content_type.include?('application/json')).to be_truthy
  end

  it 'should not allow /send_client_notifications access to anon users' do
    post '/send_client_notifications', {
      :data => 'AAAAA'
    }.to_json

    expect(last_response.status).to eq(500)
  end

  it 'should not allow /send_client_notifications access to non-admin users' do
    # Create User
    user = FactoryBot.create(:user)
    
    # Sign-in
    post '/login', {
      :email => user.email,
      :password => user.password
    }.to_json

    expect(last_response).to be_ok

    post '/send_client_notifications', {
      :data => 'AAAAA'
    }.to_json

    expect(last_response.status).to eq(500)
  end

  it 'allows admins to send push notifications to clients' do
    # This test should never, ever send real notifications
    expect(User.all_post_urls).to be_empty

    admin = FactoryBot.create(:admin)

    # Sign-in
    post '/login', {
      :email => admin.email,
      :password => admin.password
    }.to_json

    expect(last_response).to be_ok

    post '/send_client_notifications', {
      :data => 'AAAAA'
    }.to_json

    expect(last_response).to be_ok

    response_data = JSON.parse(last_response.body)
    expect(response_data['data']).to eq('AAAAA')

    actual_update_id = Persistence::ClientNotifications.current_notification['update_id']
    expect(response_data['update_id']).to eq(actual_update_id)

    # Test what happens when users check the ID against the server's
    post '/check_client_notification', response_data.to_json
    expect(last_response).to be_ok
    expect(last_response.body).to eq('{"message":"OK"}')
  end

  it 'handles empty requests to /check_client_notification' do
    expect(Persistence::ClientNotifications.current_notification).to_not be_nil

    post '/check_client_notification'

    expect(last_response.status).to eq(500)
  end


  it 'handles non-JSON requests to /check_client_notification' do
    expect(Persistence::ClientNotifications.current_notification).to_not be_nil

    post '/check_client_notification', {
      :update_id  => 'not an update id',
      :data => 'AAAAA'
    }

    expect(last_response.status).to eq(500)
  end

  it 'handles invalid requests to /check_client_notification' do
    expect(Persistence::ClientNotifications.current_notification).to_not be_nil

    post '/check_client_notification', {
      :data => 'AAAAA'
    }.to_json

    expect(last_response.status).to eq(500)
  end

  it 'successfully checks invalid update_id during /check_client_notification' do
    expect(Persistence::ClientNotifications.current_notification).to_not be_nil

    post '/check_client_notification', {
      :update_id => 'This is not the update id',
      :data => 'AAAAA'
    }.to_json

    expect(last_response.status).to eq(500)
  end

  it 'should allow anonymous users to access /current_match GET' do

    # By this point in testing, match data might not be set
    reset_match_data
   
    expect(Bet.count).to eq(0)

    get '/current_match'
    expect(last_response).to be_ok
  end

  it "should not allow /current_match PUT access to anon users" do
    match_data = {
      :status => 'closed',
      :winner => '',
      :participants => {
        'a' => { :name => 'Player A', :amount => 0, :odds => '' },
        'b' => { :name => 'Player B', :amount => 0, :odds => '' }
      },
    }.to_json

    put '/current_match', match_data
    expect(last_response.status).to eq(500)
    expect(last_response.body).to eq('{"error":"Must be logged-in"}')
  end

  it "should not allow /current_match PUT access to non-admin users" do
    # Create User
    user = FactoryBot.create(:user)
    
    # Sign-in
    post '/login', {
      :email => user.email,
      :password => user.password
    }.to_json

    expect(last_response).to be_ok

    header "Content-Type", "application/json"

    match_data = {
      :status => 'closed',
      :winner => '',
      :participants => {
        'a' => { :name => 'Player A', :amount => 0, :odds => '' },
        'b' => { :name => 'Player B', :amount => 0, :odds => '' }
      },
    }.to_json

    put '/current_match', match_data
    expect(last_response.status).to eq(500)
    expect(last_response.body).to eq('{"error":"invalid request"}')
  end

  it 'allows users to rankup with /payment' do
    user = FactoryBot.create(:user, :balance => 20000)

    # Sign-in
    post '/login', {
      :email => user.email,
      :password => user.password
    }.to_json

    expect(last_response).to be_ok

    post('/payment', {
      :amount => 10000,
      :payment_type => 'rankup'
    }.to_json)

    expect(last_response).to be_ok

    updated_user_balance = User.first(:id => user.id).balance
    expect(updated_user_balance).to eq(10000)

    updated_user_rank = User.first(:id => user.id).rank
    expect(updated_user_rank).to eq(1)

    payment_model = Payment.first(:user_id => user.id)
    expect(payment_model).to_not be_nil
    expect(payment_model.amount).to eq(10000)
    expect(payment_model.payment_type).to eq('rankup')
    expect(payment_model.status).to eq('complete')
  end

  it 'refuses to rankup users with max rank in /payment' do
    user = FactoryBot.create(:user, :balance => 20000, :rank => 5)

    # Sign-in
    post '/login', {
      :email => user.email,
      :password => user.password
    }.to_json

    expect(last_response).to be_ok

    post('/payment', {
      :amount => 10000,
      :payment_type => 'rankup'
    }.to_json)

    expect(last_response.status).to eq(500)

    expect(User.first(:id => user.id).balance).to eq(20000) # unchanged
    expect(User.first(:id => user.id).rank).to eq(5) # unchanged

    expect(Payment.first(:user_id => user.id)).to be_nil
  end


  it 'bails out users who spend everything with /payment' do
    user = FactoryBot.create(:user, :balance => 10000)

    # Sign-in
    post '/login', {
      :email => user.email,
      :password => user.password
    }.to_json

    expect(last_response).to be_ok

    post('/payment', {
      :amount => 10000,
      :payment_type => 'rankup'
    }.to_json)

    expect(last_response).to be_ok

    updated_user_balance = User.first(:id => user.id).balance
    expect(updated_user_balance).to eq(10) # bailout

    updated_user_rank = User.first(:id => user.id).rank
    expect(updated_user_rank).to eq(1)

    payment_model = Payment.first(:user_id => user.id)
    expect(payment_model).to_not be_nil
    expect(payment_model.amount).to eq(10000)
    expect(payment_model.payment_type).to eq('rankup')
    expect(payment_model.status).to eq('complete')
  end


  it 'prevents invalid amount on /payment' do
    user = FactoryBot.create(:user, :balance => 10)

    # Sign-in
    post '/login', {
      :email => user.email,
      :password => user.password
    }.to_json

    expect(last_response).to be_ok

    post('/payment', {
      :amount => 11,
      :payment_type => 'not supported'
    }.to_json)

    expect(last_response.status).to eq(500)
  end


  it 'prevents invalid payment_type on /payment' do
    user = FactoryBot.create(:user, :balance => 1000)

    # Sign-in
    post '/login', {
      :email => user.email,
      :password => user.password
    }.to_json

    expect(last_response).to be_ok

    post('/payment', {
      :amount => 100,
      :payment_type => 'not supported'
    }.to_json)

    expect(last_response.status).to eq(500)
  end

  it "allows people to bet their fake money - test #1" do
    reset_match_data
    expect(Bet.count).to eq(0)

    # Create users
    admin = FactoryBot.create(:admin)
    loser = FactoryBot.create(:user, :balance => 21)
    winner = FactoryBot.create(:user, :balance => 10)
 
    loser_browser = Rack::Test::Session.new(Rack::MockSession.new(app))
    winner_browser = Rack::Test::Session.new(Rack::MockSession.new(app))

    # User login
    post '/login', {
      :email => admin.email,
      :password => admin.password
    }.to_json

    loser_browser.post '/login', {
      :email => loser.email,
      :password => loser.password
    }.to_json

    winner_browser.post '/login', {
      :email => winner.email,
      :password => winner.password
    }.to_json

    # Open bidding
    put '/current_match', {
      :status => 'open',
      :winner => '',
      :participants => {
        'a' => { :name => 'A', :amount => 0, :odds => ''},
        'b' => { :name => 'B', :amount => 0, :odds => ''}
      },
    }.to_json

    expect(last_response).to be_ok

    # Bid - loser will bet 10 on B
    loser_browser.post '/bet', {
      'forParticipant' => 'b',
      :amount => 10
    }.to_json

    expect(loser_browser.last_response).to be_ok

    # Bid - winner will bet 1 on A
    winner_browser.post '/bet', {
      'forParticipant' => 'a',
      :amount => 1
    }.to_json

    expect(winner_browser.last_response).to be_ok

    # Close bidding
    put '/current_match', {
      :status => 'inProgress',
      :winner => '',
      :participants => {
        'a' => { :name => 'A', :amount => 0, :odds => ''},
        'b' => { :name => 'B', :amount => 0, :odds => ''}
      },
    }.to_json

    expect(last_response).to be_ok

    # Ensure that odds & amount are calculated
    match_data_after_close = Persistence::MatchStatusPersistence.get_from_file

    expect(match_data_after_close['participants']['a']['amount'].to_f).to eq(1.0)
    expect(match_data_after_close['participants']['a']['odds']).to eq("1:10")
    expect(match_data_after_close['participants']['b']['amount'].to_f).to eq(10.0)
    expect(match_data_after_close['participants']['b']['odds']).to eq("10:1")


    # TODO: Change after adding user functionality to show 'all bettors'
    expect(match_data_after_close['bettors']['a']).to match_array([])
    expect(match_data_after_close['bettors']['b']).to match_array([])

    expect(Bet.count).to eq(2)

    # End match
    put '/current_match', {
      :status => 'payout',
      :winner => 'a',
      :participants => match_data_after_close['participants'],
    }.to_json

    expect(last_response).to be_ok

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
  # - Anonymous users should not be able to bet
  # - Users should not be able to make payments while betting
  it "allows people to bet their fake money - test #2" do
    reset_match_data
    expect(Bet.count).to eq(0)

    # Create users
    admin = FactoryBot.create(:admin)
    loser = FactoryBot.create(:user, :balance => 5)
    winner = FactoryBot.create(:user, :balance => 500)

    loser_browser = Rack::Test::Session.new(Rack::MockSession.new(app))
    winner_browser = Rack::Test::Session.new(Rack::MockSession.new(app))
    anonymous_browser = Rack::Test::Session.new(Rack::MockSession.new(app))

    # User login
    post '/login', {
      :email => admin.email,
      :password => admin.password
    }.to_json

    loser_browser.post '/login', {
      :email => loser.email,
      :password => loser.password
    }.to_json

    winner_browser.post '/login', {
      :email => winner.email,
      :password => winner.password
    }.to_json

    # Open bidding
    put '/current_match', {
      :status => 'open',
      :winner => '',
      :participants => {
        'a' => { :name => 'A', :amount => 0, :odds => ''},
        'b' => { :name => 'B', :amount => 0, :odds => ''},
      },
    }.to_json

    expect(last_response).to be_ok

    # Bid - loser will initially bet 5 on B
    loser_browser.post '/bet', {
      'forParticipant' => 'b',
      :amount => 5
    }.to_json

    expect(loser_browser.last_response).to be_ok
    
    # Bid - winner will bet 500 on B
    winner_browser.post '/bet', {
      'forParticipant' => 'b',
      :amount => 500
    }.to_json

    expect(winner_browser.last_response).to be_ok

    # Bid - loser will change bid to 5 on A
    loser_browser.post '/bet', {
      'forParticipant' => 'a',
      :amount => 5
    }.to_json

    expect(loser_browser.last_response).to be_ok

   # Anonymous user test
    anonymous_browser.post '/bet', {
      'forParticipant' => 'a',
      :amount => 5
    }.to_json

    expect(anonymous_browser.last_response.status).to eq(500)

    # Payment failure test
    loser_browser.post '/payment', {
      :payment_type => 'rankup',
      :amount => 10
    }.to_json
    
    expect(loser_browser.last_response.status).to eq(500)
    expect(JSON.parse(loser_browser.last_response.body)['error']).to(
      eq('Cannot make payment while betting'))

    # Close bidding
    put '/current_match', {
      :status => 'inProgress',
      :winner => '',
      :participants => {
        'a' => { :name => 'A', :amount => 0, :odds => ''},
        'b' => { :name => 'B', :amount => 0, :odds => ''}
      },
    }.to_json

    expect(last_response).to be_ok

    # Ensure that odds & amount are calculated
    match_data_after_close = Persistence::MatchStatusPersistence.get_from_file

    expect(match_data_after_close['participants']['a']['amount'].to_f).to eq(5.0)
    expect(match_data_after_close['participants']['a']['odds']).to eq("1:100")
    expect(match_data_after_close['participants']['b']['amount'].to_f).to eq(500.0)
    expect(match_data_after_close['participants']['b']['odds']).to eq("100:1")

    expected_bettors_a = [
      { 'displayName' => loser.display_name, 'rank' => loser.rank }
    ]

    expected_bettors_b = [
      { 'displayName' => winner.display_name, 'rank' => winner.rank }
    ]

    expect(match_data_after_close['bettors']['a']).to match_array(expected_bettors_a)
    expect(match_data_after_close['bettors']['b']).to match_array(expected_bettors_b)

    expect(Bet.count).to eq(2)

    # Testing 'cannot bid after deadline' functionality
    winner_browser.post '/bet', {
      'forParticipant' => 'b',
      :amount => 499
    }.to_json

    expect(winner_browser.last_response).to_not be_ok


    # End match
    put '/current_match', {
      :status => 'payout',
      :winner => 'b',
      :participants => match_data_after_close['participants'],
    }.to_json

    expect(last_response).to be_ok

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
    reset_match_data
    expect(Bet.count).to eq(0)

    # Create users
    admin = FactoryBot.create(:admin)
    loser = FactoryBot.create(:user, :balance => 5)
    winner = FactoryBot.create(:user, :balance => 500)

    loser_browser = Rack::Test::Session.new(Rack::MockSession.new(app))
    winner_browser = Rack::Test::Session.new(Rack::MockSession.new(app))

    # User login
    post '/login', {
      :email => admin.email,
      :password => admin.password
    }.to_json

    loser_browser.post '/login', {
      :email => loser.email,
      :password => loser.password
    }.to_json

    winner_browser.post '/login', {
      :email => winner.email,
      :password => winner.password
    }.to_json

    # Open bidding
    put '/current_match', {
      :status => 'open',
      :winner => '',
      :participants => {
        'a' => { :name => 'A', :amount => 0, :odds => ''},
        'b' => { :name => 'B', :amount => 0, :odds => ''},
      },
    }.to_json

    expect(last_response).to be_ok

    # Bid - loser will bet 5 on A
    loser_browser.post '/bet', {
      'forParticipant' => 'a',
      :amount => 5
    }.to_json

    expect(loser_browser.last_response).to be_ok

    # Bid - winner will bet 500 on B
    winner_browser.post '/bet', {
      'forParticipant' => 'b',
      :amount => 500
    }.to_json

    expect(winner_browser.last_response).to be_ok

    # Close bidding
    put '/current_match', {
      :status => 'inProgress',
      :winner => '',
      :participants => {
        'a' => { :name => 'A', :amount => 0, :odds => ''},
        'b' => { :name => 'B', :amount => 0, :odds => ''}
      },
    }.to_json

    expect(last_response).to be_ok

    # Ensure that odds & amount are calculated
    match_data_after_close = Persistence::MatchStatusPersistence.get_from_file

    expect(match_data_after_close['participants']['a']['amount'].to_f).to eq(5.0)
    expect(match_data_after_close['participants']['a']['odds']).to eq("1:100")
    expect(match_data_after_close['participants']['b']['amount'].to_f).to eq(500.0)
    expect(match_data_after_close['participants']['b']['odds']).to eq("100:1")
   
    expected_bettors_a = [
      { 'displayName' => loser.display_name, 'rank' => loser.rank }
    ]

    expected_bettors_b = [
      { 'displayName' => winner.display_name, 'rank' => winner.rank }
    ]
    expect(match_data_after_close['bettors']['a']).to match_array(expected_bettors_a)
    expect(match_data_after_close['bettors']['b']).to match_array(expected_bettors_b)

    # Cancel match - admin client data needs to updated to
    # include bid amounts & odds
    put '/current_match', {
      :status => 'closed',
      :winner => 'b',
      :participants => match_data_after_close['participants'],
    }.to_json

    # Payout is async
    match_data_after_cancel = Persistence::MatchStatusPersistence.get_from_file

    expect(match_data_after_cancel['status']).to eq('closed')

    # Check payout amounts to ensure that there is no payout
    expect(User.first(:email => loser.email).balance.to_i).to eq(5)
    expect(User.first(:email => winner.email).balance.to_i).to eq(500)

    expect(Bet.count).to eq(0)
  end

  it 'allows people to bet their fake money - test #3 tie' do
    reset_match_data
    expect(Bet.count).to eq(0)

    # Create users
    admin = FactoryBot.create(:admin)
    bettor_a = FactoryBot.create(:user, :balance => 21)
    bettor_b = FactoryBot.create(:user, :balance => 10)
 
    browser_a = Rack::Test::Session.new(Rack::MockSession.new(app))
    browser_b = Rack::Test::Session.new(Rack::MockSession.new(app))

    # User login
    post '/login', {
      :email => admin.email,
      :password => admin.password
    }.to_json

    browser_a.post '/login', {
      :email => bettor_a.email,
      :password => bettor_a.password
    }.to_json

    browser_b.post '/login', {
      :email => bettor_b.email,
      :password => bettor_b.password
    }.to_json

    # Open bidding
    put '/current_match', {
      :status => 'open',
      :winner => '',
      :participants => {
        'a' => { :name => 'A', :amount => 0, :odds => ''},
        'b'  => { :name => 'B', :amount => 0, :odds => ''}
      },
    }.to_json

    expect(last_response).to be_ok

    # Bid - bettor_a
    browser_a.post '/bet', {
      'forParticipant' => 'a',
      :amount => 5
    }.to_json

    expect(browser_a.last_response).to be_ok

    # Bid - bettor_b
    browser_b.post '/bet', {
      'forParticipant' => 'b',
      :amount => 5
    }.to_json

    expect(browser_b.last_response).to be_ok

    # Close bidding
    put '/current_match', {
      :status => 'inProgress',
      :winner => '',
      :participants => {
        'a' => { :name => 'A', :amount => 0, :odds => ''},
        'b'  => { :name => 'B', :amount => 0, :odds => ''}
      },
    }.to_json

    expect(last_response).to be_ok

    # Ensure that odds & amount are calculated
    match_data_after_close = Persistence::MatchStatusPersistence.get_from_file

    expect(match_data_after_close['participants']['a']['amount'].to_f).to eq(5.0)
    expect(match_data_after_close['participants']['a']['odds']).to eq("1:1")
    expect(match_data_after_close['participants']['b']['amount'].to_f).to eq(5.0)
    expect(match_data_after_close['participants']['b']['odds']).to eq("1:1")

    # TODO: Change after adding user functionality to show 'all bettors'
    expect(match_data_after_close['bettors']['a']).to match_array([])
    expect(match_data_after_close['bettors']['b']).to match_array([])

    expect(Bet.count).to eq(2)

    # End match
    put '/current_match', {
      :status => 'payout',
      :winner => 'tie',
      :participants => match_data_after_close['participants'],
    }.to_json

    expect(last_response).to be_ok

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

    # Payout should not occur
    expect(User.first(:email => bettor_a.email).balance.to_i).to eq(21)
    expect(User.first(:email => bettor_b.email).balance.to_i).to eq(10)

    expect(Bet.count).to eq(0)
  end


  it "allows match cancellation during betting" do
    reset_match_data
    expect(Bet.count).to eq(0)

    # Create users
    admin = FactoryBot.create(:admin)
    loser = FactoryBot.create(:user, :balance => 5)
    winner = FactoryBot.create(:user,:balance => 500)

    loser_browser = Rack::Test::Session.new(Rack::MockSession.new(app))
    winner_browser = Rack::Test::Session.new(Rack::MockSession.new(app))

    # User login
    post '/login', {
      :email => admin.email,
      :password => admin.password
    }.to_json

    loser_browser.post '/login', {
      :email => loser.email,
      :password => loser.password
    }.to_json

    winner_browser.post '/login', {
      :email => winner.email,
      :password => winner.password
    }.to_json

    # Open bidding
    put '/current_match', {
      :status => 'open',
      :winner => '',
      :participants => {
        'a' => { :name => 'A', :amount => 0, :odds => ''},
        'b' => { :name => 'B', :amount => 0, :odds => ''}
      },
    }.to_json

    expect(last_response).to be_ok

    # Bid - loser will bet 5 on A
    loser_browser.post '/bet', {
      'forParticipant' => 'a',
      :amount => 5
    }.to_json

    expect(loser_browser.last_response).to be_ok

    # Bid - winner will bet 500 on B
    winner_browser.post '/bet', {
      'forParticipant' => 'b',
      :amount => 500
    }.to_json

    expect(winner_browser.last_response).to be_ok

    # Cancel bidding
    put '/current_match', {
      :status => 'closed',
      :winner => '',
      :participants => {
        'a' => { :name => 'A', :amount => 0, :odds => ''},
        'b' => { :name => 'B', :amount => 0, :odds => ''}
      },
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
    reset_match_data
    expect(Bet.count).to eq(0)

    # Create users
    admin = FactoryBot.create(:admin)
    
    # User login
    post '/login', {
      :email => admin.email,
      :password => admin.password
    }.to_json

    # Open bidding
    put '/current_match', {
      :status => 'open',
      :winner => '',
      :participants => {
        'a' => { :name => 'A', :amount => 0, :odds => ''},
        'b' => { :name => 'B', :amount => 0, :odds => ''}
      },
    }.to_json

    expect(last_response).to be_ok

    # Close bidding
    put '/current_match', {
      :status => 'inProgress',
      :winner => '',
      :participants => {
        'a' => { :name => 'A', :amount => 0, :odds => ''},
        'b' => { :name => 'B', :amount => 0, :odds => ''}
      },
    }.to_json

    expect(last_response).to be_ok

    # Ensure that odds & amount are calculated
    match_data_after_close = Persistence::MatchStatusPersistence.get_from_file

    expect(match_data_after_close['participants']['a']['amount'].to_f).to eq(0)
    expect(match_data_after_close['participants']['a']['odds']).to eq("0:0")
    expect(match_data_after_close['participants']['b']['amount'].to_f).to eq(0.0)
    expect(match_data_after_close['participants']['b']['odds']).to eq("0:0")

    # TODO: Change after adding user functionality to show 'all bettors'
    expect(match_data_after_close['bettors']['a']).to match_array([])
    expect(match_data_after_close['bettors']['b']).to match_array([])

    expect(Bet.count).to eq(0)

    # End match
    put '/current_match', {
      :status => 'payout',
      :winner => 'a',
      :participants => match_data_after_close['participants'],
    }.to_json

    expect(last_response).to be_ok

    # Payout is async, but in this case, it' an expensive no-op
    sleep(1)
    
    # Check match data
    match_data_after_payout = Persistence::MatchStatusPersistence.get_from_file

    expect(match_data_after_payout['status']).to eq('closed')

    # Check payout amounts
    expect(Bet.count).to eq(0)
  end

  it "allows people to have one-sided matches for winner" do
    reset_match_data
    expect(Bet.count).to eq(0)

    # Create users
    admin = FactoryBot.create(:admin)
    user = FactoryBot.create(:user, balance: 2525)
    
    user_browser = Rack::Test::Session.new(Rack::MockSession.new(app))

    # User login
    post '/login', {
      :email => admin.email,
      :password => admin.password
    }.to_json

    user_browser.post '/login', {
      :email => user.email,
      :password => user.password
    }.to_json
    
    # Open bidding
    put '/current_match', {
      :status => 'open',
      :winner => '',
      :participants => {
        'a' => { :name => 'A', :amount => 0, :odds => ''},
        'b' => { :name => 'B', :amount => 0, :odds => ''},
      },
    }.to_json

    expect(last_response).to be_ok

    # Bid - User-5 will bet 10 on A
    user_browser.post '/bet', {
      'forParticipant' => 'a',
      :amount => 10
    }.to_json

    expect(user_browser.last_response).to be_ok
    
    # Close bidding
    put '/current_match', {
      :status => 'inProgress',
      :winner => '',
      :participants => { 
        'a' => { :name => 'A', :amount => 0, :odds => ''},
        'b' => { :name => 'B', :amount => 0, :odds => ''}
      },
    }.to_json

    expect(last_response).to be_ok

    # Ensure that odds & amount are calculated
    match_data_after_close =  Persistence::MatchStatusPersistence.get_from_file

    expect(match_data_after_close['participants']['a']['amount'].to_f).to eq(10.0)
    expect(match_data_after_close['participants']['a']['odds']).to eq("0:0")
    expect(match_data_after_close['participants']['b']['amount'].to_f).to eq(0.0)
    expect(match_data_after_close['participants']['b']['odds']).to eq("0:0")

    # TODO: Change after adding user functionality to show 'all bettors'
    expect(match_data_after_close['bettors']['a']).to match_array([])
    expect(match_data_after_close['bettors']['b']).to match_array([])

    expect(Bet.count).to eq(1)

    # End match
    put '/current_match', {
      :status => 'payout',
      :winner => 'a',
      :participants => match_data_after_close['participants'],
    }.to_json

    expect(last_response).to be_ok

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
    reset_match_data
    expect(Bet.count).to eq(0)

    # Create users
    admin = FactoryBot.create(:admin)
    user = FactoryBot.create(:user, balance: 2525)
    
    user_browser = Rack::Test::Session.new(Rack::MockSession.new(app))

    # User login
    post '/login', {
      :email => admin.email,
      :password => admin.password
    }.to_json

    user_browser.post '/login', {
      :email => user.email,
      :password => user.password
    }.to_json
    
    # Open bidding
    put '/current_match', {
      :status => 'open',
      :winner => '',
      :participants => {
        'a' => { :name => 'A', :amount => 0, :odds => ''},
        'b' => { :name => 'B', :amount => 0, :odds => ''}
      },
    }.to_json

    expect(last_response).to be_ok

    # Bid - User-5 will bet 10 on A
    user_browser.post '/bet', {
      'forParticipant' => 'a',
      :amount => 10
    }.to_json

    expect(user_browser.last_response).to be_ok
    
    # Close bidding
    put '/current_match', {
      :status => 'inProgress',
      :winner => '',
      :participants => {
        'a' => { :name => 'A', :amount => 0, :odds => ''},
        'b' => { :name => 'B', :amount => 0, :odds => ''}
      },
    }.to_json

    expect(last_response).to be_ok

    # Ensure that odds & amount are calculated
    match_data_after_close =  Persistence::MatchStatusPersistence.get_from_file

    expect(match_data_after_close['participants']['a']['amount'].to_f).to eq(10.0)
    expect(match_data_after_close['participants']['a']['odds']).to eq("0:0")
    expect(match_data_after_close['participants']['b']['amount'].to_f).to eq(0.0)
    expect(match_data_after_close['participants']['b']['odds']).to eq("0:0")

    # TODO: Change after adding user functionality to show 'all bettors'
    expect(match_data_after_close['bettors']['a']).to match_array([])
    expect(match_data_after_close['bettors']['b']).to match_array([])

    expect(Bet.count).to eq(1)

    # End match
    put '/current_match', {
      :status => 'payout',
      :winner => 'b',
      :participants => match_data_after_close['participants'],
    }.to_json

    expect(last_response).to be_ok

    ## Payout is async, but in this case, it's an expensive no-op
    sleep(1)

    # Check match data
    match_data_after_payout = Persistence::MatchStatusPersistence.get_from_file

    expect(match_data_after_payout['status']).to eq('closed')

    # There should be no payout
    expect(User.first(:email => user.email).balance.to_i).to eq(2525)

    expect(Bet.count).to eq(0)
  end

  it "does not allow non-positive integer bet amounts" do
    reset_match_data
    expect(Bet.count).to eq(0)

    # Create users
    admin = FactoryBot.create(:admin)
    user = FactoryBot.create(:user, balance: 50)

    user_browser = Rack::Test::Session.new(Rack::MockSession.new(app))

    # User login
    post '/login', {
      :email => admin.email,
      :password => admin.password
    }.to_json

    user_browser.post '/login', {
      :email => user.email,
      :password => user.password
    }.to_json

    # Open bidding
    put '/current_match', {
      :status => 'open',
      :winner => '',
      :participants => {
        'a' => { :name => 'A', :amount => 0, :odds => ''},
        'b' => { :name => 'B', :amount => 0, :odds => ''},
      },
    }.to_json

    expect(last_response).to be_ok

    # Invalid Bet: zero
    user_browser.post '/bet', {
      'forParticipant' => 'a',
      :amount => 0
    }.to_json

    expect(user_browser.last_response).to_not be_ok
    expect(user_browser.last_response.body).to include('amount must be a positive integer')

    # Invalid Bet: negative integer
    user_browser.post '/bet', {
      'forParticipant' => 'a',
      :amount => -1
    }.to_json

    expect(user_browser.last_response).to_not be_ok
    expect(user_browser.last_response.body).to include('amount must be a positive integer')

    # Invalid Bet: negative float
    user_browser.post '/bet', {
      'forParticipant' => 'a',
      :amount => -1.00001
    }.to_json

    expect(user_browser.last_response).to_not be_ok
    expect(user_browser.last_response.body).to include('amount must be a positive integer')

    # Invalid Bet: positive float
    user_browser.post '/bet', {
      'forParticipant' => 'a',
      :amount => 1.00001
    }.to_json

    expect(user_browser.last_response).to_not be_ok
    expect(user_browser.last_response.body).to include('amount must be a positive integer')

    # Invalid Bet: over account balance
    user_browser.post '/bet', {
      'forParticipant' => 'a',
      :amount => 51
    }.to_json

    expect(user_browser.last_response).to_not be_ok
    expect(user_browser.last_response.body).to include('insufficient funds')

    # Invalid Bet: invalid forParticipantValue
    user_browser.post '/bet', {
      'forParticipant' => 'c',
      :amount => 50
    }.to_json

    expect(user_browser.last_response).to_not be_ok
    expect(user_browser.last_response.body).to include('invalid request')

    # Cancel bidding
    put '/current_match', {
      :status => 'closed',
      :winner => '',
      :participants => {
        'a' => { :name => 'A', :amount => 0, :odds => ''},
        'b' => { :name => 'B', :amount => 0, :odds => ''},
      },
    }.to_json

    expect(last_response).to be_ok

    expect(User.first(:email => user.email).balance.to_i).to eq(50)
  end
end

