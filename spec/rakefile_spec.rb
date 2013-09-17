ENV['RACK_ENV'] = 'test'

require 'rspec'
require 'mail'
require 'factory_girl'
require './models.rb'
require 'spec_helper'

describe 'email_job' do
  it 'successfully sends e-mail' do
    expect(Models::EmailJob.count).to eq(0)

    20.times do
      FactoryGirl.create(:email_job)
    end

    expect(Models::EmailJob.count).to eq(20)
    expect(`rake RACK_ENV=test`).to match(/test\s*/)
    `rake email_job RACK_ENV=test`
    expect(Models::EmailJob.count).to eq(0)
  end
end

