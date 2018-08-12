ENV['RACK_ENV'] = 'test'

require 'spec_helper'
require 'set'
require 'rspec'
require 'factory_bot'
require './models.rb'

describe 'Models::User' do
  it 'allows access to properties' do
    user = Models::User.create(:email => 'DB_TEST@example.com',
                               :password => 'password',
                               :display_name => 'DB_Test',
                               :balance => 25,
                               :permissions => ['admin','test'].to_set,
                               :post_url => 'http://www.example.com',
                               :rank => 1)

    expect(user.email).to eq('db_test@example.com')
    expect(user.display_name).to eq('DB_Test')
    expect(user.balance).to eq(25)
    expect(user.permission_entry).to eq('admin;test')
    expect(user.post_url).to eq('http://www.example.com')
    expect(user.rank).to eq(1)

    expect(user.permissions).to eq(['admin', 'test'].to_set)
  end

  it 'has functional password hash class methods' do
    salt = Models::User.generate_salt
    expect(salt).to_not be_nil

    password_digest = Models::User.generate_password_digest('password', salt)
    expect(password_digest).to_not be_nil
  end

  it 'rejects users with invalid e-mail addresses' do
    expect{FactoryBot.create(:user, :email => '')}.to raise_error(Sequel::ValidationFailed)
    expect{FactoryBot.create(:user, :email => 'test')}.to raise_error(Sequel::ValidationFailed)
  end

  it 'rejects users with invalid display_name' do
    expect{FactoryBot.create(:user, :display_name => nil)}.to raise_error(Sequel::ValidationFailed)
    expect{FactoryBot.create(:user, :display_name => '')}.to raise_error(Sequel::ValidationFailed)
    expect{FactoryBot.create(:user, :display_name => 'twenty one character')}.to raise_error(Sequel::ValidationFailed)
  end

  it 'rejects users with invalid balance' do
    expect{FactoryBot.create(:user, :balance => nil)}.to raise_error(Sequel::ValidationFailed)
  end

  it 'rejects users with invalid password' do
    expect{FactoryBot.create(:user, :password => nil)}.to raise_error(Sequel::ValidationFailed)
    expect{FactoryBot.create(:user, :password => '')}.to raise_error(Sequel::ValidationFailed)
  end

  it 'rejects user with invalid post_url' do
    expect do
      FactoryBot.create(:user, :post_url => 'non-valid URI')
    end.to raise_error(Sequel::ValidationFailed)
  end

  it 'rejects user with invalid rank' do
    expect do
      FactoryBot.create(:user, :rank => 'invalid')
    end.to raise_error(Sequel::ValidationFailed)
  end

  it 'rejects user with invalid balance' do
    expect do
      FactoryBot.create(:user, :balance => 'invalid')
    end.to raise_error(Sequel::ValidationFailed)

    expect do
      FactoryBot.create(:user, :balance => -1)
    end.to raise_error(Sequel::ValidationFailed)
  end


  it 'fills-in rank after create' do
    user = Models::User.create(:email => 'ranktest@example.com',
                               :password => 'password',
                               :display_name => 'ranktest',
                               :balance => 25)

    expect(user.rank).to_not be_nil
    expect(user.rank).to eq(0) # starting rank
  end


  it 'properly retrieves all post_urls' do
    # A previous test creates a user with non-empty post_url
    
    # These user's URLs should not be included
    FactoryBot.create(:user, :post_url => '')
    FactoryBot.create(:user, :post_url => nil)

    # This user's URL should be included
    FactoryBot.create(:user, :post_url => 'http://www.example.com/test')

    post_urls = Models::User.all_post_urls
    expect(post_urls).to_not be_nil
    expect(post_urls.length).to eq(2)
    expect(post_urls.first).to eq('http://www.example.com')
    expect(post_urls.last).to eq('http://www.example.com/test')
  end
end

