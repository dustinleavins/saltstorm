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

  it "has a working 'request password reset' page" do
    get '/request_password_reset'
    expect(last_response).to be_ok
  end

  it "allows users to reset password" do
    user = FactoryBot.create(:user)
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

    expect(EmailJob.where(:to => user.email.downcase).count).to eq(2)
    expect(PasswordResetRequest.count(:email => user.email.downcase)).to eq(0)
  end

  it "handles /request_password_reset errors" do
    invalid_email = FactoryBot.attributes_for(:user)[:email]

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
    user = FactoryBot.create(:user)

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

