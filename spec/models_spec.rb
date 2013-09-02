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
                               :permissions => ['admin','test'].to_set,
                               :post_url => 'http://www.example.com')

    expect(user.email).to eq('db_test@example.com')
    expect(user.display_name).to eq('DB_Test')
    expect(user.balance). to eq(25)
    expect(user.permission_entry).to eq('admin;test')
    expect(user.post_url).to eq('http://www.example.com')

    expect(user.permissions).to eq(['admin', 'test'].to_set)
  end

  it 'has functional password hash class methods' do
    salt = Models::User.generate_salt
    expect(salt).to_not be_nil

    password_digest = Models::User.generate_password_digest('password', salt)
    expect(password_digest).to_not be_nil
  end

  it 'rejects users with invalid e-mail addresses' do
    expect{FactoryGirl.create(:user, :email => '')}.to raise_error
    expect{FactoryGirl.create(:user, :email => 'test')}.to raise_error
  end

  it 'rejects users with invalid display_name' do
    expect{FactoryGirl.create(:user, :display_name => nil)}.to raise_error
    expect{FactoryGirl.create(:user, :display_name => '')}.to raise_error
  end

  it 'rejects users with invalid balance' do
    expect{FactoryGirl.create(:user, :balance => nil)}.to raise_error
  end

  it 'rejects users with invalid password' do
    expect{FactoryGirl.create(:user, :password => nil)}.to raise_error
    expect{FactoryGirl.create(:user, :password => '')}.to raise_error
  end

  it 'rejects user with invalid post_url' do
    expect do
      FactoryGirl.create(:user, :post_url => 'non-valid URI')
    end.to raise_error
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

  it 'rejects bets without user_ids' do
    expect do
      Models::Bet.create(:for_participant => 'a', :amount => 10)
    end.to raise_error
  end

  it 'rejects bets with invalid for_participant' do
    user = FactoryGirl.create(:user)
    expect do
      Models::Bet.create(:user_id => user.id,
                         :for_participant => nil,
                         :amount => 10)
    end.to raise_error

    expect do
      Models::Bet.create(:user_id => user.id,
                         :for_participant => '',
                         :amount => 10)
    end.to raise_error
  end

  it 'rejects bets with invalid amounts' do
    expect do
      Models::Bet.create(:user_id => user.id,
                         :for_participant => 'c',
                         :amount => nil)
    end.to raise_error
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

  it 'rejects jobs with invalid e-mail addresses' do
    expect do
      Models::EmailJob.create(:to => nil,
                              :subject => 'subject',
                              :body => 'body')
    end.to raise_error

    expect do
      Models::EmailJob.create(:to => '',
                              :subject => 'subject',
                              :body => 'body')
    end.to raise_error


    expect do
      Models::EmailJob.create(:to => 'test',
                              :subject => 'subject',
                              :body => 'body')
    end.to raise_error
  end

  it 'rejects jobs with invalid subject' do
    expect do
      Models::EmailJob.create(:to => 'test@example.com',
                              :subject => nil,
                              :body => 'body')
    end.to raise_error

    expect do
      Models::EmailJob.create(:to => 'test@example.com',
                              :subject => '',
                              :body => 'body')
    end.to raise_error
  end

  it 'rejects jobs with invalid body' do
    expect do
      Models::EmailJob.create(:to => 'test@example.com',
                              :subject => 'subject',
                              :body => nil)
    end.to raise_error

    expect do
      Models::EmailJob.create(:to => 'test@example.com',
                              :subject => 'subject',
                              :body => '')
    end.to raise_error

  end
end

describe 'Models::PasswordResetRequest' do
  it 'allows access to properties' do
    request = Models::PasswordResetRequest.create(:email => 'TO@example.com',
                                                  :code => '111')

    expect(request.email).to eq('TO@example.com')
    expect(request.code).to eq('111')
  end

  it 'rejects requests with invalid e-mail addresses' do
    expect do
      Models::PasswordResetRequest.create(:email => nil,
                                          :code => 'code')
    end.to raise_error

    expect do
      Models::PasswordResetRequest.create(:email => '',
                                          :code => 'code')
    end.to raise_error

    expect do
      Models::PasswordResetRequest.create(:email => 'test',
                                          :code => 'code')
    end.to raise_error
  end

  it 'rejects requests with invalid code' do
    expect do
      Models::PasswordResetRequest.create(:email => 'test@example.com',
                                          :code => '')
    end.to raise_error
  end

  it 'accepts requests with nil code' do
    req = Models::PasswordResetRequest.create(:email => 'test@example.com',
                                              :code => nil)

    expect(req.code).to_not be_nil
  end
end