describe 'Models::Bet' do
  it 'allows access to properties' do
    user = FactoryBot.create(:user)
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
    end.to raise_error(Sequel::ValidationFailed)
  end

  it 'rejects bets with invalid for_participant' do
    user = FactoryBot.create(:user)
    expect do
      Models::Bet.create(:user_id => user.id,
                         :for_participant => nil,
                         :amount => 10)
    end.to raise_error(Sequel::ValidationFailed)

    expect do
      Models::Bet.create(:user_id => user.id,
                         :for_participant => '',
                         :amount => 10)
    end.to raise_error(Sequel::ValidationFailed)
  end

  it 'rejects bets with invalid amounts' do
    user = FactoryBot.create(:user)
    expect do
      Models::Bet.create(:user_id => user.id,
                         :for_participant => 'c',
                         :amount => nil)
    end.to raise_error(Sequel::ValidationFailed)
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
    end.to raise_error(Sequel::ValidationFailed)

    expect do
      Models::EmailJob.create(:to => '',
                              :subject => 'subject',
                              :body => 'body')
    end.to raise_error(Sequel::ValidationFailed)


    expect do
      Models::EmailJob.create(:to => 'test',
                              :subject => 'subject',
                              :body => 'body')
    end.to raise_error(Sequel::ValidationFailed)
  end

  it 'rejects jobs with invalid subject' do
    expect do
      Models::EmailJob.create(:to => 'test@example.com',
                              :subject => nil,
                              :body => 'body')
    end.to raise_error(Sequel::ValidationFailed)

    expect do
      Models::EmailJob.create(:to => 'test@example.com',
                              :subject => '',
                              :body => 'body')
    end.to raise_error(Sequel::ValidationFailed)
  end

  it 'rejects jobs with invalid body' do
    expect do
      Models::EmailJob.create(:to => 'test@example.com',
                              :subject => 'subject',
                              :body => nil)
    end.to raise_error(Sequel::ValidationFailed)

    expect do
      Models::EmailJob.create(:to => 'test@example.com',
                              :subject => 'subject',
                              :body => '')
    end.to raise_error(Sequel::ValidationFailed)

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
    end.to raise_error(Sequel::ValidationFailed)

    expect do
      Models::PasswordResetRequest.create(:email => '',
                                          :code => 'code')
    end.to raise_error(Sequel::ValidationFailed)

    expect do
      Models::PasswordResetRequest.create(:email => 'test',
                                          :code => 'code')
    end.to raise_error(Sequel::ValidationFailed)
  end

  it 'rejects requests with invalid code' do
    expect do
      Models::PasswordResetRequest.create(:email => 'test@example.com',
                                          :code => '')
    end.to raise_error(Sequel::ValidationFailed)
  end

  it 'accepts requests with nil code' do
    req = Models::PasswordResetRequest.create(:email => 'test@example.com',
                                              :code => nil)

    expect(req.code).to_not be_nil
  end
end

describe 'Models::Payment' do
  it 'allows access to properties' do
    user = FactoryBot.create(:user, :balance => 100)
    payment = Models::Payment.create(
      :user => user,
      :payment_type => 'rankup',
      :amount => 10,
      :status => 'pending')

    expect(payment.user_id).to eq(user.id)
    expect(payment.user.id).to eq(user.id)
    expect(payment.payment_type).to eq('rankup')
    expect(payment.amount).to eq(10)
    expect(payment.status).to eq('pending')
    expect(payment.date_modified).to_not be_nil

    # Testing User's side of the association
    expect(user.payments).to_not be_nil
    expect(user.payments.length).to eq(1)
  end

  it 'rejects payments with invalid payment_type' do
    expect{FactoryBot.create(:payment, :payment_type => nil)}.to raise_error(Sequel::ValidationFailed)
    expect{FactoryBot.create(:payment, :payment_type => '')}.to raise_error(Sequel::ValidationFailed)
    expect{FactoryBot.create(:payment, :payment_type => 'unsupported')}.to raise_error(Sequel::ValidationFailed)
  end

  it 'rejects payments with invalid status' do
    expect{FactoryBot.create(:payment, :status => nil)}.to raise_error(Sequel::ValidationFailed)
    expect{FactoryBot.create(:payment, :status => '')}.to raise_error(Sequel::ValidationFailed)
    expect{FactoryBot.create(:payment, :status => 'not allowed')}.to raise_error(Sequel::ValidationFailed)
  end

  it 'rejects payments with invalid user_id' do
    expect{FactoryBot.create(:payment, :user => nil)}.to raise_error(Sequel::ValidationFailed)
  end

  it 'rejects payments with invalid amount' do
    user_with_low_balance = FactoryBot.create(:user, :balance => 5)
    
    expect{FactoryBot.create(:payment, :amount => 0)}.to raise_error(Sequel::ValidationFailed)
    expect{FactoryBot.create(:payment, :amount => nil)}.to raise_error(Sequel::ValidationFailed)
    
    expect do
      FactoryBot.create(:payment, :user => user_with_low_balance, :amount => 6)
    end.to raise_error(Sequel::ValidationFailed)

  end
end

describe 'Models::ApiKey' do
  it 'allows access to properties' do
    user = FactoryBot.create(:user)
    api_key = Models::ApiKey.create(:user => user,
                                    :key => 'AABBCCDD')

    expect(api_key.user).to eq(user)
    expect(api_key.key).to eq('AABBCCDD')
    expect(api_key.full_key).to eq("#{user.id}+AABBCCDD")
    expect(api_key.key_salt).to_not be_nil
    expect(api_key.key_hash).to_not be_nil
    expect(api_key.date_modified).to_not be_nil
  end

  it 'allows use of the new_with_random_key method' do
    api_key = Models::ApiKey.new_with_random_key(:user => FactoryBot.create(:user))
    expect(api_key.valid?).to be_truthy
  end
end
