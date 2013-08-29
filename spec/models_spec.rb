ENV['RACK_ENV'] = 'test'

require 'set'
require 'rspec'
require 'factory_girl'
require './models.rb'
require 'spec_helper'

describe 'Models::User' do
  it 'allows access to properties' do
    user = Models::User.create(:email => 'DB_TEST@example.com',
                               :password => 'password',
                               :display_name => 'DB_Test',
                               :balance => 25,
                               :permissions => ['admin','test'].to_set)

    expect(user.email).to eq('db_test@example.com')
    expect(user.display_name).to eq('DB_Test')
    expect(user.balance). to eq(25)
    expect(user.permission_entry).to eq('admin;test')

    expect(user.permissions).to eq(['admin', 'test'].to_set)
  end


  it 'has functional password hash class methods' do
    salt = Models::User.generate_salt
    expect(salt).to_not be_nil

    password_digest = Models::User.generate_password_digest('password', salt)
    expect(password_digest).to_not be_nil
  end
end

describe 'Models::Bet' do
  it 'allows access to properties' do
    user = FactoryGirl.create(:user)
    bet = Models::Bet.create(:user_id => user.id,
                             :for_participant => 'a',
                             :amount => 10)

    expect(bet.user_id).to eq(user.id)
    expect(bet.for_participant).to eq('a')
    expect(bet.amount).to eq(10)
  end
end

describe 'Models::EmailJob' do
  it 'allows access to properties' do
    email = Models::EmailJob.create(:to => 'TO@example.com',
                                    :subject => 'subject',
                                    :body => 'body')

    expect(email.to).to eq('TO@example.com')
    expect(email.subject). to eq('subject')
    expect(email.body).to eq('body')
  end
end

describe 'Models::PasswordResetRequest' do
  it 'allows access to properties' do
    request = Models::PasswordResetRequest.create(:email => 'TO@example.com',
                                                  :code => '111')

    expect(request.email).to eq('TO@example.com')
    expect(request.code).to eq('111')
  end
end
