ENV['RACK_ENV'] = 'test'
Thread.abort_on_exception=true

require 'spec_helper'
require 'json'
require 'uri'
require 'rspec'
require 'rack/test'
require './apps/main.rb'
require './models.rb'
require './persistence.rb'

describe 'Main App' do
  include Rack::Test::Methods
  include Models

  def app
    MainApp
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

  it "allows users to login and logout" do
    user = FactoryGirl.create(:user)

    # Login
    post '/login', {
      :email => user.email,
      :password => user.password
    }

    expect(last_response).to be_redirect
    expect(last_response.location).to include('/main')

    # Try a route requiring login
    get '/main'
    expect(last_response).to be_ok

    # Logout
    get '/logout'
    expect(last_response).to be_redirect

    # Try a route requiring login
    get '/main'
    expect(last_response).to_not be_ok

  end

  it "allows users to login to main_mobile" do
    user = FactoryGirl.create(:user)

    # Login
    post '/login', {
      :email => user.email,
      :password => user.password,
      :mobile => true
    }

    expect(last_response).to be_redirect
    expect(last_response.location).to include('/main_mobile')

    # Try a route requiring login
    get '/main'
    expect(last_response).to be_ok
  end


  it "does not allow non-users to login" do
    user = FactoryGirl.build(:user) # Do not save

    # Sign-in
    post '/login', {
      :email => user.email,
      :password => user.password
    }

    expect(last_response).to be_redirect

    # Try a route requiring login
    get '/main'
    expect(last_response).to_not be_ok
  end

  it "does not allow users to login with incorrect password" do
    user = FactoryGirl.create(:user)

    # Sign-in
    post '/login', {
      :email => user.email,
      :password => user.password.reverse
    }

    expect(last_response).to be_redirect

    # Try a route requiring login
    get '/main'
    expect(last_response).to_not be_ok
  end

  it "does not allow users to login without password" do
    user = FactoryGirl.create(:user)

    # Sign-in
    post '/login', {
      :email => user.email,
    }

    expect(last_response).to be_redirect

    # Try a route requiring login
    get '/main'
    expect(last_response).to_not be_ok
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
    get '/main'
    expect(last_response).to be_ok

    # Check to see if starting balance == 400
    new_user = User.first(:email => user_info[:email].downcase)
    expect(new_user).to_not be_nil
    expect(new_user.balance).to eq(400)
  end

  it 'does not allow HTML injection on /signup' do
    post '/signup', {
      :email => '<p>Hello email</p>',
      :password => 'pass1',
      confirm_password: 'pass2',
      display_name: '<p>Hello Display Name</p>'
    }

    expect(last_response).to_not be_redirect

    response_body = last_response.body.downcase
    expect(response_body).to include('&lt;p&gt;hello email&lt;/p&gt;')
    expect(response_body).to_not include('<p>hello email</p>')

    expect(response_body).to include('&lt;p&gt;hello display name&lt;/p&gt;')
    expect(response_body).to_not include('<p>hello display name</p>')
  end

  it "does not allows user to signup with incorrect confirm password" do
    user_info = FactoryGirl.attributes_for(:user)
    post '/signup', {
      :email => user_info[:email],
      :password => user_info[:password],
      confirm_password: user_info[:password].reverse,
      display_name: user_info[:display_name]
    }

    expect(last_response).to_not be_redirect

    expect(User.where(:email =>user_info[:email].downcase).count).to eq(0)
    expect(EmailJob.where(:to => user_info[:email].downcase).count).to eq(0)

    # Try a route requiring login
    get '/main'
    expect(last_response).to_not be_ok
  end

  it "does not allows user to signup with empty password" do
    user_info = FactoryGirl.attributes_for(:user)
    post '/signup', {
      :email => user_info[:email],
      :password => '',
      confirm_password: '',
      display_name: user_info[:display_name]
    }

    expect(last_response).to_not be_redirect

    expect(User.where(:email =>user_info[:email].downcase).count).to eq(0)
    expect(EmailJob.where(:to => user_info[:email].downcase).count).to eq(0)

    # Try a route requiring login
    get '/main'
    expect(last_response).to_not be_ok
  end

  it "does not allows user to signup with empty email" do
    user_info = FactoryGirl.attributes_for(:user)
    post '/signup', {
      :email => '',
      :password => user_info[:password],
      confirm_password: user_info[:password],
      display_name: user_info[:display_name]
    }

    expect(last_response).to_not be_redirect

    expect(User.where(:email =>user_info[:email].downcase).count).to eq(0)
    expect(EmailJob.where(:to => user_info[:email].downcase).count).to eq(0)

    # Try a route requiring login
    get '/main'
    expect(last_response).to_not be_ok
  end

  it "does not allows user to signup with empty name" do
    user_info = FactoryGirl.attributes_for(:user)
    post '/signup', {
      :email => user_info[:email],
      :password => user_info[:password],
      confirm_password: user_info[:password],
      display_name: ''
    }

    expect(last_response).to_not be_redirect

    expect(User.where(:email =>user_info[:email].downcase).count).to eq(0)
    expect(EmailJob.where(:to => user_info[:email].downcase).count).to eq(0)

    # Try a route requiring login
    get '/main'
    expect(last_response).to_not be_ok
  end

  it "does not allows user to signup with duplicate e-mail" do
    existing_user_email = FactoryGirl.create(:user).email
    user_info = FactoryGirl.attributes_for(:user)
    post '/signup', {
      :email => existing_user_email,
      :password => user_info[:password],
      confirm_password: user_info[:password],
      display_name: user_info[:display_name]
    }

    expect(last_response).to_not be_redirect

    expect(User.where(:display_name =>user_info[:display_name]).count).to eq(0)
    expect(EmailJob.where(:to => user_info[:email].downcase).count).to eq(0)

    # Try a route requiring login
    get '/main'
    expect(last_response).to_not be_ok
  end

  it "does not allows user to signup with duplicate name" do
    existing_user_name = FactoryGirl.create(:user).display_name
    user_info = FactoryGirl.attributes_for(:user)
    post '/signup', {
      :email => user_info[:email],
      :password => user_info[:password],
      confirm_password: user_info[:password],
      display_name: existing_user_name 
    }

    expect(last_response).to_not be_redirect

    expect(User.where(:email =>user_info[:email]).count).to eq(0)
    expect(EmailJob.where(:to => user_info[:email].downcase).count).to eq(0)

    # Try a route requiring login
    get '/main'
    expect(last_response).to_not be_ok
  end

  it "allows users to access /main" do
    user = FactoryGirl.create(:user)

    # Sign-in
    post '/login', {
      :email => user.email,
      :password => user.password
    }

    # Try a route requiring login
    get '/main'
    expect(last_response).to be_ok
  end

  it 'allows users to access /main_mobile' do
    user = FactoryGirl.create(:user)

    # Sign-in
    post '/login', {
      :email => user.email,
      :password => user.password
    }

    # Try a route requiring login
    get '/main_mobile'
    expect(last_response).to be_ok
  end

  it "blocks anonymous users from accessing /main" do
    get '/main'
    expect(last_response).to be_redirect
  end

  it "blocks anonymous users from accessing /main_mobile" do
    get '/main_mobile'
    expect(last_response).to be_redirect
  end

  it 'allows users to access /payments' do
    user = FactoryGirl.create(:user)

    # Sign-in
    post '/login', {
      :email => user.email,
      :password => user.password
    }

    get '/payments'
    expect(last_response).to be_ok
  end

  it "blocks anonymous users from accessing /payments" do
    get '/payments'
    expect(last_response).to be_redirect
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
    get '/main'
    expect(last_response).to be_ok

    expect(EmailJob.where(:to => user.email.downcase).count).to eq(2)
    expect(PasswordResetRequest.count(:email => user.email.downcase)).to eq(0)
  end

  it 'has a working /account redirect' do
    get '/account'
    expect(last_response).to be_redirect
  end

  it 'stops anonymous users from accessing account page' do
    get '/account/'
    expect(last_response).to_not be_ok
  end

  it "has a working account page" do
    user = FactoryGirl.create(:user)

    # Login
    post '/login', {
      :email => user.email,
      :password => user.password
    }

    get '/account/'
    expect(last_response).to be_ok
  end

  it "allows user to update password" do
    user = FactoryGirl.create(:user)

    # Login
    post '/login', {
      :email => user.email,
      :password => user.password
    }

    post '/account/password', {
      :password => 'password10',
      :confirm_password => 'password10'
    }

    expect(last_response).to be_redirect # redirect to /account/

    updated_user = User.first(:email => user.email.downcase)
    expected_pw_hash = User.generate_password_digest('password10',
                                                     updated_user.password_salt)

    expect(updated_user.password_hash).to eq(expected_pw_hash)
  end

  it "prevents anonymous user from updating password" do
    post '/account/password', {
      :password => 'password10',
      :confirm_password => 'password10'
    }

    expect(last_response).to be_redirect # redirect to /login
  end

  it "prevents user from updating password with invalid password" do
    user = FactoryGirl.create(:user)

    # Login
    post '/login', {
      :email => user.email,
      :password => user.password
    }

    post '/account/password', {
      :password => '',
      :confirm_password => ''
    }

    expect(last_response).to be_redirect # redirect to /account/

    updated_user = User.first(:email => user.email.downcase)
    unexpected_pw_hash = User.generate_password_digest('',
                                                       updated_user.password_salt)

    expect(updated_user.password_hash).to_not eq(unexpected_pw_hash)
  end


  it "allows user to update info" do
    user = FactoryGirl.create(:user)

    # Login
    post '/login', {
      :email => user.email,
      :password => user.password
    }

    post '/account/info', {
      :display_name => user.display_name.reverse,
      :email => 'changed_email@example.com',
      :password => user.password
    }

    expect(last_response).to be_redirect # redirect to /account/

    updated_user = User.first(:email => 'changed_email@example.com')
    expect(updated_user).to_not be_nil

    expect(updated_user.display_name).to eq(user.display_name.reverse)
  end

  it 'does not allow HTML injection for /account info change ' do
    user = FactoryGirl.create(:user)

    # Login
    post '/login', {
      :email => user.email,
      :password => user.password
    }

    post '/account/info', {
      :display_name => '<p>hello display name</p>',
      :email => '<p>hello email</p>',
      :password => 'incorrect password'
    }

    expect(last_response).to be_redirect # redirect to /account/

    get('/account/')
    expect(last_response).to be_ok
    response_body = last_response.body.downcase

    expect(response_body).to include('&lt;p&gt;hello display name&lt;/p&gt;')
    expect(response_body).to_not include('<p>hello display name</p>')

    expect(response_body).to include('&lt;p&gt;hello email&lt;/p&gt;')
    expect(response_body).to_not include('<p>hello email</p>')
  end

  it "prevents anonymous users from updating info" do
    post '/account/info', {
      :display_name => 'n/a',
      :email => 'n/a',
      :password => 'n/a'
    }

    expect(last_response).to be_redirect # redirect to /login
  end

  it "prevents user from updating info with incorrect password" do
    user = FactoryGirl.create(:user)

    # Login
    post '/login', {
      :email => user.email,
      :password => user.password
    }

    post '/account/info', {
      :display_name => user.display_name.reverse,
      :email => 'changed_email@example.com',
      :password => user.password.reverse
    }

    expect(last_response).to be_redirect # redirect to /account/
    expect(User.first(:display_name => user.display_name.reverse)).to be_nil
  end

  it "prevents user from updating info with invalid name" do
    user = FactoryGirl.create(:user)

    # Login
    post '/login', {
      :email => user.email,
      :password => user.password
    }

    post '/account/info', {
      :display_name => '',
      :email => 'changed_email@example.com',
      :password => user.password
    }

    expect(last_response).to be_redirect # redirect to /account/

    # Ensure that the display name wasn't updated
    expect(User.first(:email => user.email).display_name).to_not be_nil
    expect(User.first(:email => user.email).display_name).to_not eq('')
  end

  it "prevents user from updating info with invalid email" do
    user = FactoryGirl.create(:user)

    # Login
    post '/login', {
      :email => user.email,
      :password => user.password
    }

    post '/account/info', {
      :display_name => user.display_name.reverse,
      :email => '',
      :password => user.password
    }

    expect(last_response).to be_redirect # redirect to /account/

    # Ensure that the display name wasn't updated
    expect(User.first(:email => user.email)).to_not be_nil
    expect(User.first(:email => user.email).display_name).to_not eq(user.display_name.reverse)
  end

  it "prevents user from updating info with invalid email" do
    user = FactoryGirl.create(:user)

    # Login
    post '/login', {
      :email => user.email,
      :password => user.password
    }

    post '/account/info', {
      :display_name => user.display_name.reverse,
      :email => '',
      :password => user.password
    }

    expect(last_response).to be_redirect # redirect to /account/

    # Ensure that the display name wasn't updated
    expect(User.first(:email => user.email)).to_not be_nil
    expect(User.first(:email => user.email).display_name).to_not eq(user.display_name.reverse)
  end

  it "prevents user from updating info with invalid post_url" do
    user = FactoryGirl.create(:user)

    # Login
    post '/login', {
      :email => user.email,
      :password => user.password
    }

    post '/account/info', {
      :display_name => user.display_name,
      :email => user.email,
      :password => user.password,
      :post_url => 'invalid'
    }

    expect(last_response).to be_redirect # redirect to /account/

    # Ensure that the post_url wasn't updated
    expect(User.first(:email => user.email)).to_not be_nil
    expect(User.first(:email => user.email).post_url).to_not eq('invalid')
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

    expect(last_response).to_not be_ok
    expect(PasswordResetRequest.count(:email => user.email.downcase)).to eq(1)

    # Invalid POST - no code
    post '/reset_password', {
      :email => user.email,
      :password => 'password',
      :confirm_password => 'password'
    }

    expect(last_response).to_not be_ok
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
end

