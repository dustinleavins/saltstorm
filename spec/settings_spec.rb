ENV['RACK_ENV'] = 'test'

require 'spec_helper'
require 'rspec'
require './settings.rb'

describe 'Settings Module' do
  it "successfully loads & merges site config" do
    settings = Settings::site('normal', :path => 'spec/settings_spec/site.yml')
    expect(settings['main_video_html']).to eq('video')
    expect(settings['site_name']).to eq('name')
    expect(settings['site_description']).to eq('description')
    expect(settings['user_signup_balance']).to eq(400)
    expect(settings['base_bailout_balance']).to eq(10)
  end
  
  it "properly merges site config" do
    settings = Settings::site('merge', :path => 'spec/settings_spec/site.yml')
    expect(settings['user_signup_balance']).to eq(2525)
    expect(settings['base_bailout_balance']).to eq(20)
    expect(settings['main_video_html']).to eq('video_merge')
    expect(settings['site_name']).to eq('name_merge')
    expect(settings['site_description']).to eq('description_merge')
  end

  it "does not require common site config settings" do
    settings = Settings::site('normal', :path => 'spec/settings_spec/site_nocommon.yml')
    expect(settings['main_video_html']).to eq('video')
    expect(settings['site_name']).to eq('name')
    expect(settings['site_description']).to eq('description')
    expect(settings['user_signup_balance']).to eq(400)
    expect(settings['base_bailout_balance']).to eq(10)
  end

  it "does not require environment site config settings" do
    settings = Settings::site('normal', :path => 'spec/settings_spec/site_noenvironment.yml')
    expect(settings['main_video_html']).to eq('video')
    expect(settings['site_name']).to eq('name')
    expect(settings['site_description']).to eq('description')
    expect(settings['user_signup_balance']).to eq(400)
    expect(settings['base_bailout_balance']).to eq(10)
  end

  it "successfully loads db config" do
    settings = Settings::db('normal', :path => 'spec/settings_spec/database.yml')
    expect(settings.nil?).to be_false
    expect(settings.count).to be > 0
  end

  it "successfully loads secret_key" do
    token = Settings::secret_token(:path => 'spec/settings_spec/secret_token.yml')
    expect(token).to eq('secret token')
  end
end

