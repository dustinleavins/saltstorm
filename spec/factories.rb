require 'set'
require './models.rb'

FactoryGirl.define do
  to_create { |i| i.save }
  sequence :display_name do |n|
    "User-#{n}"
  end

  factory :user, class:Models::User do
    email { "#{display_name}@example.com" }
    password "password"
    display_name
    balance 10
  end

  factory :admin, class:Models::User do
    email { "#{display_name}@example.com" }
    password "password"
    sequence(:display_name) {|n| "Admin-#{n}"}
    balance 0
    permissions ['admin'].to_set
  end

  factory :email_job, class:Models::EmailJob do
    sequence(:to) {|n| "user#{n}@example.com"}
    subject 'Subject'
    body 'Body'
    sent nil
  end

  factory :payment, class:Models::Payment do
    association :user, :factory => :user, :amount => 100
    payment_type 'rankup'
    amount 10
    status 'pending'
  end
end
